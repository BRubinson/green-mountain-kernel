import Foundation
import GRDB

extension Migrations {
    // m0014 — COGS. Pure ADD, shaped like m0010's diagram_element: a generic
    // element row plus a per-type subtype table, so a new element type is one
    // subtype table plus one registry entry rather than a migration.
    // element_type carries NO CHECK, unlike diagram_element — that CHECK is
    // exactly why adding a type there means rebuilding the table. Validity is
    // enforced at READ by DopeCogElementSpec.spec(for:). dope_scope_code is a
    // ghost-tolerant CODE, not a uuid FK: ingest re-mints every child uuid, and
    // a dangling code is a legal renderable state.
    /// Registers the m0014 migration: creates dope cog and element tables.
    ///
    /// Pure ADD migration. Creates dope_cog, dope_cog_element, and
    /// dope_cog_primary_system tables with indices. Element type validity is
    /// enforced at read-time via spec registry, not via CHECK constraint.
    ///
    /// - Parameter migrator: The database migrator to register the migration with.
    static func m0014_dopeCogElement(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0014_dopeCogElement") { db in
            try db.execute(
                sql: """
                    CREATE TABLE dope_cog (
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

                    CREATE TABLE dope_cog_element (
                        \(baseColumns),
                        dope_cog_uuid TEXT NOT NULL
                            REFERENCES dope_cog(uuid) ON DELETE CASCADE,
                        parent_element_uuid TEXT
                            REFERENCES dope_cog_element(uuid) ON DELETE CASCADE,
                        element_type TEXT NOT NULL,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        dope_scope_code TEXT,
                        deleted_on TEXT,
                        mask_kind TEXT CHECK (mask_kind IS NULL OR mask_kind = 'PASSTHROUGH'),
                        CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                    );

                    CREATE TABLE dope_cog_primary_system (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES dope_cog_element(uuid) ON DELETE CASCADE,
                        primary_path TEXT NOT NULL
                    );

                    CREATE UNIQUE INDEX idx_dope_cog_scope_code
                        ON dope_cog(dope_scope_uuid, code) WHERE deleted_on IS NULL;
                    CREATE UNIQUE INDEX idx_dope_cog_element_code
                        ON dope_cog_element(dope_cog_uuid, code) WHERE deleted_on IS NULL;

                    CREATE INDEX idx_dope_cog_scope_fk ON dope_cog(dope_scope_uuid);
                    CREATE INDEX idx_dope_cog_element_cog_fk
                        ON dope_cog_element(dope_cog_uuid);
                    CREATE INDEX idx_dope_cog_element_parent_fk
                        ON dope_cog_element(parent_element_uuid);
                    CREATE INDEX idx_dope_cog_primary_system_element_fk
                        ON dope_cog_primary_system(element_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [14, Store.isoNow()]
            )
        }
    }
}
