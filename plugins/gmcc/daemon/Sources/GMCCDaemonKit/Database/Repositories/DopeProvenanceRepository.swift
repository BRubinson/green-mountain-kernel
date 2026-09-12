import Foundation
import GRDB

/// Reads and writes `dope_element_provenance` — the merge base. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts. The
/// merge-plan/resolve orchestrations (multi-transaction, filesystem sandbox
/// reads between them) stay on the Store facade.
///
/// Two writers, and they are deliberately the only two:
///   * `stampFromFiles` runs after a files -> db sync and records what each
///     element looked like when it arrived, clearing the dirty flag. This IS
///     the base.
///   * `markLocallyModified` runs on a granular dope mutation and sets the
///     dirty flag for the affected dot-path.
///
/// Everything is addressed by dot-path, never uuid: ingest re-mints every
/// child uuid, so uuid-keyed provenance would be erased by the operation it
/// exists to inform.
struct DopeProvenanceRepository: RepositoryContext {
    let db: Database
    let core: StoreCore


    /// Load the stored base for one scope.
    func provenance(scopeUuid: String) throws -> [String: DopeMerge.Base] {
        // Widens a 3-column list to SELECT *: the Record needs the BaseEntity
        // columns. locallyModified is decoded as Bool by GRDB (!= 0), which
        // unifies this site's old `== 1` with the three sibling `!= 0` sites --
        // a no-op on every producible value (the write path stores only 0 or 1).
        let rows = try DopeElementProvenanceRecord.fetchAll(
            db, where: "dope_scope_uuid = ?", arguments: [scopeUuid])
        var out = [String: DopeMerge.Base]()
        for row in rows {
            out[row.dotPath] = DopeMerge.Base(
                syncedContentHash: row.syncedContentHash,
                locallyModified: row.locallyModified)
        }
        return out
    }

    /// Record the base after a files -> db sync: every element that came from
    /// a file gets its hash stored and its dirty flag cleared.
    ///
    /// Rows for paths no longer present are deleted, so provenance cannot
    /// outlive the tree it describes and resurrect a stale base later.
    func stampFromFiles(scopeUuid: String, bundle: DopeDocumentBundle) throws {
        let elements = DopeMerge.elements(of: bundle)
        let now = Store.isoNow()
        let live = Set(elements.map(\.dotPath))

        for element in elements {
            try db.execute(sql: """
                INSERT INTO dope_element_provenance
                    (uuid, version, created_at, updated_at, dope_scope_uuid,
                     dot_path, element_kind, synced_content_hash, locally_modified)
                VALUES (?, 0, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                    element_kind = excluded.element_kind,
                    synced_content_hash = excluded.synced_content_hash,
                    locally_modified = 0,
                    updated_at = excluded.updated_at
                """, arguments: [UUID().uuidString.lowercased(), now, now, scopeUuid,
                                 element.dotPath, element.kind, element.contentHash])
        }

        let stale = try String.fetchAll(db, sql: """
            SELECT dot_path FROM dope_element_provenance WHERE dope_scope_uuid = ?
            """, arguments: [scopeUuid]).filter { !live.contains($0) }
        for path in stale {
            try db.execute(sql: """
                DELETE FROM dope_element_provenance
                 WHERE dope_scope_uuid = ? AND dot_path = ?
                """, arguments: [scopeUuid, path])
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
        try db.execute(sql: """
            INSERT INTO dope_element_provenance
                (uuid, version, created_at, updated_at, dope_scope_uuid,
                 dot_path, element_kind, synced_content_hash, locally_modified)
            VALUES (?, 0, ?, ?, ?, ?, ?, NULL, 1)
            ON CONFLICT(dope_scope_uuid, dot_path) DO UPDATE SET
                locally_modified = 1,
                updated_at = excluded.updated_at
            """, arguments: [UUID().uuidString.lowercased(), now, now, scopeUuid,
                             dotPath, kind])
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
            return try String.fetchOne(db, sql: """
                SELECT code FROM dope_persistence WHERE uuid = ?
                """, arguments: [nodeUuid])
        case .entity:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.' || e.code
                  FROM dope_persistence_entity e
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE e.uuid = ?
                """, arguments: [nodeUuid])
        case .property:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.' || e.code || '.' || p.code
                  FROM dope_persistence_entity_property p
                  JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE p.uuid = ?
                """, arguments: [nodeUuid])
        case .enumeration:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.enums.' || n.code
                  FROM dope_persistence_enum n
                  JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                 WHERE n.uuid = ?
                """, arguments: [nodeUuid])
        case .option:
            return try String.fetchOne(db, sql: """
                SELECT d.code || '.enums.' || n.code || '.' || o.code
                  FROM dope_persistence_enum_option o
                  JOIN dope_persistence_enum n ON n.uuid = o.dope_persistence_enum_uuid
                  JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                 WHERE o.uuid = ?
                """, arguments: [nodeUuid])
        }
    }

    /// The dot-paths this session has edited, in order.
    func locallyModifiedPaths(scopeUuid: String) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT dot_path FROM dope_element_provenance
             WHERE dope_scope_uuid = ? AND locally_modified = 1
             ORDER BY dot_path
            """, arguments: [scopeUuid])
    }
}
