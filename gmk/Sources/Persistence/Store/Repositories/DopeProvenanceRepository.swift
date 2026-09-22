import Foundation
import GRDB

/// Reads and writes `dope_element_provenance` — the merge base. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts. The
/// merge-plan/resolve orchestrations stay on the Store facade.
///
/// Two writers, deliberately the only two: `stampFromFiles` records what each
/// element looked like when it arrived and clears the dirty flag, which IS the
/// base; `markLocallyModified` sets the dirty flag for one dot-path. Everything
/// is addressed by dot-path, because ingest re-mints every child uuid.
struct DopeProvenanceRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Load the stored base for one scope.
    func provenance(scopeUuid: String) throws -> [String: DopeMerge.Base] {
        // Widens a 3-column list to SELECT *: the Record needs the BaseEntity
        // columns. locallyModified is decoded as Bool by GRDB (!= 0), which
        // unifies this site's old `== 1` with the three sibling `!= 0` sites --
        // a no-op on every producible value (the write path stores only 0 or 1).
        let rows =
            try DopeElementProvenanceRecord
            .filter(DopeElementProvenanceRecord.Columns.dopeScopeUuid == scopeUuid)
            .order(DopeElementProvenanceRecord.Columns.dotPath)
            .fetchAll(db)
        var out: [String: DopeMerge.Base] = [:]
        for row in rows {
            out[row.dotPath] = DopeMerge.Base(
                syncedContentHash: row.syncedContentHash,
                locallyModified: row.locallyModified
            )
        }
        return out
    }

    /// Record the base after a files -> db sync: every element that came from
    /// a file gets its hash stored and its dirty flag cleared.
    ///
    /// Rows for paths absent from the tree are deleted, so provenance cannot
    /// outlive what it describes and resurrect a stale base later.
    func stampFromFiles(scopeUuid: String, bundle: DopeDocumentBundle) throws {
        let elements = DopeMerge.elements(of: bundle)
        let now = Store.isoNow()
        let live = Set(elements.map(\.dotPath))

        for element in elements {
            try db.execute(
                sql: """
                    INSERT INTO dope_element_provenance
                        (uuid, version, created_at, updated_at, dope_scope_uuid,
                         dot_path, element_kind, synced_content_hash, locally_modified)
                    VALUES (?, 0, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                        element_kind = excluded.element_kind,
                        synced_content_hash = excluded.synced_content_hash,
                        locally_modified = 0,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    UUID().uuidString.lowercased(), now, now, scopeUuid,
                    element.dotPath, element.kind, element.contentHash,
                ]
            )
        }

        let stale =
            try DopeElementProvenanceRecord
            .filter(DopeElementProvenanceRecord.Columns.dopeScopeUuid == scopeUuid)
            .select(DopeElementProvenanceRecord.Columns.dotPath, as: String.self)
            .fetchAll(db)
            .filter { !live.contains($0) }
        for path in stale {
            try db.execute(
                sql: """
                    DELETE FROM dope_element_provenance
                     WHERE dope_scope_uuid = ? AND dot_path = ?
                    """,
                arguments: [scopeUuid, path]
            )
        }
    }

    /// Flag one dot-path as edited in this session.
    ///
    /// Upserts rather than requiring a prior row: an element created here has
    /// no base, and "dirty with no base" is a meaningful state the merge
    /// reads as a local addition (or, when the file also has it, as a
    /// conflict it refuses to guess about).
    func markLocallyModified(scopeUuid: String, dotPath: String, kind: String) throws {
        let now = Store.isoNow()
        try db.execute(
            sql: """
                INSERT INTO dope_element_provenance
                    (uuid, version, created_at, updated_at, dope_scope_uuid,
                     dot_path, element_kind, synced_content_hash, locally_modified)
                VALUES (?, 0, ?, ?, ?, ?, ?, NULL, 1)
                ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                    locally_modified = 1,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                UUID().uuidString.lowercased(), now, now, scopeUuid,
                dotPath, kind,
            ]
        )
    }

    /// Resolve a node's dot-path from its uuid, for the level it sits at.
    ///
    /// The merge is addressed by dot-path but the mutation verbs speak in
    /// uuids, so this is the join between them. Returns nil for a node that
    /// has already been deleted — a hard delete cascades, so by the time a
    /// delete is recorded the row may be gone; the caller marks what it can
    /// and a missing mark degrades to "not known to be dirty", which the
    /// merge treats as files-win rather than as a silent data loss.
    func dotPath(nodeUuid: String, level: DopeLevel) throws -> String? {
        switch level {
        case .scope:
            return nil  // the scope itself is not a merge element
        case .persistence:
            return
                try DopePersistenceRecord
                .all()
                .withUuid(nodeUuid)
                .select(DopePersistenceRecord.Columns.code, as: String.self)
                .fetchOne(db)
        case .entity:
            return try DopeDomainChildPath.entities()
                .withUuid(nodeUuid)
                .fetchOne(db)?
                .entityDotPath
        case .property:
            return try DopeDomainGrandchildPath.properties()
                .withUuid(nodeUuid)
                .fetchOne(db)?
                .propertyDotPath
        case .enumeration:
            return try DopeDomainChildPath.enums()
                .withUuid(nodeUuid)
                .fetchOne(db)?
                .enumDotPath
        case .option:
            return try DopeDomainGrandchildPath.options()
                .withUuid(nodeUuid)
                .fetchOne(db)?
                .optionDotPath
        }
    }

    /// The dot-paths this session has edited, in order.
    func locallyModifiedPaths(scopeUuid: String) throws -> [String] {
        try DopeElementProvenanceRecord
            .filter(DopeElementProvenanceRecord.Columns.dopeScopeUuid == scopeUuid)
            .filter(DopeElementProvenanceRecord.Columns.locallyModified)
            .order(DopeElementProvenanceRecord.Columns.dotPath)
            .select(DopeElementProvenanceRecord.Columns.dotPath, as: String.self)
            .fetchAll(db)
    }
}
