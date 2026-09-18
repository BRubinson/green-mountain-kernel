import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0009 — materialized base properties: base_origin_property_uuid.
    // A property may be materialized on a composing entity while TAGGED
    // with the BASE_COMPOSABLE property it originates from (provenance
    // without giving up a real, FK-referenceable row — relationship refs
    // target domain.entity.uuid, so uuid must exist locally).
    //
    // Plain ADD COLUMN, not the m0002/m0008 rebuild: the column is
    // nullable with no DEFAULT and joins no CHECK — exactly the case
    // SQLite's ALTER TABLE ADD COLUMN accepts with a REFERENCES clause.
    // That also avoids a DROP of dope_domain_entity_property, the table
    // every relationship and origin ref points into.
    //
    // No CHECK coupling, unlike enum/relationship: base_origin is
    // orthogonal to data_type (any type may be materialized from a
    // base); the real constraints (origin on a BASE_COMPOSABLE the
    // entity composes, matching data_type) are cross-row and live in
    // validatePropertyShape + DopeValidator.
    //
    // ON DELETE RESTRICT mirrors the sibling ref FKs: deleting a base
    // property that composing entities still tag is a refusal naming
    // the referrer, never a silent de-tagging. The ordered-delete
    // discipline is STRONGER here than for relationships — base_origin
    // is data_type-independent, so the relationship-first DELETE split
    // does not separate referrers from targets; the NULL-out steps in
    // wipeDopeTree and dopeNodeDelete precede BOTH property DELETEs.
    static func m0009_dopePropertyBaseOrigin(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0009_dopePropertyBaseOrigin") { db in
            try db.execute(
                sql: """
                    ALTER TABLE dope_domain_entity_property
                        ADD COLUMN base_origin_property_uuid TEXT
                            REFERENCES dope_domain_entity_property(uuid) ON DELETE RESTRICT;

                    CREATE INDEX idx_dope_property_base_origin_fk
                        ON dope_domain_entity_property(base_origin_property_uuid);
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [9, Store.isoNow()]
            )
        }
    }
}
