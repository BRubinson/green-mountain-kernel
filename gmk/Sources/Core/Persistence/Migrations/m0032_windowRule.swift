import Foundation
import GRDB

extension Migrations {
    // m0032 — window_rule: one tile/float disposition per (machine, bundle id).
    /// Creates the `window_rule` table and its unique (machine, bundle) index.
    /// - Parameter migrator: The database migrator.
    static func m0032_windowRule(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0032_windowRule") { db in
            try db.execute(
                sql: """
                    CREATE TABLE window_rule (
                        \(baseColumns),
                        machine_uuid TEXT NOT NULL REFERENCES machine(uuid) ON DELETE CASCADE,
                        bundle_id TEXT NOT NULL,
                        app_name TEXT NOT NULL,
                        disposition TEXT NOT NULL
                    );
                    CREATE UNIQUE INDEX idx_window_rule_machine_bundle
                        ON window_rule(machine_uuid, bundle_id);
                    """
            )
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [32, Store.isoNow()]
            )
        }
    }
}
