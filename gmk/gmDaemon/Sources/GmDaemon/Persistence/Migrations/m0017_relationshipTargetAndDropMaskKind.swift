import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0017 — two naming/shape corrections, both plain ALTERs.
    //
    // (1) related_property_uuid -> relationship_target_uuid.
    // The old name read as if it were a general "related property" link.
    // It is not: the table's own CHECK is a BICONDITIONAL,
    //   CHECK ((data_type = 'relationship') = (... IS NOT NULL))
    // so the column is set for relationship properties and NULL for every
    // other data_type. It is exclusively the relationship's target. All 50
    // relationship properties in the shipped tree point at a `.uuid`, so
    // the name was carrying an ambiguity the data never had.
    //
    // SQLite's RENAME COLUMN rewrites both the CHECK expression and the
    // index definition, so this needs no rebuild.
    //
    // (2) mask_kind is DROPPED from all seven tables that carried it.
    // It marked a "PASSTHROUGH" ancestor shell whose field values must not
    // override the base. That is only necessary if copy-up materializes
    // EMPTY ancestors; a copy-up that carries the base's real values makes
    // the simpler rule exact:
    //
    //     a node present in the overlay overrides
    //     deleted_on set means deleted
    //     join on code, nothing else
    //
    // Nothing ever wrote the column — the copy-up verb it was guarding was
    // never built — so this removes unused machinery rather than a
    // behavior. The tradeoff being accepted: an overlay's copied ancestors
    // freeze at fork time instead of tracking later base edits.
    //
    // ALTER TABLE DROP COLUMN handles the inline CHECK on the column
    // itself (verified against the SQLite build in use), so no rebuild.
    static func m0017_relationshipTargetAndDropMaskKind(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0017_relationshipTargetAndDropMaskKind") { db in
            try db.execute(
                sql: """
                    ALTER TABLE dope_persistence_entity_property
                        RENAME COLUMN related_property_uuid TO relationship_target_uuid;
                    """)

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
