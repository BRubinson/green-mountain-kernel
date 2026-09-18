import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // The retired-root config values m0027 left behind. m0001 seeded the
    // four layout rows under the RETIRED root, and m0027 renamed only the
    // KEY (ckfs_root → gmfs_root) — so every db that was not hand-migrated
    // still points at a filesystem that no longer exists, and PATHS_GET
    // serves it to every client. Production is healthy only because
    // migrate_to_gmfs.sh rewrote its absolute roots by hand; a FRESH db
    // (each non-prod environment mints one) re-seeds the stale value on
    // first boot and this migration corrects it in the same pass.
    //
    // Values are corrected to THIS kernel's resolved root. The LIKE guard
    // is what keeps this a no-op on healthy rows — prod keeps ~/gmfs, and
    // a row someone already pointed elsewhere on purpose is not touched
    // either, because it does not name the retired root.
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
