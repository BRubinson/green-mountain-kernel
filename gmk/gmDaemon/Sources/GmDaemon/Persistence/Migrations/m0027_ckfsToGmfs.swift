import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0027 — GMFS is retired for GMFS. Four column renames plus one
    // value-preserving config-key rename.
    //
    // WHY THIS IS A RENAME AND NOT A NEW COLUMN: the whole point is that
    // the Swift property renames WITH it. GRDB decodes these records with
    // `convertFromSnakeCase`, so `gmfsRelativeStoragePath` maps to
    // `gmfs_relative_storage_path` and nothing else. Leaving the column
    // named `ckfs_*` while the property says `gmfs_*` would force explicit
    // `CodingKeys` on four record types — which is exactly the
    // schema/symbol drift the comments in this file exist to prevent.
    //
    // WHY IT IS APPENDED RATHER THAN FOLDED INTO m0001: m0001 has shipped.
    // Editing its body would break replay-from-scratch while leaving
    // already-migrated databases working — the worst of both, and the
    // failure would surface on a fresh install rather than here.
    //
    // NO REBUILD IS NEEDED. Verified: no VIEW and no TRIGGER body names
    // `ckfs_relative_storage_path` (the FTS triggers cover other tables),
    // and SQLite's ALTER TABLE RENAME COLUMN preserves every row, index and
    // constraint. That is why this is four statements rather than four
    // create-copy-drop-rename rebuilds.
    //
    // The `daemon_config` step renames the KEY and leaves the VALUE
    // untouched. A row whose value still points at an old absolute path is
    // a correct row for a database that has not moved yet; rewriting values
    // here would mean this migration guessed at a filesystem layout it
    // cannot see.
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
                        """)
            }

            try db.execute(
                sql: """
                    UPDATE daemon_config SET config_key = 'gmfs_root'
                     WHERE config_key = 'ckfs_root';
                    """)

            let after = try renamed.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "prompt",
                    detail: "m0027 row-count mismatch: before \(before) after \(after)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [27, Store.isoNow()]
            )
        }
    }
}
