import Foundation
import GRDB

/// Reads and writes `dope_element_provenance` — the merge base.
///
/// Runs in a Store-owned transaction with no dbQueue. Two writers,
/// deliberately the only two: `stampFromFiles` records element state on
/// arrival and clears the dirty flag (the base); `markLocallyModified` sets
/// it for one dot-path. Everything is addressed by dot-path; ingest
/// re-mints every child uuid.
struct DopeProvenanceRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Loads the stored merge base for one scope.
    /// - Parameter scopeUuid: The scope identifier.
    /// - Returns: A map of dot-paths to their base values.
    /// - Throws: Any database error.
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

    /// Records the merge base after a files-to-db sync.
    ///
    /// Every element from a file gets its hash stored and dirty flag cleared.
    /// Rows for paths absent from the tree are deleted, so provenance cannot
    /// outlive what it describes and resurrect a stale base.
    /// - Parameters:
    ///   - scopeUuid: The scope identifier.
    ///   - bundle: The document bundle loaded from files.
    /// - Throws: Any database error.
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

    /// Marks a dot-path as edited in this session.
    ///
    /// Upserts rather than requiring a prior row: an element created here has
    /// no base, and "dirty with no base" is a meaningful state the merge reads
    /// as a local addition (or a conflict it refuses to guess about).
    /// - Parameters:
    ///   - scopeUuid: The scope identifier.
    ///   - dotPath: The element's dot-path.
    ///   - kind: The element kind (e.g., "entity", "property").
    /// - Throws: Any database error.
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

    /// Records a merge resolution into the base for conflicting paths.
    ///
    /// Taking theirs clears the dirty flag so the next sync treats the file as
    /// untouched. Taking ours re-bases onto the file's current hash while
    /// staying dirty, keeping the local edit and preventing file-moved conflict.
    /// - Parameters:
    ///   - scopeUuid: The scope identifier.
    ///   - dotPaths: The conflicting dot-paths to resolve.
    ///   - takeOurs: True to keep local changes; false to take the file.
    ///   - theirHashes: Map of dot-paths to the file's current hashes.
    /// - Throws: Any database error.
    func recordResolutions(
        scopeUuid: String,
        dotPaths: [String],
        takeOurs: Bool,
        theirHashes: [String: String]
    ) throws {
        let now = Store.isoNow()
        for dotPath in dotPaths {
            if takeOurs {
                try db.execute(
                    sql: """
                        UPDATE dope_element_provenance
                           SET synced_content_hash = ?, locally_modified = 1, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """,
                    arguments: [
                        theirHashes[dotPath], now,
                        scopeUuid, dotPath,
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE dope_element_provenance
                           SET locally_modified = 0, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """,
                    arguments: [now, scopeUuid, dotPath]
                )
            }
        }
    }

    /// Resolves a node's dot-path from its uuid at a given level.
    ///
    /// The merge is addressed by dot-path but mutations speak in uuids; this
    /// joins them. Returns nil for a deleted node: hard delete cascades, so
    /// the row may be gone by recording time. The caller marks what it can;
    /// a missing mark degrades to "not known to be dirty", treated as files-win.
    /// - Parameters:
    ///   - nodeUuid: The node identifier.
    ///   - level: The hierarchy level where the node sits.
    /// - Returns: The dot-path, or nil if the node is deleted.
    /// - Throws: Any database error.
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
    /// - Parameter scopeUuid: The scope identifier.
    /// - Returns: All locally modified dot-paths, in order.
    /// - Throws: Any database error.
    func locallyModifiedPaths(scopeUuid: String) throws -> [String] {
        try DopeElementProvenanceRecord
            .filter(DopeElementProvenanceRecord.Columns.dopeScopeUuid == scopeUuid)
            .filter(DopeElementProvenanceRecord.Columns.locallyModified)
            .order(DopeElementProvenanceRecord.Columns.dotPath)
            .select(DopeElementProvenanceRecord.Columns.dotPath, as: String.self)
            .fetchAll(db)
    }
}
