import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0012 — the Dope*Domain* -> Dope*Persistence* rename, carried all
    // the way down to the SQL table and column names, FUSED with the
    // deleted_on soft delete, the mask_kind overlay marker, and the
    // per-subtree content_revision.
    //
    // Fusing them is not an optimization, it is the same operation:
    // UNIQUE(parent, code) is an INLINE TABLE CONSTRAINT that SQLite
    // cannot drop, so converting it to a partial index
    // (WHERE deleted_on IS NULL, which is what makes delete-then-re-add
    // of the same code work) requires exactly the five-table rebuild the
    // rename already requires. Rebuilding five heavily-FK'd tables twice
    // in one release, against an append-only db that is never wiped, is
    // how you lose a database.
    //
    // Because the target names are NEW, this needs no ALTER..RENAME at
    // all: create with final REFERENCES text, copy, drop the old five.
    // That sidesteps m0008's documented hazard entirely (under
    // foreign_keys=OFF a RENAME does not rewrite REFERENCES clauses).
    //
    // Registered with GRDB's default .deferred foreignKeyChecks and NO
    // PRAGMA in this body — m0008's rule, and it matters more here: five
    // tables CASCADE-reference each other, so with enforcement live the
    // DROPs would cascade the data away.
    //
    // Copy order is parent-first; DROP order is child-first. `id` is
    // copied EXPLICITLY so rowids and therefore every insertion order
    // survive.
    //
    // The three new columns are all nullable-or-defaulted and join no
    // CHECK that existing data could violate, so this migration is
    // BEHAVIORALLY INERT: with every deleted_on NULL the partial unique
    // indexes are semantically identical to the constraints they replace.
    //
    // deleted_on  — the prompt's soft delete. Doubles as the resolver's
    //               WHITEOUT: an overlay node carrying it masks the base
    //               node at that dot-path. Reads deliberately do NOT
    //               filter it (that is the point: communicate the
    //               intended delete).
    // mask_kind   — 'PASSTHROUGH' marks an ancestor shell that exists in
    //               a sparse overlay only to carry identity and children.
    //               Without it, masking one property would drag in
    //               domain/entity shells whose empty description
    //               ('' NOT NULL DEFAULT) would OVERRIDE the base's real
    //               description. Silent data corruption; this column is
    //               the fix.
    // content_revision — per-subtree counter for sub-loadable dope, on
    //               dope_persistence only. dope_scope.revision REMAINS
    //               the single whole-tree counter and the sole CAS gate;
    //               this sits BESIDE it and never replaces it.
    static func m0012_dopePersistenceRenameAndSoftDelete(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0012_dopePersistenceRenameAndSoftDelete") { db in
            // Row counts BEFORE, so the copy is proven and not merely hoped
            // for. On an append-only db a migration fails loudly; it never
            // silently drops a row.
            let before = try [
                "dope_domain", "dope_domain_entity", "dope_domain_enum",
                "dope_domain_enum_option", "dope_domain_entity_property",
            ].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }

            try db.execute(
                sql: """
                    CREATE TABLE dope_persistence (
                        \(baseColumns),
                        dope_scope_uuid TEXT NOT NULL
                            REFERENCES dope_scope(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        content_revision INTEGER NOT NULL DEFAULT 0
                            CHECK (content_revision >= 0),
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH')
                    );

                    CREATE TABLE dope_persistence_entity (
                        \(baseColumns),
                        dope_persistence_uuid TEXT NOT NULL
                            REFERENCES dope_persistence(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        entity_type TEXT NOT NULL DEFAULT 'MODEL'
                            CHECK (entity_type IN ('MODEL', 'JUNCTION', 'BASE_COMPOSABLE')),
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        repo_representative_file TEXT,
                        base_composable_uuid TEXT
                            REFERENCES dope_persistence_entity(uuid) ON DELETE RESTRICT,
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH'),
                        CHECK (base_composable_uuid IS NULL OR base_composable_uuid != uuid)
                    );

                    CREATE TABLE dope_persistence_enum (
                        \(baseColumns),
                        dope_persistence_uuid TEXT NOT NULL
                            REFERENCES dope_persistence(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 256),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        repo_representative_file TEXT,
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH')
                    );

                    CREATE TABLE dope_persistence_enum_option (
                        \(baseColumns),
                        dope_persistence_enum_uuid TEXT NOT NULL
                            REFERENCES dope_persistence_enum(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 128),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH')
                    );

                    CREATE TABLE dope_persistence_entity_property (
                        \(baseColumns),
                        dope_persistence_entity_uuid TEXT NOT NULL
                            REFERENCES dope_persistence_entity(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 128),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        data_type TEXT NOT NULL
                            CHECK (data_type IN ('enum', 'relationship', 'boolean',
                                                 'uuid', 'int', 'long', 'decimal',
                                                 'text', 'datetime')),
                        nullable INTEGER NOT NULL DEFAULT 1 CHECK (nullable IN (0, 1)),
                        is_unique INTEGER NOT NULL DEFAULT 0 CHECK (is_unique IN (0, 1)),
                        auto_increment INTEGER CHECK (auto_increment IN (0, 1)),
                        text_char_limit INTEGER CHECK (text_char_limit > 0),
                        dope_persistence_enum_uuid TEXT
                            REFERENCES dope_persistence_enum(uuid) ON DELETE RESTRICT,
                        related_property_uuid TEXT
                            REFERENCES dope_persistence_entity_property(uuid) ON DELETE RESTRICT,
                        base_origin_property_uuid TEXT
                            REFERENCES dope_persistence_entity_property(uuid) ON DELETE RESTRICT,
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH'),
                        CHECK ((data_type = 'enum') = (dope_persistence_enum_uuid IS NOT NULL)),
                        CHECK ((data_type = 'relationship') = (related_property_uuid IS NOT NULL)),
                        CHECK (auto_increment IS NULL OR data_type = 'long'),
                        CHECK (text_char_limit IS NULL OR data_type = 'text')
                    );

                    -- Copy: parent-first, id explicit so rowids survive.
                    INSERT INTO dope_persistence
                        (id, uuid, version, created_at, updated_at,
                         dope_scope_uuid, code, name, description, sort_order)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_scope_uuid, code, name, description, sort_order
                      FROM dope_domain;

                    INSERT INTO dope_persistence_entity
                        (id, uuid, version, created_at, updated_at,
                         dope_persistence_uuid, code, name, entity_type, description,
                         sort_order, repo_representative_file, base_composable_uuid)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_domain_uuid, code, name, entity_type, description,
                           sort_order, repo_representative_file, base_composable_uuid
                      FROM dope_domain_entity;

                    INSERT INTO dope_persistence_enum
                        (id, uuid, version, created_at, updated_at,
                         dope_persistence_uuid, code, name, description, sort_order,
                         repo_representative_file)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_domain_uuid, code, name, description, sort_order,
                           repo_representative_file
                      FROM dope_domain_enum;

                    INSERT INTO dope_persistence_enum_option
                        (id, uuid, version, created_at, updated_at,
                         dope_persistence_enum_uuid, code, name, description, sort_order)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_domain_enum_uuid, code, name, description, sort_order
                      FROM dope_domain_enum_option;

                    INSERT INTO dope_persistence_entity_property
                        (id, uuid, version, created_at, updated_at,
                         dope_persistence_entity_uuid, code, name, description, sort_order,
                         data_type, nullable, is_unique, auto_increment, text_char_limit,
                         dope_persistence_enum_uuid, related_property_uuid,
                         base_origin_property_uuid)
                    SELECT id, uuid, version, created_at, updated_at,
                           dope_domain_entity_uuid, code, name, description, sort_order,
                           data_type, nullable, is_unique, auto_increment, text_char_limit,
                           dope_domain_enum_uuid, related_property_uuid,
                           base_origin_property_uuid
                      FROM dope_domain_entity_property;

                    -- Drop: child-first.
                    DROP TABLE dope_domain_entity_property;
                    DROP TABLE dope_domain_enum_option;
                    DROP TABLE dope_domain_enum;
                    DROP TABLE dope_domain_entity;
                    DROP TABLE dope_domain;

                    -- Uniqueness moves off the table constraint onto partial
                    -- indexes, so a tombstoned row no longer occupies its
                    -- (parent, code) slot and delete-then-re-add works.
                    CREATE UNIQUE INDEX idx_dope_persistence_scope_code
                        ON dope_persistence(dope_scope_uuid, code)
                        WHERE deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_persistence_entity_code
                        ON dope_persistence_entity(dope_persistence_uuid, code)
                        WHERE deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_persistence_enum_code
                        ON dope_persistence_enum(dope_persistence_uuid, code)
                        WHERE deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_persistence_enum_option_code
                        ON dope_persistence_enum_option(dope_persistence_enum_uuid, code)
                        WHERE deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_persistence_property_code
                        ON dope_persistence_entity_property(dope_persistence_entity_uuid, code)
                        WHERE deleted_on IS NULL;

                    CREATE INDEX idx_dope_persistence_scope_fk
                        ON dope_persistence(dope_scope_uuid);
                    CREATE INDEX idx_dope_persistence_entity_parent_fk
                        ON dope_persistence_entity(dope_persistence_uuid);
                    CREATE INDEX idx_dope_persistence_entity_base_composable_fk
                        ON dope_persistence_entity(base_composable_uuid);
                    CREATE INDEX idx_dope_persistence_enum_parent_fk
                        ON dope_persistence_enum(dope_persistence_uuid);
                    CREATE INDEX idx_dope_persistence_enum_option_parent_fk
                        ON dope_persistence_enum_option(dope_persistence_enum_uuid);
                    CREATE INDEX idx_dope_persistence_property_entity_fk
                        ON dope_persistence_entity_property(dope_persistence_entity_uuid);
                    CREATE INDEX idx_dope_persistence_property_enum_fk
                        ON dope_persistence_entity_property(dope_persistence_enum_uuid);
                    CREATE INDEX idx_dope_persistence_property_related_fk
                        ON dope_persistence_entity_property(related_property_uuid);
                    CREATE INDEX idx_dope_persistence_property_base_origin_fk
                        ON dope_persistence_entity_property(base_origin_property_uuid);
                    """)

            // Proven, not hoped for.
            let after = try [
                "dope_persistence", "dope_persistence_entity", "dope_persistence_enum",
                "dope_persistence_enum_option", "dope_persistence_entity_property",
            ].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "dope_persistence",
                    detail: "m0012 row-count mismatch: before \(before) after \(after)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [12, Store.isoNow()]
            )
        }
    }
}
