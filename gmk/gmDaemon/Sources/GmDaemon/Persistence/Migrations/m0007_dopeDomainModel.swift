import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0007 — DOPE persistence modeling. Pure ADD: six BaseEntity tables, no
    // FTS5 mirrors. dope_scope.revision is the whole-tree content counter and IS
    // scope.doped.json's `version`; the row's `version` column keeps its
    // optimistic-lock meaning. Scope uniqueness is TWO PARTIAL UNIQUE INDEXES
    // because SQLite treats NULLs as distinct, so a column-list UNIQUE would
    // constrain nothing for a NULL prompt_uuid. The two property ref FKs are ON
    // DELETE RESTRICT, so scope deletion and ingest's whole-tree wipe delete
    // properties FIRST or a cross-domain relationship RESTRICTs mid-statement.
    static func m0007_dopeDomainModel(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0007_dopeDomainModel") { db in
            try db.execute(
                sql: """
                    CREATE TABLE dope_scope (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                        scope_type TEXT NOT NULL
                            CHECK (scope_type IN ('SESSION_BASE', 'PROMPT')),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                        CHECK ((scope_type = 'PROMPT') = (prompt_uuid IS NOT NULL))
                    );

                    CREATE TABLE dope_domain (
                        \(baseColumns),
                        dope_scope_uuid TEXT NOT NULL
                            REFERENCES dope_scope(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        UNIQUE(dope_scope_uuid, code)
                    );

                    CREATE TABLE dope_domain_entity (
                        \(baseColumns),
                        dope_domain_uuid TEXT NOT NULL
                            REFERENCES dope_domain(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        entity_type TEXT NOT NULL DEFAULT 'MODEL'
                            CHECK (entity_type IN ('MODEL', 'JUNCTION')),
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        repo_representative_file TEXT,
                        UNIQUE(dope_domain_uuid, code)
                    );

                    CREATE TABLE dope_domain_enum (
                        \(baseColumns),
                        dope_domain_uuid TEXT NOT NULL
                            REFERENCES dope_domain(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 256),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        repo_representative_file TEXT,
                        UNIQUE(dope_domain_uuid, code)
                    );

                    CREATE TABLE dope_domain_enum_option (
                        \(baseColumns),
                        dope_domain_enum_uuid TEXT NOT NULL
                            REFERENCES dope_domain_enum(uuid) ON DELETE CASCADE,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 128),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        UNIQUE(dope_domain_enum_uuid, code)
                    );

                    CREATE TABLE dope_domain_entity_property (
                        \(baseColumns),
                        dope_domain_entity_uuid TEXT NOT NULL
                            REFERENCES dope_domain_entity(uuid) ON DELETE CASCADE,
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
                        dope_domain_enum_uuid TEXT
                            REFERENCES dope_domain_enum(uuid) ON DELETE RESTRICT,
                        related_property_uuid TEXT
                            REFERENCES dope_domain_entity_property(uuid) ON DELETE RESTRICT,
                        UNIQUE(dope_domain_entity_uuid, code),
                        CHECK ((data_type = 'enum') = (dope_domain_enum_uuid IS NOT NULL)),
                        CHECK ((data_type = 'relationship') = (related_property_uuid IS NOT NULL)),
                        CHECK (auto_increment IS NULL OR data_type = 'long'),
                        CHECK (text_char_limit IS NULL OR data_type = 'text')
                    );

                    CREATE UNIQUE INDEX idx_dope_scope_base_code
                        ON dope_scope(session_uuid, code)
                        WHERE scope_type = 'SESSION_BASE';
                    CREATE UNIQUE INDEX idx_dope_scope_prompt_code
                        ON dope_scope(session_uuid, prompt_uuid, code)
                        WHERE scope_type = 'PROMPT';

                    CREATE INDEX idx_dope_scope_session_uuid ON dope_scope(session_uuid);
                    CREATE INDEX idx_dope_scope_prompt_uuid ON dope_scope(prompt_uuid);
                    CREATE INDEX idx_dope_domain_scope_fk ON dope_domain(dope_scope_uuid);
                    CREATE INDEX idx_dope_domain_entity_domain_fk
                        ON dope_domain_entity(dope_domain_uuid);
                    CREATE INDEX idx_dope_domain_enum_domain_fk
                        ON dope_domain_enum(dope_domain_uuid);
                    CREATE INDEX idx_dope_domain_enum_option_enum_fk
                        ON dope_domain_enum_option(dope_domain_enum_uuid);
                    CREATE INDEX idx_dope_property_entity_fk
                        ON dope_domain_entity_property(dope_domain_entity_uuid);
                    CREATE INDEX idx_dope_property_enum_fk
                        ON dope_domain_entity_property(dope_domain_enum_uuid);
                    CREATE INDEX idx_dope_property_related_fk
                        ON dope_domain_entity_property(related_property_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [7, Store.isoNow()]
            )
        }
    }
}
