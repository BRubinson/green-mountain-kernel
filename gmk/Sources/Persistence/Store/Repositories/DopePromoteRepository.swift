import Foundation
import GRDB

// BASE_PROJECT promotion — the third sync direction (data access half). It is
// db -> db, ACROSS scope tiers, conditioned on the session's branch matching the
// project's configured primary branch, and copies through copyDopeTree.
// The predicate is a single GLOBAL HIGH-WATER MARK on the base row
// (promoted_from_revision / promoted_from_updated_at), ignoring WHICH scope last
// promoted: keying on the base's own revision lets two instances ping-pong at
// every alternating boot, and without a high-water the same session re-promotes
// identical content at every SessionStart. promoted_from_scope_uuid is audit-only.

/// DOPE_PROMOTE data access. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct DopePromoteRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// The counts a dry run reports: it copies nothing, so it can promise
    /// nothing about the tree's size.
    private static let dryRunCounts = DopeTreeCounts(
        domains: 0,
        entities: 0,
        properties: 0,
        enums: 0,
        options: 0
    )

    func promote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        guard
            let lineage = try SessionLineage.request(sessionUuid: req.sessionUuid).fetchOne(db)
        else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        // session.code IS the slugged branch (GitHead.sessionCode), so the
        // branch match is a pure db comparison — no git read, and no new
        // column on session.
        let expected = GitHead.sessionCode(forBranch: lineage.primaryBranch)
        guard lineage.sessionCode == expected else {
            return DopePromoteResponse(
                promoted: [],
                skipped: "branch_mismatch",
                detail: "session '\(lineage.sessionCode)' is not the project's primary branch "
                    + "'\(lineage.primaryBranch)' (expected session code '\(expected)')"
            )
        }

        let sources =
            try dope.dopeScopeCandidates(
                sessionUuid: req.sessionUuid,
                scopeType: .sessionInstance,
                code: req.code
            )
            .filter { $0.deletedOn == nil }
        guard !sources.isEmpty else {
            return DopePromoteResponse(
                promoted: [],
                skipped: "no_session_scope",
                detail: "this session has no SESSION_INSTANCE scope"
            )
        }

        var promoted: [DopePromotedScope] = []
        for source in sources {
            let entry = try promoteScope(
                source: source,
                projectUuid: lineage.projectUuid,
                dryRun: req.dryRun == true
            )
            if let entry { promoted.append(entry) }
        }

        for entry in promoted where req.dryRun != true {
            if let base = try dope.fetchDopeScope(uuid: entry.baseScopeUuid) {
                try dope.recordDopeChange(
                    scope: base,
                    action: "promote",
                    level: .scope,
                    nodeUuid: base.uuid,
                    revision: base.revision
                )
            }
        }
        return DopePromoteResponse(
            promoted: promoted,
            skipped: promoted.isEmpty ? "up_to_date" : nil,
            detail: promoted.isEmpty
                ? "BASE_PROJECT already carries this session's latest revision" : nil
        )
    }

    /// One source scope's promotion. nil means nothing to do: the base is
    /// already at or ahead of this source, or there is no base and no content
    /// worth creating one for.
    private func promoteScope(
        source: DopeScopeRow,
        projectUuid: String,
        dryRun: Bool
    ) throws -> DopePromotedScope? {
        // An empty or virgin source must never blank a populated base.
        let sourceCounts =
            try DopeScopePersistenceCount.request(scopeUuid: source.uuid)
            .fetchOne(db)?
            .persistenceCount ?? 0
        let base =
            try DopeScopeRecord
            .filter(DopeScopeRecord.Columns.projectUuid == projectUuid)
            .filter(DopeScopeRecord.Columns.scopeType == DopeScopeType.baseProject.rawValue)
            .filter(DopeScopeRecord.Columns.code == source.code)
            .fetchOne(db)
        guard let base else {
            return try createBase(
                source: source,
                projectUuid: projectUuid,
                sourceCounts: sourceCounts,
                dryRun: dryRun
            )
        }
        return try replaceBase(
            source: source,
            base: base,
            sourceCounts: sourceCounts,
            dryRun: dryRun
        )
    }

    /// The high-water gate and the wipe-and-copy over an existing base.
    private func replaceBase(
        source: DopeScopeRow,
        base: DopeScopeRecord,
        sourceCounts: Int,
        dryRun: Bool
    ) throws -> DopePromotedScope? {
        let hwRevision = base.promotedFromRevision ?? -1
        let hwUpdated = base.promotedFromUpdatedAt ?? ""
        // Strictly ahead of the high-water, ties broken by recency.
        let newer =
            source.revision > hwRevision
            || (source.revision == hwRevision && source.updatedAt > hwUpdated)
        guard newer else { return nil }
        guard sourceCounts > 0 else {
            throw StoreError.badRequest(
                detail:
                    "refusing to promote an empty tree over populated BASE_PROJECT "
                    + "'\(source.code)' — publish real content first"
            )
        }
        let fromRevision = hwRevision < 0 ? 0 : hwRevision
        if dryRun {
            return DopePromotedScope(
                code: source.code,
                baseScopeUuid: base.uuid,
                fromRevision: fromRevision,
                toRevision: source.revision,
                counts: Self.dryRunCounts
            )
        }
        try dope.wipeDopeTree(scopeUuid: base.uuid)
        let counts = try dope.copyDopeTree(from: source, into: base.uuid)
        // The base's own revision is ITS counter: +1, never copied
        // from the source, so it can only move forward.
        try db.execute(
            sql: """
                UPDATE dope_scope
                   SET revision = revision + 1,
                       promoted_from_scope_uuid = ?,
                       promoted_from_revision = ?,
                       promoted_from_updated_at = ?,
                       updated_at = ?
                 WHERE uuid = ? AND revision = ?
                """,
            arguments: [
                source.uuid, source.revision, source.updatedAt,
                Store.isoNow(), base.uuid, base.revision,
            ]
        )
        guard db.changesCount == 1 else {
            throw StoreError.revisionConflict(
                scopeUuid: base.uuid,
                expected: base.revision,
                actual: base.revision
            )
        }
        return DopePromotedScope(
            code: source.code,
            baseScopeUuid: base.uuid,
            fromRevision: fromRevision,
            toRevision: source.revision,
            counts: counts
        )
    }

    /// The first promotion of a code: the base row does not exist yet.
    private func createBase(
        source: DopeScopeRow,
        projectUuid: String,
        sourceCounts: Int,
        dryRun: Bool
    ) throws -> DopePromotedScope? {
        guard sourceCounts > 0 else { return nil }
        if dryRun {
            return DopePromotedScope(
                code: source.code,
                baseScopeUuid: "(would be created)",
                fromRevision: 0,
                toRevision: source.revision,
                counts: Self.dryRunCounts
            )
        }
        let uuid = try core.insertBase(
            db,
            table: "dope_scope",
            extra: [
                "project_uuid": projectUuid,
                "scope_type": DopeScopeType.baseProject.rawValue,
                "code": source.code,
                "name": source.name,
                "description": source.description,
                "revision": 1,
                "promoted_from_scope_uuid": source.uuid,
                "promoted_from_revision": source.revision,
                "promoted_from_updated_at": source.updatedAt,
            ]
        )
        let counts = try dope.copyDopeTree(from: source, into: uuid)
        return DopePromotedScope(
            code: source.code,
            baseScopeUuid: uuid,
            fromRevision: 0,
            toRevision: source.revision,
            counts: counts
        )
    }
}
