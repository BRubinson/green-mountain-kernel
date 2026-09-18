import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0019 — COGS vocabulary: primary_system becomes HULL, and
    // PersistenceOwner joins it as a second element type.
    //
    // dope_cog_element.element_type deliberately carries NO db CHECK
    // (the Swift registry governs it), which is exactly why this is a
    // table RENAME plus a plain CREATE rather than the rebuild m0018
    // needed. The cog tables are empty db-wide, so there is nothing to
    // backfill — the UPDATE below is written anyway so the migration is
    // correct on any database, not just this one.
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
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [19, Store.isoNow()]
            )
        }
    }
}
