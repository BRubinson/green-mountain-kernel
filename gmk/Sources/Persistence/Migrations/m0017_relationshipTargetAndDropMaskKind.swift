import Foundation
import GRDB

extension Migrations {
    // m0017 — two shape corrections, both plain ALTERs.
    // (1) related_property_uuid -> relationship_target_uuid. The table's CHECK is
    // a biconditional on data_type = 'relationship', so the column is exclusively
    // that relationship's target. SQLite's RENAME COLUMN rewrites both the CHECK
    // expression and the index definition, so no rebuild.
    // (2) mask_kind is DROPPED from all seven tables. The overlay rule reduces
    // to: a node present in the overlay overrides, deleted_on means deleted, join
    // on code. ALTER TABLE DROP COLUMN handles the column's inline CHECK.
    static func m0017_relationshipTargetAndDropMaskKind(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0017_relationshipTargetAndDropMaskKind") { db in
            try db.execute(
                sql: """
                    ALTER TABLE dope_persistence_entity_property
                        RENAME COLUMN related_property_uuid TO relationship_target_uuid;
                    """
            )

            for table in [
                "dope_persistence", "dope_persistence_entity",
                "dope_persistence_entity_property", "dope_persistence_enum",
                "dope_persistence_enum_option", "dope_cog", "dope_cog_element",
            ] {
                try db.execute(sql: "ALTER TABLE \(table) DROP COLUMN mask_kind;")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [17, Store.isoNow()]
            )
        }
    }
}
