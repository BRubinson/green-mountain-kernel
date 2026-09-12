import Foundation
import GRDB

// BASE_PROJECT promotion — the third sync direction (data access half).
//
// The two that already exist are DopeBootSync (files -> db, forward-only,
// session-scoped) and dopeIngest's --adopt gate (db forward-only within ONE
// scope). This is neither: it is db -> db, ACROSS scope tiers, conditioned on
// the session's branch matching the project's configured primary branch.
//
// The copy itself is not new work — it generalizes dopeInit's
// --clone-from-session-base through the shared copyDopeTree.
//
// The predicate is a single GLOBAL HIGH-WATER MARK recorded on the base row
// (promoted_from_revision / promoted_from_updated_at), deliberately ignoring
// WHICH scope last promoted. Two failures that a naive "is the source newer
// than the base" rule does not actually prevent:
//
//   1. PING-PONG. Keying on the base's own revision lets instance A (rev 500)
//      and instance B (rev 12) overwrite each other at every alternating boot,
//      forever, because each is "newer than the base" the moment the other
//      lands.
//   2. EVENT STORM. Without a recorded high-water the same session re-promotes
//      byte-identical content at every single SessionStart.
//
// promoted_from_scope_uuid is audit-only and never appears in the predicate.
// Keeping the high-water separate from the base's own `revision` also lets
// that revision stay a forward-only counter of the base's own tree, which a
// lower-revision winner can never drag backward.

/// DOPE_PROMOTE data access. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct DopePromoteRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func promote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {

        guard let lineage = try Row.fetchOne(db, sql: """
            SELECT s.code AS session_code, i.project_uuid AS project_uuid,
                   p.primary_project_branch AS primary_branch
              FROM session s
              JOIN instance i ON i.uuid = s.instance_uuid
              JOIN project  p ON p.uuid = i.project_uuid
             WHERE s.uuid = ?
            """, arguments: [req.sessionUuid]) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        let sessionCode: String = lineage["session_code"]
        let projectUuid: String = lineage["project_uuid"]
        let primaryBranch: String = lineage["primary_branch"]

        // session.code IS the slugged branch (GitHead.sessionCode), so the
        // branch match is a pure db comparison — no git read, and no new
        // column on session.
        let expected = GitHead.sessionCode(forBranch: primaryBranch)
        guard sessionCode == expected else {
            return DopePromoteResponse(
                promoted: [], skipped: "branch_mismatch",
                detail: "session '\(sessionCode)' is not the project's primary branch "
                      + "'\(primaryBranch)' (expected session code '\(expected)')")
        }

        var sources = try dope.dopeScopeCandidates(
            sessionUuid: req.sessionUuid, scopeType: .sessionInstance, code: req.code)
        sources = sources.filter { $0.deletedOn == nil }
        guard !sources.isEmpty else {
            return DopePromoteResponse(promoted: [], skipped: "no_session_scope",
                                       detail: "this session has no SESSION_INSTANCE scope")
        }

        var promoted = [DopePromotedScope]()
        for source in sources {
            // An empty or virgin source must never blank a populated base.
            let sourceCounts = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_persistence WHERE dope_scope_uuid = ?
                """, arguments: [source.uuid]) ?? 0
            let base = try DopeScopeRecord.fetchOne(db, sql: """
                SELECT * FROM dope_scope
                 WHERE project_uuid = ? AND scope_type = 'BASE_PROJECT' AND code = ?
                """, arguments: [projectUuid, source.code]).map { $0.wireRow() }

            if let base {
                let hwRevision = try Int64.fetchOne(db, sql: """
                    SELECT promoted_from_revision FROM dope_scope WHERE uuid = ?
                    """, arguments: [base.uuid]) ?? -1
                let hwUpdated = try String.fetchOne(db, sql: """
                    SELECT promoted_from_updated_at FROM dope_scope WHERE uuid = ?
                    """, arguments: [base.uuid]) ?? ""
                // Strictly ahead of the high-water, ties broken by recency.
                let newer = source.revision > hwRevision
                    || (source.revision == hwRevision && source.updatedAt > hwUpdated)
                guard newer else { continue }
                guard sourceCounts > 0 else {
                    throw StoreError.badRequest(detail:
                        "refusing to promote an empty tree over populated BASE_PROJECT "
                        + "'\(source.code)' — publish real content first")
                }
                if req.dryRun == true {
                    promoted.append(DopePromotedScope(
                        code: source.code, baseScopeUuid: base.uuid,
                        fromRevision: hwRevision < 0 ? 0 : hwRevision,
                        toRevision: source.revision,
                        counts: DopeTreeCounts(domains: 0, entities: 0, properties: 0,
                                               enums: 0, options: 0)))
                    continue
                }
                try dope.wipeDopeTree(scopeUuid: base.uuid)
                let counts = try dope.copyDopeTree(from: source, into: base.uuid)
                // The base's own revision is ITS counter: +1, never copied
                // from the source, so it can only move forward.
                try db.execute(sql: """
                    UPDATE dope_scope
                       SET revision = revision + 1,
                           promoted_from_scope_uuid = ?,
                           promoted_from_revision = ?,
                           promoted_from_updated_at = ?,
                           updated_at = ?
                     WHERE uuid = ? AND revision = ?
                    """, arguments: [source.uuid, source.revision, source.updatedAt,
                                     Store.isoNow(), base.uuid, base.revision])
                guard db.changesCount == 1 else {
                    throw StoreError.revisionConflict(
                        scopeUuid: base.uuid, expected: base.revision,
                        actual: base.revision)
                }
                promoted.append(DopePromotedScope(
                    code: source.code, baseScopeUuid: base.uuid,
                    fromRevision: hwRevision < 0 ? 0 : hwRevision,
                    toRevision: source.revision, counts: counts))
            } else {
                guard sourceCounts > 0 else { continue }
                if req.dryRun == true {
                    promoted.append(DopePromotedScope(
                        code: source.code, baseScopeUuid: "(would be created)",
                        fromRevision: 0, toRevision: source.revision,
                        counts: DopeTreeCounts(domains: 0, entities: 0, properties: 0,
                                               enums: 0, options: 0)))
                    continue
                }
                let uuid = try core.insertBase(db, table: "dope_scope", extra: [
                    "project_uuid": projectUuid,
                    "scope_type": DopeScopeType.baseProject.rawValue,
                    "code": source.code,
                    "name": source.name,
                    "description": source.description,
                    "revision": 1,
                    "promoted_from_scope_uuid": source.uuid,
                    "promoted_from_revision": source.revision,
                    "promoted_from_updated_at": source.updatedAt,
                ])
                let counts = try dope.copyDopeTree(from: source, into: uuid)
                promoted.append(DopePromotedScope(
                    code: source.code, baseScopeUuid: uuid, fromRevision: 0,
                    toRevision: source.revision, counts: counts))
            }
        }

        for entry in promoted where req.dryRun != true {
            if let base = try dope.fetchDopeScope(uuid: entry.baseScopeUuid) {
                try dope.recordDopeChange(scope: base, action: "promote",
                                          level: .scope, nodeUuid: base.uuid,
                                          revision: base.revision)
            }
        }
        return DopePromoteResponse(
            promoted: promoted,
            skipped: promoted.isEmpty ? "up_to_date" : nil,
            detail: promoted.isEmpty
                ? "BASE_PROJECT already carries this session's latest revision" : nil)
    }
}
