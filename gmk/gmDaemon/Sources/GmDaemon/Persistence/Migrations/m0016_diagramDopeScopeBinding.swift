import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0016 — the diagram-level dope binding: which scope does this WHOLE
    // diagram read and write through. Pure ADD COLUMN.
    //
    // Distinct from, and coexisting with, the existing PER-ELEMENT
    // diagram_dope_scope / diagram_dope_entity code bindings resolved
    // through dopeScopeCandidates. Those answer "which node does this one
    // shape point at"; this answers "which scope is this canvas over".
    //
    // The prompt asked for the ITEM-tier restriction as a CHECK. It cannot
    // be one: a SQLite CHECK cannot reference another table, and ALTER
    // TABLE ADD COLUMN cannot add a CHECK at all. The restriction is a
    // Swift guard on write plus ghost-tolerant resolution on read —
    // consistent with the per-element binding, which is also a code and
    // never a SQL FK.
    static func m0016_diagramDopeScopeBinding(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0016_diagramDopeScopeBinding") { db in
            try db.execute(
                sql: """
                    ALTER TABLE diagram ADD COLUMN dope_scope_code TEXT;

                    CREATE INDEX idx_diagram_dope_scope_code ON diagram(dope_scope_code);
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [16, Store.isoNow()]
            )
        }
    }
}
