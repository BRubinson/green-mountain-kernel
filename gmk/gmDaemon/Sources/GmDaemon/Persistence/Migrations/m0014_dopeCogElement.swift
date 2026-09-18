import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0014 — COGS (Coordination Of General Systems). Pure ADD.
    //
    // Shape mirrors m0010's diagram_element: a generic element row plus a
    // per-type SUBTYPE table carrying that type's typed fields. A second
    // element type is then one new subtype table plus one registry entry
    // — never a migration against this table.
    //
    // DELIBERATE DIVERGENCE FROM m0010, and the whole point of the
    // registry: element_type carries NO CHECK constraint. m0010's
    // diagram_element.element_type has one, which is exactly why adding a
    // type there means rebuilding the table — the pain m0008 already paid
    // once for dope_domain_entity. Validity is enforced in Swift by
    // DopeCogElementSpec.spec(for:) throwing on an unknown value at READ,
    // the same pattern Store+Diagram.fetchElementInfo already uses, plus
    // the structural guarantee that exactly one subtype row exists.
    //
    // dope_scope_code is a ghost-tolerant CODE resolved at read time, not
    // a uuid FK: ingest re-mints every child uuid, and a uuid FK would
    // need an ON DELETE answer dope_scope cannot give (scope delete is not
    // offered). Same precedent as diagram_dope_scope — a dangling code is
    // a legal, renderable state, never an error.
    //
    // deleted_on/mask_kind ride here for the same reason they ride on the
    // persistence tables, and under the same rule: they are masking state,
    // meaningful only on the overlay tiers, and never serialized.
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
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [14, Store.isoNow()]
            )
        }
    }
}
