import Foundation
import GRDB

extension Migrations {
    // m0030 — correct the four daemon_config layout rows that still name the
    // retired root. m0027 renamed only the KEY, so a db that was not hand-migrated
    // points at a filesystem that does not exist and PATHS_GET serves it to every
    // client; a fresh db re-seeds the stale value on first boot.
    // Values are corrected to THIS kernel's resolved root. The LIKE guard keeps
    // this a no-op on healthy rows, including a row deliberately pointed
    // elsewhere, because such a row does not name the retired root.
    /// Registers the m0030 migration to update retired root config values.
    /// - Parameter migrator: The database migrator to register the migration with.
    static func m0030_retiredRootConfigValues(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0030_retiredRootConfigValues") { db in
            let root = Paths.root.path
            let now = Store.isoNow()
            for (key, value) in [
                ("gmfs_root", root),
                ("kbite_root", "\(root)/kbites"),
                ("kbite_open_root", "\(root)/kbites/open"),
                ("kbite_digested_root", "\(root)/kbites/digested"),
            ] {
                try db.execute(
                    sql: """
                        UPDATE daemon_config SET config_value = ?, updated_at = ?
                         WHERE config_key = ? AND config_value LIKE '%/gmcc_ckfs%'
                        """,
                    arguments: [value, now, key]
                )
            }
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [30, Store.isoNow()]
            )
        }
    }
}
