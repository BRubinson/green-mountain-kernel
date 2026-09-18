import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0008 — BASE_COMPOSABLE entities + the base_composable_uuid self-FK.
    // SQLite cannot ALTER a CHECK, so dope_domain_entity is REBUILT in the m0002
    // order. Registered .deferred with NO PRAGMA in this body: the property
    // table CASCADE-references this one, so with FK enforcement live the DROP
    // would take every property row. The self-FK is written against the FINAL
    // table name — under foreign_keys=OFF a RENAME does not rewrite REFERENCES.
    // ON DELETE RESTRICT means wipeDopeTree and domain-delete must NULL every
    // base_composable_uuid in scope BEFORE the domain CASCADE.
    static func m0008_dopeBaseComposableEntities(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0008_dopeBaseComposableEntities") { db in
            try db.execute(
                sql: """
                    CREATE TABLE dope_domain_entity_new (
                        \(baseColumns),
                        dope_domain_uuid TEXT NOT NULL
                            REFERENCES dope_domain(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        entity_type TEXT NOT NULL DEFAULT 'MODEL'
                            CHECK (entity_type IN ('MODEL', 'JUNCTION', 'BASE_COMPOSABLE')),
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        repo_representative_file TEXT,
                        base_composable_uuid TEXT
                            REFERENCES dope_domain_entity(uuid) ON DELETE RESTRICT,
                        UNIQUE(dope_domain_uuid, code),
                        CHECK (base_composable_uuid IS NULL OR base_composable_uuid != uuid)
                    );

                    INSERT INTO dope_domain_entity_new
                        (id, uuid, version, created_at, updated_at,
                         dope_domain_uuid, code, name, entity_type, description,
                         sort_order, repo_representative_file, base_composable_uuid)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_domain_uuid, code, name, entity_type, description,
                           sort_order, repo_representative_file, NULL
                      FROM dope_domain_entity;

                    DROP TABLE dope_domain_entity;
                    ALTER TABLE dope_domain_entity_new RENAME TO dope_domain_entity;

                    CREATE INDEX idx_dope_domain_entity_domain_fk
                        ON dope_domain_entity(dope_domain_uuid);
                    CREATE INDEX idx_dope_entity_base_composable_fk
                        ON dope_domain_entity(base_composable_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [8, Store.isoNow()]
            )
        }
    }
}
