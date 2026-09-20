import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0009 — base_origin_property_uuid: a property materialized on a composing
    // entity while tagged with the BASE_COMPOSABLE property it originates from.
    // Plain ADD COLUMN, nullable with no DEFAULT and no CHECK — the one shape
    // SQLite accepts with a REFERENCES clause, and it avoids dropping the table
    // every relationship and origin ref points into. ON DELETE RESTRICT, so the
    // NULL-out steps in wipeDopeTree and dopeNodeDelete precede BOTH property
    // DELETEs. Cross-row shape rules live in validatePropertyShape.
    static func m0009_dopePropertyBaseOrigin(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0009_dopePropertyBaseOrigin") { db in
            try db.execute(
                sql: """
                    ALTER TABLE dope_domain_entity_property
                        ADD COLUMN base_origin_property_uuid TEXT
                            REFERENCES dope_domain_entity_property(uuid) ON DELETE RESTRICT;

                    CREATE INDEX idx_dope_property_base_origin_fk
                        ON dope_domain_entity_property(base_origin_property_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [9, Store.isoNow()]
            )
        }
    }
}
