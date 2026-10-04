import Foundation
import GRDB

extension Migrations {
    // m0016 — diagram.dope_scope binding: which scope this WHOLE diagram reads
    // and writes through, distinct from the per-element code bindings resolved
    // through dopeScopeCandidates. Pure ADD COLUMN. The ITEM-tier restriction
    // cannot be a CHECK — a SQLite CHECK cannot reference another table, and
    // ALTER TABLE ADD COLUMN cannot add one at all — so it is a Swift guard on
    // write plus ghost-tolerant resolution on read.
    /// Registers migration m0016: adds diagram.dope_scope column.
    /// - Parameter migrator: The database migrator to register with.
    static func m0016_diagramDopeScopeBinding(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0016_diagramDopeScopeBinding") { db in
            try db.execute(
                sql: """
                    ALTER TABLE diagram ADD COLUMN dope_scope_code TEXT;

                    CREATE INDEX idx_diagram_dope_scope_code ON diagram(dope_scope_code);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [16, Store.isoNow()]
            )
        }
    }
}
