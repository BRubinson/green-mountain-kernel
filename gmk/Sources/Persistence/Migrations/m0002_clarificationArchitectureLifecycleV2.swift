import Foundation
import GRDB

extension Migrations {
    // m0002 — db-native clarification + architecture entities, prompt lifecycle
    // v2, daemon_config; the prompt table is rebuilt in place.
    // Registered with NO foreignKeyChecks: argument — GRDB's default .deferred
    // IS the official SQLite 12-step. NO PRAGMA may appear in this body:
    // pragmas are silently ignored inside a transaction, and with FK
    // enforcement live the prompt rebuild either aborts on file_change's NO
    // ACTION reference or CASCADE-deletes every prompt_artifact row and commits.
    static func m0002_clarificationArchitectureLifecycleV2(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0002_clarificationArchitectureLifecycleV2") { db in
            // Step 1 — the prompt rebuild, FIRST, while the table has only its
            // three m0001-era referrers. create-new → copy → drop-old →
            // rename-new, so the only ALTER renames a table with zero referrers;
            // renaming the OLD table out of the way instead rewrites child FK
            // clauses to REFERENCES "prompt_old" whenever foreign_keys is ON.
            // The copy carries `id` explicitly so every uuid keeps its rowid.
            try db.execute(
                sql: """
                    CREATE TABLE prompt_new (
                        \(baseColumns),
                        session_uuid TEXT NOT NULL REFERENCES session(uuid),
                        seq INTEGER NOT NULL,
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        backstory TEXT NOT NULL,
                        goal TEXT NOT NULL,
                        detail TEXT NOT NULL,
                        command TEXT NOT NULL DEFAULT '',
                        status TEXT NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft', 'clarifying', 'architecting',
                                              'implementing', 'reviewing', 'done')),
                        ckfs_relative_storage_path TEXT NOT NULL,
                        UNIQUE(session_uuid, code),
                        UNIQUE(session_uuid, seq)
                    );

                    INSERT INTO prompt_new (id, uuid, version, created_at, updated_at,
                                            session_uuid, seq, code, name, backstory,
                                            goal, detail, command, status,
                                            ckfs_relative_storage_path)
                    SELECT id, uuid, version, created_at, updated_at,
                           session_uuid, seq, code, name, backstory,
                           goal, detail, command,
                           CASE status WHEN 'clarified' THEN 'done' ELSE status END,
                           ckfs_relative_storage_path
                    FROM prompt;

                    DROP TABLE prompt;
                    ALTER TABLE prompt_new RENAME TO prompt;
                    CREATE INDEX idx_prompt_session_uuid ON prompt(session_uuid);
                    """
            )

            // Step 2 — the new entity tables, created AFTER the rebuild so
            // their CASCADE references point at the new prompt table and never
            // exist during the DROP above.
            try db.execute(
                sql: """
                    CREATE TABLE clarification_summary (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        status TEXT NOT NULL DEFAULT 'building'
                            CHECK (status IN ('building', 'answering', 'complete')),
                        backstory_note TEXT NOT NULL DEFAULT '',
                        refined_goal TEXT NOT NULL DEFAULT '',
                        refined_detail TEXT NOT NULL DEFAULT '',
                        UNIQUE(prompt_uuid)
                    );

                    CREATE TABLE clarification (
                        \(baseColumns),
                        clarification_summary_uuid TEXT NOT NULL
                            REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL,
                        category TEXT NOT NULL
                            CHECK (category IN ('goal', 'detail', 'yeet_type')),
                        question TEXT NOT NULL,
                        answer TEXT,
                        answer_source TEXT
                            CHECK (answer_source IN ('user', 'bot_inferred')),
                        status TEXT NOT NULL DEFAULT 'open'
                            CHECK (status IN ('open', 'answered', 'skipped')),
                        CHECK (status != 'answered' OR answer IS NOT NULL),
                        UNIQUE(clarification_summary_uuid, seq)
                    );

                    CREATE TABLE architecture_summary (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        body TEXT NOT NULL DEFAULT '',
                        status TEXT NOT NULL DEFAULT 'drafting'
                            CHECK (status IN ('drafting', 'proposed', 'approved')),
                        UNIQUE(prompt_uuid)
                    );

                    CREATE TABLE architecture_persistence_change (
                        \(baseColumns),
                        architecture_summary_uuid TEXT NOT NULL
                            REFERENCES architecture_summary(uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL,
                        class_name TEXT NOT NULL,
                        file_path TEXT NOT NULL,
                        reason_brief TEXT NOT NULL,
                        UNIQUE(architecture_summary_uuid, seq)
                    );

                    CREATE TABLE architecture_persistence_field_change (
                        \(baseColumns),
                        persistence_change_uuid TEXT NOT NULL
                            REFERENCES architecture_persistence_change(uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL,
                        field_name TEXT NOT NULL,
                        change_reason TEXT NOT NULL,
                        change_purpose TEXT NOT NULL,
                        data_type TEXT NOT NULL,
                        nullable INTEGER NOT NULL CHECK (nullable IN (0, 1)),
                        is_foreign_key INTEGER NOT NULL DEFAULT 0 CHECK (is_foreign_key IN (0, 1)),
                        fk_target TEXT,
                        is_indexed INTEGER NOT NULL DEFAULT 0 CHECK (is_indexed IN (0, 1)),
                        CHECK (is_foreign_key = 0 OR fk_target IS NOT NULL),
                        UNIQUE(persistence_change_uuid, seq)
                    );

                    CREATE TABLE architecture_general_change (
                        \(baseColumns),
                        architecture_summary_uuid TEXT NOT NULL
                            REFERENCES architecture_summary(uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL,
                        file_path TEXT NOT NULL,
                        class_name TEXT,
                        reason_brief TEXT NOT NULL,
                        change_depth TEXT NOT NULL
                            CHECK (change_depth IN ('pseudo', 'draft', 'actual')),
                        change_code TEXT NOT NULL,
                        UNIQUE(architecture_summary_uuid, seq)
                    );

                    CREATE TABLE daemon_config (
                        \(baseColumns),
                        config_key TEXT NOT NULL UNIQUE,
                        config_value TEXT NOT NULL
                    );

                    CREATE INDEX idx_clarification_summary_prompt_uuid
                        ON clarification_summary(prompt_uuid);
                    CREATE INDEX idx_clarification_summary_uuid_fk
                        ON clarification(clarification_summary_uuid);
                    CREATE INDEX idx_architecture_summary_prompt_uuid
                        ON architecture_summary(prompt_uuid);
                    CREATE INDEX idx_arch_persistence_change_summary_fk
                        ON architecture_persistence_change(architecture_summary_uuid);
                    CREATE INDEX idx_arch_persistence_field_change_fk
                        ON architecture_persistence_field_change(persistence_change_uuid);
                    CREATE INDEX idx_arch_general_change_summary_fk
                        ON architecture_general_change(architecture_summary_uuid);
                    """
            )

            // Step 3 — seed daemon_config with the layout defaults ($HOME
            // conventions, matching gm_session_startup.sh). CONFIG_SET is the write
            // door for a differing layout; the daemon never reads $GMCC_* env
            // vars (its environment is a posix_spawn snapshot of whichever
            // client invocation autostarted it).
            let home = NSHomeDirectory()
            let now = Store.isoNow()
            for (key, value) in [
                ("ckfs_root", "\(home)/gmcc_ckfs"),
                ("kbite_root", "\(home)/gmcc_ckfs/kbites"),
                ("kbite_open_root", "\(home)/gmcc_ckfs/kbites/open"),
                ("kbite_digested_root", "\(home)/gmcc_ckfs/kbites/digested"),
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO daemon_config
                            (uuid, version, created_at, updated_at, config_key, config_value)
                        VALUES (?, 0, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString.lowercased(), now, now, key, value]
                )
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [2, Store.isoNow()]
            )
        }
    }
}
