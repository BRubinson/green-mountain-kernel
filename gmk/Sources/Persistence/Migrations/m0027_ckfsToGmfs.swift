import Foundation
import GRDB

extension Migrations {
    // m0027 — four column renames plus one value-preserving config-key rename.
    // A RENAME rather than a new column because the Swift property renames with
    // it: GRDB decodes these records with convertFromSnakeCase, so
    // `gmfsRelativeStoragePath` maps to `gmfs_relative_storage_path` and nothing
    // else. No rebuild is needed — no VIEW or TRIGGER body names the old column,
    // and ALTER TABLE RENAME COLUMN preserves every row, index and constraint.
    // The daemon_config step renames the KEY and leaves the VALUE untouched:
    // rewriting values would guess at a filesystem layout it cannot see.
    /// Registers migration m0027: renames CKFS columns to GMFS and updates config keys.
    /// - Parameter migrator: The database migrator to register this migration with.
    static func m0027_ckfsToGmfs(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0027_ckfsToGmfs") { db in
            let renamed = ["project", "instance", "session", "prompt"]

            // Proven, not hoped for — the m0012 precedent. A RENAME COLUMN
            // cannot lose rows, so this is cheap insurance rather than a real
            // suspicion; it costs four COUNT(*)s and it is what makes the
            // claim "data preserved" a checked one.
            let before = try renamed.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }

            for table in renamed {
                try db.execute(
                    sql: """
                        ALTER TABLE \(table)
                            RENAME COLUMN ckfs_relative_storage_path
                                       TO gmfs_relative_storage_path;
                        """
                )
            }

            try db.execute(
                sql: """
                    UPDATE daemon_config SET config_key = 'gmfs_root'
                     WHERE config_key = 'ckfs_root';
                    """
            )

            let after = try renamed.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "prompt",
                    detail: "m0027 row-count mismatch: before \(before) after \(after)"
                )
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [27, Store.isoNow()]
            )
        }
    }
}
