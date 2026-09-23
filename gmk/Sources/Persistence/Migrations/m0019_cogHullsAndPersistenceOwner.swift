import Foundation
import GRDB

extension Migrations {
    /// Registers the m0019 migration: renames primary_system to hull.
    ///
    /// PersistenceOwner joins as a second element type. No db CHECK enforces
    /// element_type (the Swift registry governs it), so this is a table RENAME
    /// plus CREATE rather than a rebuild.
    /// - Parameter migrator: The database migrator to register with.
    static func m0019_cogHullsAndPersistenceOwner(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0019_cogHullsAndPersistenceOwner") { db in
            try db.execute(
                sql: """
                    ALTER TABLE dope_cog_primary_system RENAME TO dope_cog_hull;

                    UPDATE dope_cog_element
                       SET element_type = 'hull'
                     WHERE element_type = 'primary_system';

                    CREATE TABLE dope_cog_persistence_owner (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES dope_cog_element(uuid) ON DELETE CASCADE,
                        -- A dot-path CODE, never a uuid FK: dopeIngest re-mints
                        -- every child uuid, so a uuid here would go stale on the
                        -- next re-ingest. Ghost-tolerant and resolved at read
                        -- time, per the diagram_dope_scope precedent.
                        dope_persistence_code TEXT NOT NULL
                    );

                    CREATE INDEX idx_dope_cog_persistence_owner_element_fk
                        ON dope_cog_persistence_owner(element_uuid);
                    CREATE INDEX idx_dope_cog_persistence_owner_code
                        ON dope_cog_persistence_owner(dope_persistence_code);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [19, Store.isoNow()]
            )
        }
    }
}
