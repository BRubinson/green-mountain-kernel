import Foundation
import GRDB

/// Versioned schema migrations.
///
/// GRDB's DatabaseMigrator keeps its own private `grdb_migrations` replay
/// guard; the spec-visible ledger is the separate `schema_migrations` table
/// (the only table not wrapped in the BaseEntity columns), which each
/// migration appends its own row to.
public enum Migrations {
    /// Bump alongside new registerMigration calls.
    /// The re-baseline era ended at m0002: the db is append-only now. m0001's
    /// body is FROZEN — the migrator keys on the migration id and silently
    /// skips a changed body on an existing db, so any schema change lands as a
    /// new registerMigration and existing databases upgrade in place. Never
    /// instruct anyone to wipe ~/gmcc/gmcc.db* again.
    public static let currentSchemaVersion = 26

    /// The five BaseEntity columns wrapped into every domain table.
    /// `id` is the internal rowid; `uuid` is the external join key — all FKs
    /// reference uuid, never id.
    private static let baseColumns = """
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        version INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
        """

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("m0001_baseSchema") { db in
            try db.execute(sql: """
                CREATE TABLE schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at TEXT NOT NULL
                );

                CREATE TABLE project (
                    \(baseColumns),
                    git_repo_name TEXT NOT NULL,
                    code TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    ckfs_relative_storage_path TEXT NOT NULL
                );

                CREATE TABLE instance (
                    \(baseColumns),
                    project_uuid TEXT NOT NULL REFERENCES project(uuid),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    absolute_file_system_path TEXT NOT NULL,
                    ckfs_relative_storage_path TEXT NOT NULL,
                    UNIQUE(project_uuid, name)
                );

                CREATE TABLE session (
                    \(baseColumns),
                    instance_uuid TEXT NOT NULL REFERENCES instance(uuid),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    backstory TEXT NOT NULL,
                    goal TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'closed')),
                    ckfs_relative_storage_path TEXT NOT NULL,
                    UNIQUE(instance_uuid, code)
                );

                CREATE TABLE prompt (
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
                        CHECK (status IN ('draft', 'clarifying', 'clarified')),
                    ckfs_relative_storage_path TEXT NOT NULL,
                    UNIQUE(session_uuid, code),
                    UNIQUE(session_uuid, seq)
                );

                CREATE TABLE prompt_artifact (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    file_path TEXT NOT NULL,
                    kind TEXT NOT NULL
                        CHECK (kind IN ('explore', 'architecture', 'review', 'qualified', 'other')),
                    note TEXT,
                    UNIQUE(prompt_uuid, file_path)
                );

                CREATE TABLE kbite (
                    \(baseColumns),
                    code TEXT NOT NULL UNIQUE
                );

                CREATE TABLE prompt_active_kbite (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    UNIQUE(prompt_uuid, kbite_uuid)
                );

                CREATE TABLE session_active_kbite (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    UNIQUE(session_uuid, kbite_uuid)
                );

                CREATE TABLE instance_active_kbite (
                    \(baseColumns),
                    instance_uuid TEXT NOT NULL REFERENCES instance(uuid) ON DELETE CASCADE,
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    UNIQUE(instance_uuid, kbite_uuid)
                );

                CREATE TABLE project_active_kbite (
                    \(baseColumns),
                    project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    UNIQUE(project_uuid, kbite_uuid)
                );

                CREATE TABLE session_file (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid),
                    relative_path TEXT NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1,
                    UNIQUE(session_uuid, relative_path)
                );

                CREATE TABLE file_change (
                    \(baseColumns),
                    session_file_uuid TEXT NOT NULL REFERENCES session_file(uuid),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid),
                    prompt_uuid TEXT REFERENCES prompt(uuid),
                    change_kind TEXT NOT NULL DEFAULT 'edit'
                        CHECK (change_kind IN ('edit', 'create', 'delete', 'rename'))
                );

                CREATE TABLE file_change_range (
                    \(baseColumns),
                    file_change_uuid TEXT NOT NULL REFERENCES file_change(uuid) ON DELETE CASCADE,
                    line_start INTEGER NOT NULL,
                    line_end INTEGER NOT NULL,
                    changed_content TEXT
                );

                CREATE TABLE daemon_event (
                    \(baseColumns),
                    kind TEXT NOT NULL,
                    subject_uuid TEXT,
                    payload TEXT
                );

                CREATE INDEX idx_instance_project_uuid ON instance(project_uuid);
                CREATE INDEX idx_session_instance_uuid ON session(instance_uuid);
                CREATE INDEX idx_prompt_session_uuid ON prompt(session_uuid);
                CREATE INDEX idx_prompt_artifact_prompt_uuid ON prompt_artifact(prompt_uuid);
                CREATE INDEX idx_prompt_active_kbite_prompt_uuid ON prompt_active_kbite(prompt_uuid);
                CREATE INDEX idx_prompt_active_kbite_kbite_uuid ON prompt_active_kbite(kbite_uuid);
                CREATE INDEX idx_session_active_kbite_session_uuid ON session_active_kbite(session_uuid);
                CREATE INDEX idx_session_active_kbite_kbite_uuid ON session_active_kbite(kbite_uuid);
                CREATE INDEX idx_instance_active_kbite_instance_uuid ON instance_active_kbite(instance_uuid);
                CREATE INDEX idx_instance_active_kbite_kbite_uuid ON instance_active_kbite(kbite_uuid);
                CREATE INDEX idx_project_active_kbite_project_uuid ON project_active_kbite(project_uuid);
                CREATE INDEX idx_project_active_kbite_kbite_uuid ON project_active_kbite(kbite_uuid);
                CREATE INDEX idx_session_file_session_uuid ON session_file(session_uuid);
                CREATE INDEX idx_file_change_session_file_uuid ON file_change(session_file_uuid);
                CREATE INDEX idx_file_change_session_uuid ON file_change(session_uuid);
                CREATE INDEX idx_file_change_prompt_uuid ON file_change(prompt_uuid);
                CREATE INDEX idx_file_change_range_file_change_uuid ON file_change_range(file_change_uuid);
                CREATE INDEX idx_daemon_event_subject_uuid ON daemon_event(subject_uuid);
                CREATE INDEX idx_daemon_event_kind ON daemon_event(kind);
                CREATE INDEX idx_daemon_event_created_at ON daemon_event(created_at);
                """)

            // Kbite content family (v16 prompt 4), folded into the single
            // re-baselined m0001: the digested-content side — resources,
            // files, keyword vocabulary, and the FTS5 mirror backing
            // KBITE_SEARCH.
            try db.execute(sql: """
                CREATE TABLE keyword (
                    \(baseColumns),
                    keyword TEXT NOT NULL UNIQUE
                );

                CREATE TABLE kbite_keyword_junction (
                    \(baseColumns),
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    keyword_uuid TEXT NOT NULL REFERENCES keyword(uuid) ON DELETE CASCADE,
                    UNIQUE(kbite_uuid, keyword_uuid)
                );

                CREATE TABLE kbite_resource (
                    \(baseColumns),
                    kbite_uuid TEXT NOT NULL REFERENCES kbite(uuid) ON DELETE CASCADE,
                    resource_name TEXT NOT NULL,
                    resource_summary TEXT NOT NULL,
                    resource_type TEXT NOT NULL
                        CHECK (resource_type IN ('documentation', 'example_project', 'api_reference', 'blogs', 'all_others')),
                    resource_trust INTEGER NOT NULL DEFAULT 0
                        CHECK (resource_trust BETWEEN 0 AND 100)
                );

                CREATE TABLE kbite_resource_file (
                    \(baseColumns),
                    kbite_resource_uuid TEXT NOT NULL REFERENCES kbite_resource(uuid) ON DELETE CASCADE,
                    resource_file_name TEXT NOT NULL,
                    resource_file_summary TEXT NOT NULL DEFAULT '',
                    resource_file_content TEXT
                );

                CREATE TABLE resource_file_keyword_junction (
                    \(baseColumns),
                    file_uuid TEXT NOT NULL REFERENCES kbite_resource_file(uuid) ON DELETE CASCADE,
                    keyword_uuid TEXT NOT NULL REFERENCES keyword(uuid) ON DELETE CASCADE,
                    UNIQUE(file_uuid, keyword_uuid)
                );

                CREATE INDEX idx_kbite_keyword_junction_kbite_uuid ON kbite_keyword_junction(kbite_uuid);
                CREATE INDEX idx_kbite_keyword_junction_keyword_uuid ON kbite_keyword_junction(keyword_uuid);
                CREATE INDEX idx_kbite_resource_kbite_uuid ON kbite_resource(kbite_uuid);
                CREATE INDEX idx_kbite_resource_file_kbite_resource_uuid ON kbite_resource_file(kbite_resource_uuid);
                CREATE INDEX idx_resource_file_keyword_junction_file_uuid ON resource_file_keyword_junction(file_uuid);
                CREATE INDEX idx_resource_file_keyword_junction_keyword_uuid ON resource_file_keyword_junction(keyword_uuid);

                CREATE VIRTUAL TABLE kbite_resource_file_fts USING fts5(
                    resource_file_name,
                    resource_file_summary,
                    resource_file_content,
                    content='kbite_resource_file',
                    content_rowid='id'
                );

                CREATE TRIGGER kbite_resource_file_ai AFTER INSERT ON kbite_resource_file BEGIN
                    INSERT INTO kbite_resource_file_fts(rowid, resource_file_name, resource_file_summary, resource_file_content)
                    VALUES (new.id, new.resource_file_name, new.resource_file_summary, new.resource_file_content);
                END;

                CREATE TRIGGER kbite_resource_file_ad AFTER DELETE ON kbite_resource_file BEGIN
                    INSERT INTO kbite_resource_file_fts(kbite_resource_file_fts, rowid, resource_file_name, resource_file_summary, resource_file_content)
                    VALUES ('delete', old.id, old.resource_file_name, old.resource_file_summary, old.resource_file_content);
                END;

                CREATE TRIGGER kbite_resource_file_au AFTER UPDATE ON kbite_resource_file BEGIN
                    INSERT INTO kbite_resource_file_fts(kbite_resource_file_fts, rowid, resource_file_name, resource_file_summary, resource_file_content)
                    VALUES ('delete', old.id, old.resource_file_name, old.resource_file_summary, old.resource_file_content);
                    INSERT INTO kbite_resource_file_fts(rowid, resource_file_name, resource_file_summary, resource_file_content)
                    VALUES (new.id, new.resource_file_name, new.resource_file_summary, new.resource_file_content);
                END;
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [1, Store.isoNow()]
            )
        }

        // m0002 — db-native clarification + architecture entities, prompt
        // lifecycle v2 (six states), daemon_config. The first no-wipe
        // migration: existing data is preserved and the prompt table is
        // rebuilt in place.
        //
        // Registered with NO foreignKeyChecks: argument — GRDB's default
        // .deferred IS the official SQLite 12-step (PRAGMA foreign_keys=OFF
        // outside the transaction → body → whole-db foreign_key_check →
        // commit). NO PRAGMA may appear in this body: pragmas are silently
        // ignored inside a transaction, and with FK enforcement live the
        // prompt rebuild either aborts (via file_change's NO ACTION
        // reference) or silently CASCADE-deletes every prompt_artifact row
        // and commits — both verified empirically.
        migrator.registerMigration("m0002_clarificationArchitectureLifecycleV2") { db in
            // Step 1 — the prompt rebuild, FIRST, while the table has only its
            // three m0001-era referrers. Ordering is create-new → copy →
            // drop-old → rename-new: the only ALTER renames a table with zero
            // referrers, which is correct under every GRDB FK mode (renaming
            // the OLD table out of the way instead rewrites child FK clauses
            // to REFERENCES "prompt_old" whenever foreign_keys is ON). The
            // copy carries `id` explicitly so every uuid keeps its rowid and
            // sqlite_sequence stays monotonic. Old terminal `clarified` maps
            // to the new terminal `done`; draft/clarifying copy through.
            try db.execute(sql: """
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
                """)

            // Step 2 — the new entity tables, created AFTER the rebuild so
            // their CASCADE references point at the new prompt table and never
            // exist during the DROP above.
            try db.execute(sql: """
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
                """)

            // Step 3 — seed daemon_config with the layout defaults ($HOME
            // conventions, matching gmcc_session_startup.sh). CONFIG_SET is the write
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

        // m0003 — full-text search over prompt/clarification/architecture
        // text (the SEARCH message). Append-only: adds six external-content
        // FTS5 mirrors + sync triggers, touches no domain row. Six separate
        // tables is forced, not chosen — external-content FTS5 binds one
        // virtual table to exactly one source via content_rowid; the search
        // query UNIONs across them. The `_ad` triggers ride the globally
        // enabled recursive_triggers pragma (Store) so they fire on FK
        // cascade deletes too. Each table ends with a one-time
        // `INSERT INTO <fts>(<fts>) VALUES('rebuild')` — triggers only fire
        // on future writes, so without the rebuild all pre-existing history
        // would be unsearchable. No PRAGMA in this body (silently ignored
        // inside a transaction).
        migrator.registerMigration("m0003_searchIndexes") { db in
            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(source: "prompt",
                        columns: ["name", "goal", "detail", "backstory"]),
                FtsSpec(source: "clarification_summary",
                        columns: ["refined_goal", "refined_detail", "backstory_note"]),
                FtsSpec(source: "clarification",
                        columns: ["question", "answer"]),
                FtsSpec(source: "architecture_summary",
                        columns: ["body"]),
                FtsSpec(source: "architecture_general_change",
                        columns: ["file_path", "reason_brief", "change_code"]),
                FtsSpec(source: "architecture_persistence_change",
                        columns: ["class_name", "file_path", "reason_brief"]),
            ]
            for spec in specs {
                let fts = "\(spec.source)_fts"
                let cols = spec.columns.joined(separator: ", ")
                let newVals = spec.columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldVals = spec.columns.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE \(fts) USING fts5(
                        \(cols),
                        content='\(spec.source)',
                        content_rowid='id'
                    );

                    CREATE TRIGGER \(spec.source)_ai AFTER INSERT ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    CREATE TRIGGER \(spec.source)_ad AFTER DELETE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                    END;

                    CREATE TRIGGER \(spec.source)_au AFTER UPDATE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    INSERT INTO \(fts)(\(fts)) VALUES('rebuild');
                    """)
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [3, Store.isoNow()]
            )
        }

        // m0004 — db-native exploration + review reports (the last two
        // file-based bot reports move into the db). Pure ADD: five new
        // BaseEntity tables + five external-content FTS5 mirrors; no rebuild,
        // no data motion, no domain row touched. One summary per prompt
        // (UNIQUE), children FK the summary with CASCADE. finding_rating is
        // deliberately nullable: NULL marks work-in-progress (unranked);
        // the complete transition refuses while any NULL remains, and GETs
        // always return NULL-rated rows in the full partition. The FtsSpec
        // loop is a private copy of m0003's — frozen migrations stay
        // self-contained; never share helpers across migration bodies. The
        // `_ad` triggers ride the global recursive_triggers pragma so FK
        // cascade deletes stay FTS-synced. No PRAGMA in this body.
        migrator.registerMigration("m0004_explorationReviewReports") { db in
            try db.execute(sql: """
                CREATE TABLE exploration_summary (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    status TEXT NOT NULL DEFAULT 'exploring'
                        CHECK (status IN ('exploring', 'complete')),
                    overview TEXT NOT NULL DEFAULT '',
                    UNIQUE(prompt_uuid)
                );

                CREATE TABLE exploration_key_file (
                    \(baseColumns),
                    exploration_summary_uuid TEXT NOT NULL
                        REFERENCES exploration_summary(uuid) ON DELETE CASCADE,
                    file_path TEXT NOT NULL,
                    UNIQUE(exploration_summary_uuid, file_path)
                );

                CREATE TABLE exploration_finding (
                    \(baseColumns),
                    exploration_summary_uuid TEXT NOT NULL
                        REFERENCES exploration_summary(uuid) ON DELETE CASCADE,
                    kind TEXT NOT NULL
                        CHECK (kind IN ('persistence_model', 'implementation_pattern',
                                        'existing_functionality', 'scope_creep_risk',
                                        'general_relevant_change', 'other')),
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    agent_name TEXT NOT NULL,
                    finding_rating INTEGER
                        CHECK (finding_rating IS NULL OR finding_rating BETWEEN 0 AND 999)
                );

                CREATE TABLE review_summary (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    status TEXT NOT NULL DEFAULT 'reviewing'
                        CHECK (status IN ('reviewing', 'complete')),
                    verdict TEXT
                        CHECK (verdict IN ('approved', 'approved_with_nits',
                                           'changes_requested', 'legacy_unstated')),
                    overview TEXT NOT NULL DEFAULT '',
                    CHECK (status != 'complete' OR verdict IS NOT NULL),
                    UNIQUE(prompt_uuid)
                );

                CREATE TABLE review_finding (
                    \(baseColumns),
                    review_summary_uuid TEXT NOT NULL
                        REFERENCES review_summary(uuid) ON DELETE CASCADE,
                    kind TEXT NOT NULL
                        CHECK (kind IN ('correctness_bug', 'spec_deviation',
                                        'regression_risk', 'security',
                                        'simplification', 'other')),
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    file_path TEXT,
                    line_start INTEGER,
                    line_end INTEGER,
                    agent_name TEXT NOT NULL,
                    finding_rating INTEGER
                        CHECK (finding_rating IS NULL OR finding_rating BETWEEN 0 AND 999),
                    status TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'fixed', 'accepted', 'wont_fix')),
                    CHECK (line_end IS NULL OR line_start IS NOT NULL)
                );

                CREATE INDEX idx_exploration_summary_prompt_uuid
                    ON exploration_summary(prompt_uuid);
                CREATE INDEX idx_exploration_key_file_summary_fk
                    ON exploration_key_file(exploration_summary_uuid);
                CREATE INDEX idx_exploration_finding_summary_fk
                    ON exploration_finding(exploration_summary_uuid);
                CREATE INDEX idx_review_summary_prompt_uuid
                    ON review_summary(prompt_uuid);
                CREATE INDEX idx_review_finding_summary_fk
                    ON review_finding(review_summary_uuid);
                """)

            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(source: "exploration_summary",
                        columns: ["overview"]),
                FtsSpec(source: "exploration_key_file",
                        columns: ["file_path"]),
                FtsSpec(source: "exploration_finding",
                        columns: ["title", "body"]),
                FtsSpec(source: "review_summary",
                        columns: ["overview"]),
                FtsSpec(source: "review_finding",
                        columns: ["title", "body", "file_path"]),
            ]
            for spec in specs {
                let fts = "\(spec.source)_fts"
                let cols = spec.columns.joined(separator: ", ")
                let newVals = spec.columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldVals = spec.columns.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE \(fts) USING fts5(
                        \(cols),
                        content='\(spec.source)',
                        content_rowid='id'
                    );

                    CREATE TRIGGER \(spec.source)_ai AFTER INSERT ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    CREATE TRIGGER \(spec.source)_ad AFTER DELETE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                    END;

                    CREATE TRIGGER \(spec.source)_au AFTER UPDATE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    INSERT INTO \(fts)(\(fts)) VALUES('rebuild');
                    """)
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [4, Store.isoNow()]
            )
        }


        // m0005 — purge the legacy concepts. Three rebuilds plus a backfill.
        //
        // The plugin no longer has a legacy tier: YEETS is gone, the yaml era
        // is gone, and every bot report is db-native. What kept the legacy
        // FORK alive was data — 66 clarification rows categorised yeet_type,
        // 84 review verdicts of legacy_unstated, and 105 pre-m0002 prompts
        // carrying no clarification/architecture summary at all, whose only
        // record was an on-disk qualified.md/architecture.md reached through
        // SUMMARY_ABSENT + prompt_is_legacy. This migration removes that data
        // reason so the fork can leave the code. Uniformity was chosen over
        // fidelity by explicit decision: the placeholder summaries assert a
        // completeness the underlying history does not have, and point at the
        // file for anyone who wants the real content.
        //
        // SQLite cannot alter a CHECK, so clarification, review_summary and
        // prompt_artifact rebuild. Registered with NO foreignKeyChecks:
        // argument for the same reason m0002 is — GRDB's default .deferred IS
        // the official SQLite 12-step, and with FK enforcement live the
        // review_summary drop would CASCADE every review_finding away. NO
        // PRAGMA may appear in this body. Each rebuild copies `id` explicitly:
        // the external-content FTS5 mirrors join on content_rowid='id', and a
        // DROP TABLE takes the source table's triggers with it, so every
        // rebuilt table recreates its triggers and re-runs the fts rebuild.
        migrator.registerMigration("m0005_purgeLegacyConcepts") { db in
            // Step 1 — data motion FIRST, so the narrowed CHECKs hold when the
            // rebuilt tables are populated.
            try db.execute(sql: """
                UPDATE clarification SET category = 'detail'
                 WHERE category = 'yeet_type';

                UPDATE review_summary SET verdict = 'approved'
                 WHERE verdict = 'legacy_unstated';
                """)

            // Step 2 — clarification: drop yeet_type from the category CHECK.
            try db.execute(sql: """
                CREATE TABLE clarification_new (
                    \(baseColumns),
                    clarification_summary_uuid TEXT NOT NULL
                        REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL,
                    category TEXT NOT NULL
                        CHECK (category IN ('goal', 'detail')),
                    question TEXT NOT NULL,
                    answer TEXT,
                    answer_source TEXT
                        CHECK (answer_source IN ('user', 'bot_inferred')),
                    status TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'answered', 'skipped')),
                    CHECK (status != 'answered' OR answer IS NOT NULL),
                    UNIQUE(clarification_summary_uuid, seq)
                );

                INSERT INTO clarification_new
                    (id, uuid, version, created_at, updated_at,
                     clarification_summary_uuid, seq, category, question,
                     answer, answer_source, status)
                SELECT id, uuid, version, created_at, updated_at,
                       clarification_summary_uuid, seq, category, question,
                       answer, answer_source, status
                  FROM clarification;

                DROP TABLE clarification;
                ALTER TABLE clarification_new RENAME TO clarification;

                CREATE INDEX idx_clarification_summary_uuid_fk
                    ON clarification(clarification_summary_uuid);
                """)

            // Step 3 — review_summary: drop legacy_unstated from the verdict
            // CHECK. review_finding CASCADE-references this table by uuid;
            // ordering is create-new / copy / drop-old / rename-new so the
            // only ALTER renames a table with zero referrers.
            try db.execute(sql: """
                CREATE TABLE review_summary_new (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    status TEXT NOT NULL DEFAULT 'reviewing'
                        CHECK (status IN ('reviewing', 'complete')),
                    verdict TEXT
                        CHECK (verdict IN ('approved', 'approved_with_nits',
                                           'changes_requested')),
                    overview TEXT NOT NULL DEFAULT '',
                    CHECK (status != 'complete' OR verdict IS NOT NULL),
                    UNIQUE(prompt_uuid)
                );

                INSERT INTO review_summary_new
                    (id, uuid, version, created_at, updated_at,
                     prompt_uuid, status, verdict, overview)
                SELECT id, uuid, version, created_at, updated_at,
                       prompt_uuid, status, verdict, overview
                  FROM review_summary;

                DROP TABLE review_summary;
                ALTER TABLE review_summary_new RENAME TO review_summary;

                CREATE INDEX idx_review_summary_prompt_uuid
                    ON review_summary(prompt_uuid);
                """)

            // Step 4 — prompt_artifact: drop the kind column. Every legal
            // value described a pre-migration report file except 'other',
            // which is the only value a current bot may write; a column with
            // one legal value carries no information. Rows keep file_path and
            // note. No FTS mirror on this table.
            try db.execute(sql: """
                CREATE TABLE prompt_artifact_new (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    file_path TEXT NOT NULL,
                    note TEXT,
                    UNIQUE(prompt_uuid, file_path)
                );

                INSERT INTO prompt_artifact_new
                    (id, uuid, version, created_at, updated_at,
                     prompt_uuid, file_path, note)
                SELECT id, uuid, version, created_at, updated_at,
                       prompt_uuid, file_path, note
                  FROM prompt_artifact;

                DROP TABLE prompt_artifact;
                ALTER TABLE prompt_artifact_new RENAME TO prompt_artifact;

                CREATE INDEX idx_prompt_artifact_prompt_uuid
                    ON prompt_artifact(prompt_uuid);
                """)

            // Step 5 — recreate the FTS triggers the drops took with them, and
            // rebuild both indexes. A private copy of the m0003 loop: frozen
            // migrations stay self-contained, never share helpers.
            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(source: "clarification", columns: ["question", "answer"]),
                FtsSpec(source: "review_summary", columns: ["overview"]),
            ]
            for spec in specs {
                let fts = "\(spec.source)_fts"
                let cols = spec.columns.joined(separator: ", ")
                let newVals = spec.columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldVals = spec.columns.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE TRIGGER \(spec.source)_ai AFTER INSERT ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    CREATE TRIGGER \(spec.source)_ad AFTER DELETE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                    END;

                    CREATE TRIGGER \(spec.source)_au AFTER UPDATE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    INSERT INTO \(fts)(\(fts)) VALUES('rebuild');
                    """)
            }

            // Step 6 — the backfill. Every prompt gets a clarification and an
            // architecture summary so SUMMARY_ABSENT can never again mean
            // "this one is legacy, go read a file". Placeholders land at
            // terminal status (complete / approved) so no lifecycle gate sees
            // a half-open summary, and carry ZERO child rows — a placeholder
            // asserts nothing it cannot back up. The body is a pointer to the
            // on-disk file, which stays the real record.
            let now = Store.isoNow()

            let missingClarification = try Row.fetchAll(db, sql: """
                SELECT p.uuid AS prompt_uuid, p.ckfs_relative_storage_path AS storage_path
                  FROM prompt p
                 WHERE NOT EXISTS (
                     SELECT 1 FROM clarification_summary c WHERE c.prompt_uuid = p.uuid
                 )
                """)
            for row in missingClarification {
                let promptUuid: String = row["prompt_uuid"]
                let storagePath: String = row["storage_path"]
                let pointer = """
                    m0005 placeholder. This prompt predates db-native \
                    clarifications; the real record, if any, is the file at \
                    \(storagePath)/memory/qualified.md
                    """
                try db.execute(sql: """
                    INSERT INTO clarification_summary
                        (uuid, version, created_at, updated_at, prompt_uuid,
                         status, backstory_note, refined_goal, refined_detail)
                    VALUES (?, 0, ?, ?, ?, 'complete', ?, ?, ?)
                    """, arguments: [
                        UUID().uuidString.lowercased(), now, now, promptUuid,
                        "Backfilled by m0005; not authored by a bot run.",
                        pointer, pointer,
                    ])
            }

            let missingArchitecture = try Row.fetchAll(db, sql: """
                SELECT p.uuid AS prompt_uuid, p.ckfs_relative_storage_path AS storage_path
                  FROM prompt p
                 WHERE NOT EXISTS (
                     SELECT 1 FROM architecture_summary a WHERE a.prompt_uuid = p.uuid
                 )
                """)
            for row in missingArchitecture {
                let promptUuid: String = row["prompt_uuid"]
                let storagePath: String = row["storage_path"]
                let pointer = """
                    m0005 placeholder. This prompt predates db-native \
                    architectures; the real record, if any, is the file at \
                    \(storagePath)/memory/architecture.md
                    """
                try db.execute(sql: """
                    INSERT INTO architecture_summary
                        (uuid, version, created_at, updated_at, prompt_uuid,
                         body, status)
                    VALUES (?, 0, ?, ?, ?, ?, 'approved')
                    """, arguments: [
                        UUID().uuidString.lowercased(), now, now, promptUuid, pointer,
                    ])
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [5, Store.isoNow()]
            )
        }


        // m0006 — un-backfill the draft prompts m0005 overreached on.
        //
        // m0005 gave a placeholder clarification + architecture summary to
        // EVERY prompt missing one, so that SUMMARY_ABSENT could never again
        // mean "this prompt is legacy, go read a file". For a prompt that has
        // moved through the lifecycle that is right. For one still at `draft`
        // it is not: the placeholders land at terminal status (complete /
        // approved), and CLARIFY_ASK only accepts rows while the summary is
        // `building` — with no edge back to `building` from either later
        // state. A draft prompt would therefore be unable to author its own
        // clarification, which is precisely the work it exists to do.
        //
        // Deleting them restores the correct meaning for that population:
        // SUMMARY_ABSENT on a draft prompt means "not opened yet — open one",
        // which is the ordinary non-legacy case and needs no fork. Only rows
        // m0005 itself wrote are touched (matched on its backstory_note
        // marker), and only while the prompt is still `draft`, so nothing a
        // bot authored can be caught by this. The FTS mirrors stay synced
        // through the live `_ad` delete triggers.
        //
        // Landed as its own migration rather than a fix to m0005's body: the
        // migrator keys on the migration id and silently skips a changed body
        // on a db that already ran it, so an edit would leave already-migrated
        // databases diverged from fresh ones forever.
        migrator.registerMigration("m0006_dropDraftPlaceholderSummaries") { db in
            let marker = "Backfilled by m0005; not authored by a bot run."
            try db.execute(sql: """
                DELETE FROM clarification_summary
                 WHERE backstory_note = ?
                   AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                """, arguments: [marker])
            // The architecture placeholder carries no note column, so it is
            // identified by the body m0005 wrote plus the same draft filter.
            try db.execute(sql: """
                DELETE FROM architecture_summary
                 WHERE body LIKE 'm0005 placeholder.%'
                   AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                """)
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [6, Store.isoNow()]
            )
        }

        // m0007 — DOPED domain modeling (Domain Optimized Project Essence
        // Driver — see DopeVocabulary). Pure ADD: six new BaseEntity tables, no rebuild, no data
        // motion, no existing row touched. No FTS5 mirrors this pass — dope
        // has no search entry point yet; mirrors attach later as a pure-ADD
        // migration exactly as m0003 did for m0002's tables.
        //
        // dope_scope.revision is the single whole-tree content counter and IS
        // the `version` field of scope.doped.json; the row's `version` column
        // keeps its standard optimistic-lock meaning (see bumpScopeRevision's
        // touchSession-style split in Store+Dope.swift).
        //
        // Scope uniqueness is TWO PARTIAL UNIQUE INDEXES, not a column-list
        // UNIQUE: SQLite treats NULLs as distinct in unique indexes, so a
        // UNIQUE(session_uuid, scope_type, prompt_uuid, code) would silently
        // constrain nothing for SESSION_BASE rows (prompt_uuid IS NULL).
        //
        // The two property ref FKs are ON DELETE RESTRICT — deleting a
        // still-referenced enum or target property must be a loud refusal,
        // never a silent un-typing. Consequence: scope deletion and ingest's
        // whole-tree wipe delete properties FIRST (explicit ordered deletes
        // in one transaction), because a cross-domain relationship would
        // RESTRICT a naive scope->domain CASCADE. Latent hazard, accepted and
        // documented: deleting a session/prompt row would CASCADE into
        // dope_scope and hit the same RESTRICT wall — nothing deletes those
        // rows today (the db is append-only).
        migrator.registerMigration("m0007_dopeDomainModel") { db in
            try db.execute(sql: """
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
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [7, Store.isoNow()]
            )
        }

        // m0008 — BASE_COMPOSABLE entities + the base_composable_uuid self-FK.
        // SQLite cannot ALTER a CHECK, so dope_domain_entity is REBUILT in the
        // m0002 order: create-new → copy → drop-old → rename-new (the only
        // ALTER renames a table with zero referrers). Registered with the
        // default .deferred foreignKeyChecks and NO PRAGMA in this body:
        // dope_domain_entity_property CASCADE-references this table, so with
        // FK enforcement live the DROP would take every property row with it.
        //
        // The self-FK is written against the FINAL table name, never
        // dope_domain_entity_new: under foreign_keys=OFF a RENAME does not
        // rewrite REFERENCES clauses, so the final-name text is exactly what
        // resolves to this table afterwards.
        //
        // ON DELETE RESTRICT mirrors the two property ref FKs — deleting a
        // still-composed base is a loud refusal, never a silent
        // un-composition. Its cost is the ordered-delete discipline extended
        // to entities: wipeDopeTree and domain-delete NULL every
        // base_composable_uuid in scope BEFORE the domain CASCADE, or a base
        // pair inside one domain trips the RESTRICT mid-statement.
        //
        // No BASE domain is seeded: the 'base' domain is convention only,
        // documented in the gmcc_daemon skill; the daemon never creates one.
        migrator.registerMigration("m0008_dopeBaseComposableEntities") { db in
            try db.execute(sql: """
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
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [8, Store.isoNow()]
            )
        }

        // m0009 — materialized base properties: base_origin_property_uuid.
        // A property may be materialized on a composing entity while TAGGED
        // with the BASE_COMPOSABLE property it originates from (provenance
        // without giving up a real, FK-referenceable row — relationship refs
        // target domain.entity.uuid, so uuid must exist locally).
        //
        // Plain ADD COLUMN, not the m0002/m0008 rebuild: the column is
        // nullable with no DEFAULT and joins no CHECK — exactly the case
        // SQLite's ALTER TABLE ADD COLUMN accepts with a REFERENCES clause.
        // That also avoids a DROP of dope_domain_entity_property, the table
        // every relationship and origin ref points into.
        //
        // No CHECK coupling, unlike enum/relationship: base_origin is
        // orthogonal to data_type (any type may be materialized from a
        // base); the real constraints (origin on a BASE_COMPOSABLE the
        // entity composes, matching data_type) are cross-row and live in
        // validatePropertyShape + DopeValidator.
        //
        // ON DELETE RESTRICT mirrors the sibling ref FKs: deleting a base
        // property that composing entities still tag is a refusal naming
        // the referrer, never a silent de-tagging. The ordered-delete
        // discipline is STRONGER here than for relationships — base_origin
        // is data_type-independent, so the relationship-first DELETE split
        // does not separate referrers from targets; the NULL-out steps in
        // wipeDopeTree and dopeNodeDelete precede BOTH property DELETEs.
        migrator.registerMigration("m0009_dopePropertyBaseOrigin") { db in
            try db.execute(sql: """
                ALTER TABLE dope_domain_entity_property
                    ADD COLUMN base_origin_property_uuid TEXT
                        REFERENCES dope_domain_entity_property(uuid) ON DELETE RESTRICT;

                CREATE INDEX idx_dope_property_base_origin_fk
                    ON dope_domain_entity_property(base_origin_property_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [9, Store.isoNow()]
            )
        }

        // m0010 — DIAGRAM domain modeling (db-persisted canvases over dope).
        // Pure ADD, m0007's grammar throughout: baseColumns identity, an index
        // per FK, CHECK-coupled discriminators, and PARTIAL unique indexes
        // wherever a nullable FK joins a uniqueness rule (the m0007
        // NULLs-are-distinct lesson, stamped four times for the tier ladder).
        //
        // diagram.revision is the whole-tree content counter (the
        // bumpScopeRevision split applies verbatim: element edits bump it
        // WITHOUT touching the diagram row's optimistic-lock version).
        //
        // Ownership is a chain-non-null tier ladder: each tier fills its own
        // FK and every ancestor's, so list/get by any ancestor is a plain
        // indexed WHERE and promotion is an UPDATE that moves tier and NULLs
        // the FKs below it. project_uuid is ALWAYS NOT NULL.
        //
        // dope bindings are TEXT codes, deliberately NOT SQL FKs into the
        // dope tables: DOPE_INGEST wipes and re-mints every child uuid, so
        // a uuid FK would dangle after one round-trip edit. Dangling codes
        // are a LEGAL renderable state (ghost cards) — diagram tables never
        // join requireNoExternalReferrers, so a picture can never block
        // domain evolution.
        //
        // The family has ZERO RESTRICT FKs: element subtree deletes are plain
        // CASCADEs (element → subtype row → vertex rows), and dope's whole
        // ordered-delete discipline does not transfer.
        //
        // Vertex rows are full BaseEntity rows (explicit user decision) whose
        // FKs target the SUBTYPE table's UNIQUE element_uuid — the schema
        // itself proves a vertex can only hang off a stroke/shape. They are
        // written as whole-set replacements inside batch transactions;
        // coordinates are element-local, so dragging a stroke is one
        // diagram_element UPDATE, never a vertex rewrite.
        migrator.registerMigration("m0010_diagramDomainModel") { db in
            try db.execute(sql: """
                CREATE TABLE diagram (
                    \(baseColumns),
                    project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                    instance_uuid TEXT REFERENCES instance(uuid) ON DELETE CASCADE,
                    session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                    tier TEXT NOT NULL
                        CHECK (tier IN ('PROJECT', 'INSTANCE', 'SESSION', 'PROMPT')),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    gmcc_diagram_path TEXT,
                    revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                    CHECK ((instance_uuid IS NOT NULL) = (tier IN ('INSTANCE', 'SESSION', 'PROMPT'))),
                    CHECK ((session_uuid IS NOT NULL) = (tier IN ('SESSION', 'PROMPT'))),
                    CHECK ((prompt_uuid IS NOT NULL) = (tier = 'PROMPT')),
                    CHECK (gmcc_diagram_path IS NULL OR tier != 'PROJECT')
                );

                CREATE TABLE diagram_element (
                    \(baseColumns),
                    diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                    parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    element_type TEXT NOT NULL
                        CHECK (element_type IN ('drawing_layer', 'drawing_stroke',
                                                'drawing_shape', 'dope_scope', 'dope_entity')),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    center_x REAL NOT NULL DEFAULT 0,
                    center_y REAL NOT NULL DEFAULT 0,
                    element_z REAL NOT NULL DEFAULT 0,
                    scale REAL NOT NULL DEFAULT 1 CHECK (scale > 0),
                    UNIQUE(diagram_uuid, code),
                    CHECK ((element_type IN ('dope_scope', 'drawing_layer'))
                            = (parent_element_uuid IS NULL)),
                    CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                );

                CREATE TABLE diagram_drawing_layer (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    opacity REAL NOT NULL DEFAULT 1
                        CHECK (opacity >= 0 AND opacity <= 1),
                    visible INTEGER NOT NULL DEFAULT 1 CHECK (visible IN (0, 1)),
                    locked INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0, 1))
                );

                CREATE TABLE diagram_drawing_stroke (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    tool TEXT NOT NULL DEFAULT 'pencil'
                        CHECK (tool IN ('pencil', 'marker', 'highlighter')),
                    stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                    stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0)
                );

                CREATE TABLE diagram_drawing_shape (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    shape_kind TEXT NOT NULL
                        CHECK (shape_kind IN ('rectangle', 'ellipse', 'line',
                                              'arrow', 'polygon')),
                    stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                    stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0),
                    fill_color TEXT,
                    corner_radius REAL CHECK (corner_radius IS NULL OR corner_radius >= 0),
                    CHECK (corner_radius IS NULL OR shape_kind = 'rectangle')
                );

                CREATE TABLE diagram_dope_scope (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    dope_scope_code TEXT NOT NULL
                );

                CREATE TABLE diagram_dope_entity (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    entity_code TEXT NOT NULL
                );

                CREATE TABLE diagram_stroke_vertex (
                    \(baseColumns),
                    stroke_element_uuid TEXT NOT NULL
                        REFERENCES diagram_drawing_stroke(element_uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL CHECK (seq >= 0),
                    x REAL NOT NULL,
                    y REAL NOT NULL,
                    pressure REAL CHECK (pressure IS NULL OR (pressure >= 0 AND pressure <= 1)),
                    UNIQUE(stroke_element_uuid, seq)
                );

                CREATE TABLE diagram_shape_vertex (
                    \(baseColumns),
                    shape_element_uuid TEXT NOT NULL
                        REFERENCES diagram_drawing_shape(element_uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL CHECK (seq >= 0),
                    x REAL NOT NULL,
                    y REAL NOT NULL,
                    UNIQUE(shape_element_uuid, seq)
                );

                CREATE UNIQUE INDEX idx_diagram_project_code
                    ON diagram(project_uuid, code) WHERE tier = 'PROJECT';
                CREATE UNIQUE INDEX idx_diagram_instance_code
                    ON diagram(instance_uuid, code) WHERE tier = 'INSTANCE';
                CREATE UNIQUE INDEX idx_diagram_session_code
                    ON diagram(session_uuid, code) WHERE tier = 'SESSION';
                CREATE UNIQUE INDEX idx_diagram_prompt_code
                    ON diagram(prompt_uuid, code) WHERE tier = 'PROMPT';

                CREATE INDEX idx_diagram_project_fk ON diagram(project_uuid);
                CREATE INDEX idx_diagram_instance_fk ON diagram(instance_uuid);
                CREATE INDEX idx_diagram_session_fk ON diagram(session_uuid);
                CREATE INDEX idx_diagram_prompt_fk ON diagram(prompt_uuid);
                CREATE INDEX idx_diagram_element_diagram_fk
                    ON diagram_element(diagram_uuid);
                CREATE INDEX idx_diagram_element_parent_fk
                    ON diagram_element(parent_element_uuid);
                CREATE INDEX idx_diagram_drawing_layer_element_fk
                    ON diagram_drawing_layer(element_uuid);
                CREATE INDEX idx_diagram_drawing_stroke_element_fk
                    ON diagram_drawing_stroke(element_uuid);
                CREATE INDEX idx_diagram_drawing_shape_element_fk
                    ON diagram_drawing_shape(element_uuid);
                CREATE INDEX idx_diagram_dope_scope_element_fk
                    ON diagram_dope_scope(element_uuid);
                CREATE INDEX idx_diagram_dope_entity_element_fk
                    ON diagram_dope_entity(element_uuid);
                CREATE INDEX idx_diagram_stroke_vertex_stroke_fk
                    ON diagram_stroke_vertex(stroke_element_uuid);
                CREATE INDEX idx_diagram_shape_vertex_shape_fk
                    ON diagram_shape_vertex(shape_element_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [10, Store.isoNow()]
            )
        }

        // m0011 — project.primary_project_branch (the prompt's
        // BASE_DOPED_BRANCH). The user-configured branch whose
        // SESSION_INSTANCE dope scope is allowed to promote into the
        // project's BASE_PROJECT scope.
        //
        // Plain ADD COLUMN, m0009's precedent: NOT NULL with a CONSTANT
        // DEFAULT and no CHECK and no REFERENCES — the shape SQLite's
        // ALTER TABLE ADD COLUMN accepts without a table rebuild. Every
        // existing project backfills to 'main', which is the documented
        // default behavior ("this starts as main by default").
        //
        // Sequenced FIRST among this prompt's migrations deliberately: it is
        // the only trivially-reversible one, so it lands as a green commit
        // between the SessionStart script rename and the two table rebuilds
        // that follow, and DopePromotion's branch-match predicate has its
        // column long before the promotion machinery exists to read it.
        migrator.registerMigration("m0011_projectPrimaryBranch") { db in
            try db.execute(sql: """
                ALTER TABLE project
                    ADD COLUMN primary_project_branch TEXT NOT NULL DEFAULT 'main';
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [11, Store.isoNow()]
            )
        }

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

            try db.execute(sql: """
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

        // m0013 — dope_scope widened from two tiers to four:
        // BASE_PROJECT / PROJECT_ITEM / SESSION_INSTANCE / SESSION_INSTANCE_ITEM.
        //
        // SQLite cannot ALTER a CHECK or a column's NOT NULL-ness, so this is
        // a full rebuild in the m0002/m0008 grammar. Registered .deferred
        // with NO PRAGMA in the body: the five dope_persistence* tables
        // CASCADE-reference this one.
        //
        // Ownership is m0010's chain-non-null tier ladder, ported verbatim:
        // each tier fills its own FK and every ancestor's, one CHECK per
        // tier, one PARTIAL unique index per tier (four, replacing the two
        // session_uuid-keyed indexes, which do not generalize past two
        // tiers). project_uuid is ALWAYS NOT NULL.
        //
        // The two existing scope types are pure VALUE renames:
        //   SESSION_BASE -> SESSION_INSTANCE
        //   PROMPT       -> SESSION_INSTANCE_ITEM
        // which is what makes this drop-in rather than a rewrite —
        // dopeScopeCandidates, dopeGet, dopeList, DopeBootSync and the
        // diagram binding ladder all keep working on a renamed constant.
        //
        // The prompt_uuid CHECK stays a BICONDITIONAL, exactly as m0007's
        // was. A nullable slot there would re-stamp m0007's NULLs-are-
        // distinct trap: UNIQUE(session_uuid, prompt_uuid, code) silently
        // constrains NOTHING for a prompt-free row. A session-level personal
        // overlay, if ever wanted, is a FIFTH tier — never a nullable slot.
        //
        // promoted_from_* is the BASE_PROJECT promotion high-water mark
        // (CHECK-restricted to that tier). It is deliberately separate from
        // the row's own `revision`: keying promotion on "did THIS scope
        // promote before" lets two instances on one branch overwrite each
        // other at every alternating boot, and without a recorded high-water
        // the same session re-promotes identical content at every
        // SessionStart. Keeping them separate also lets BASE_PROJECT.revision
        // stay its own forward-only counter that a lower-revision winner can
        // never drag backward.
        //
        // The copy uses LEFT JOINs plus a pre-flight refusal, NOT inner
        // joins: an inner join would silently DROP any scope whose
        // session/instance lineage is broken — project_uuid NOT NULL would
        // never fire, because the row simply would not be selected. On an
        // append-only db a migration fails loudly; it never deletes a row.
        migrator.registerMigration("m0013_dopeScopeTierLadder") { db in
            let orphans = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_scope ds
                LEFT JOIN session  s ON s.uuid = ds.session_uuid
                LEFT JOIN instance i ON i.uuid = s.instance_uuid
                WHERE i.project_uuid IS NULL
                """) ?? -1
            guard orphans == 0 else {
                throw StoreError.corruptState(
                    entity: "dope_scope",
                    detail: "m0013: \(orphans) scope(s) have no resolvable project "
                          + "through session->instance; refusing to drop them")
            }
            let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1

            try db.execute(sql: """
                CREATE TABLE dope_scope_new (
                    \(baseColumns),
                    project_uuid  TEXT NOT NULL REFERENCES project(uuid)  ON DELETE CASCADE,
                    instance_uuid TEXT          REFERENCES instance(uuid) ON DELETE CASCADE,
                    session_uuid  TEXT          REFERENCES session(uuid)  ON DELETE CASCADE,
                    prompt_uuid   TEXT          REFERENCES prompt(uuid)   ON DELETE CASCADE,
                    scope_type TEXT NOT NULL
                        CHECK (scope_type IN ('BASE_PROJECT', 'PROJECT_ITEM',
                                              'SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM')),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                    deleted_on TEXT,
                    promoted_from_scope_uuid TEXT,
                    promoted_from_revision INTEGER,
                    promoted_from_updated_at TEXT,
                    CHECK ((instance_uuid IS NOT NULL)
                           = (scope_type IN ('SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM'))),
                    CHECK ((session_uuid IS NOT NULL)
                           = (scope_type IN ('SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM'))),
                    CHECK ((prompt_uuid IS NOT NULL) = (scope_type = 'SESSION_INSTANCE_ITEM')),
                    CHECK (promoted_from_scope_uuid IS NULL OR scope_type = 'BASE_PROJECT'),
                    CHECK (promoted_from_revision IS NULL OR scope_type = 'BASE_PROJECT'),
                    CHECK (promoted_from_updated_at IS NULL OR scope_type = 'BASE_PROJECT')
                );

                INSERT INTO dope_scope_new
                    (id, uuid, version, created_at, updated_at,
                     project_uuid, instance_uuid, session_uuid, prompt_uuid,
                     scope_type, code, name, description, revision)
                SELECT ds.id, ds.uuid, ds.version, ds.created_at, ds.updated_at,
                       i.project_uuid, s.instance_uuid, ds.session_uuid, ds.prompt_uuid,
                       CASE ds.scope_type
                            WHEN 'SESSION_BASE' THEN 'SESSION_INSTANCE'
                            ELSE 'SESSION_INSTANCE_ITEM'
                       END,
                       ds.code, ds.name, ds.description, ds.revision
                  FROM dope_scope ds
                  LEFT JOIN session  s ON s.uuid = ds.session_uuid
                  LEFT JOIN instance i ON i.uuid = s.instance_uuid;

                DROP TABLE dope_scope;
                ALTER TABLE dope_scope_new RENAME TO dope_scope;

                CREATE UNIQUE INDEX idx_dope_scope_base_project_code
                    ON dope_scope(project_uuid, code)
                    WHERE scope_type = 'BASE_PROJECT' AND deleted_on IS NULL;
                CREATE UNIQUE INDEX idx_dope_scope_project_item_code
                    ON dope_scope(project_uuid, code)
                    WHERE scope_type = 'PROJECT_ITEM' AND deleted_on IS NULL;
                CREATE UNIQUE INDEX idx_dope_scope_session_instance_code
                    ON dope_scope(session_uuid, code)
                    WHERE scope_type = 'SESSION_INSTANCE' AND deleted_on IS NULL;
                CREATE UNIQUE INDEX idx_dope_scope_session_instance_item_code
                    ON dope_scope(session_uuid, prompt_uuid, code)
                    WHERE scope_type = 'SESSION_INSTANCE_ITEM' AND deleted_on IS NULL;

                CREATE INDEX idx_dope_scope_project_fk  ON dope_scope(project_uuid);
                CREATE INDEX idx_dope_scope_instance_fk ON dope_scope(instance_uuid);
                CREATE INDEX idx_dope_scope_session_fk  ON dope_scope(session_uuid);
                CREATE INDEX idx_dope_scope_prompt_fk   ON dope_scope(prompt_uuid);
                """)

            let after = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "dope_scope",
                    detail: "m0013 row-count mismatch: before \(before) after \(after)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [13, Store.isoNow()]
            )
        }

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
        migrator.registerMigration("m0014_dopeCogElement") { db in
            try db.execute(sql: """
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

        // m0015 — FTS5 mirrors over the dope tables. Pure ADD, and exactly
        // the migration m0007's own comment anticipated: "mirrors attach later
        // as a pure-ADD migration exactly as m0003 did for m0002's tables."
        //
        // The FtsSpec loop is a PRIVATE COPY of m0003's, per the frozen-
        // migration rule — a registered migration never reaches out to shared
        // code that might change under it.
        //
        // Sequenced strictly AFTER both rebuilds: a DROP TABLE takes its
        // triggers with it (m0005 step 5), so mirrors attached before m0012/
        // m0013 would have been silently destroyed.
        migrator.registerMigration("m0015_dopeSearchIndexes") { db in
            struct FtsSpec {
                let source: String
                let columns: [String]
            }
            let specs = [
                FtsSpec(source: "dope_scope", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence_entity",
                        columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence_entity_property",
                        columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence_enum", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_persistence_enum_option",
                        columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_cog", columns: ["code", "name", "description"]),
                FtsSpec(source: "dope_cog_element", columns: ["code", "name", "description"]),
            ]
            for spec in specs {
                let fts = "\(spec.source)_fts"
                let cols = spec.columns.joined(separator: ", ")
                let newVals = spec.columns.map { "new.\($0)" }.joined(separator: ", ")
                let oldVals = spec.columns.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE \(fts) USING fts5(
                        \(cols),
                        content='\(spec.source)',
                        content_rowid='id'
                    );

                    CREATE TRIGGER \(spec.source)_ai AFTER INSERT ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    CREATE TRIGGER \(spec.source)_ad AFTER DELETE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                    END;

                    CREATE TRIGGER \(spec.source)_au AFTER UPDATE ON \(spec.source) BEGIN
                        INSERT INTO \(fts)(\(fts), rowid, \(cols))
                        VALUES ('delete', old.id, \(oldVals));
                        INSERT INTO \(fts)(rowid, \(cols))
                        VALUES (new.id, \(newVals));
                    END;

                    INSERT INTO \(fts)(\(fts)) VALUES('rebuild');
                    """)
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [15, Store.isoNow()]
            )
        }

        // m0016 — the diagram-level dope binding: which scope does this WHOLE
        // diagram read and write through. Pure ADD COLUMN.
        //
        // Distinct from, and coexisting with, the existing PER-ELEMENT
        // diagram_dope_scope / diagram_dope_entity code bindings resolved
        // through dopeScopeCandidates. Those answer "which node does this one
        // shape point at"; this answers "which scope is this canvas over".
        //
        // The prompt asked for the ITEM-tier restriction as a CHECK. It cannot
        // be one: a SQLite CHECK cannot reference another table, and ALTER
        // TABLE ADD COLUMN cannot add a CHECK at all. The restriction is a
        // Swift guard on write plus ghost-tolerant resolution on read —
        // consistent with the per-element binding, which is also a code and
        // never a SQL FK.
        migrator.registerMigration("m0016_diagramDopeScopeBinding") { db in
            try db.execute(sql: """
                ALTER TABLE diagram ADD COLUMN dope_scope_code TEXT;

                CREATE INDEX idx_diagram_dope_scope_code ON diagram(dope_scope_code);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [16, Store.isoNow()]
            )
        }

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
        migrator.registerMigration("m0017_relationshipTargetAndDropMaskKind") { db in
            try db.execute(sql: """
                ALTER TABLE dope_persistence_entity_property
                    RENAME COLUMN related_property_uuid TO relationship_target_uuid;
                """)

            for table in ["dope_persistence", "dope_persistence_entity",
                          "dope_persistence_entity_property", "dope_persistence_enum",
                          "dope_persistence_enum_option", "dope_cog", "dope_cog_element"] {
                try db.execute(sql: "ALTER TABLE \(table) DROP COLUMN mask_kind;")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [17, Store.isoNow()]
            )
        }

        // m0018 — diagram_element.element_type: 'dope_scope' becomes
        // 'dope_scope_persistence_layer', and the subtype table renames with
        // it. The value appears in TWO CHECKs (the type list, and the
        // parent-null rule) and SQLite cannot ALTER a CHECK, so this is a
        // create-copy-drop-rename rebuild on the m0013 precedent.
        //
        // Cheap in practice and expensive to defer: the live blast radius is
        // a single row, while leaving an alias behind would mean two names
        // for one concept in a schema whose whole point is being the
        // vocabulary of record.
        migrator.registerMigration("m0018_diagramDopeScopePersistenceLayer") { db in
            let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let bindingsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_dope_scope") ?? -1

            try db.execute(sql: """
                CREATE TABLE diagram_element_new (
                    \(baseColumns),
                    diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                    parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    element_type TEXT NOT NULL
                        CHECK (element_type IN ('drawing_layer', 'drawing_stroke',
                                                'drawing_shape', 'dope_scope_persistence_layer',
                                                'dope_entity')),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    center_x REAL NOT NULL DEFAULT 0,
                    center_y REAL NOT NULL DEFAULT 0,
                    element_z REAL NOT NULL DEFAULT 0,
                    scale REAL NOT NULL DEFAULT 1 CHECK (scale > 0),
                    UNIQUE(diagram_uuid, code),
                    CHECK ((element_type IN ('dope_scope_persistence_layer', 'drawing_layer'))
                            = (parent_element_uuid IS NULL)),
                    CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                );

                INSERT INTO diagram_element_new
                    (id, uuid, version, created_at, updated_at, diagram_uuid,
                     parent_element_uuid, element_type, code, name, description,
                     sort_order, center_x, center_y, element_z, scale)
                SELECT id, uuid, version, created_at, updated_at, diagram_uuid,
                       parent_element_uuid,
                       CASE element_type
                            WHEN 'dope_scope' THEN 'dope_scope_persistence_layer'
                            ELSE element_type END,
                       code, name, description, sort_order,
                       center_x, center_y, element_z, scale
                  FROM diagram_element;

                DROP TABLE diagram_element;
                ALTER TABLE diagram_element_new RENAME TO diagram_element;

                ALTER TABLE diagram_dope_scope
                    RENAME TO diagram_dope_scope_persistence_layer;

                CREATE INDEX idx_diagram_element_diagram_fk
                    ON diagram_element(diagram_uuid);
                CREATE INDEX idx_diagram_element_parent_fk
                    ON diagram_element(parent_element_uuid);
                """)

            let after = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let bindingsAfter = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM diagram_dope_scope_persistence_layer") ?? -1
            guard before == after, bindingsBefore == bindingsAfter else {
                throw StoreError.corruptState(
                    entity: "diagram_element",
                    detail: "m0018 row-count mismatch: elements \(before)->\(after), "
                          + "bindings \(bindingsBefore)->\(bindingsAfter)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [18, Store.isoNow()]
            )
        }

        // m0019 — COGS vocabulary: primary_system becomes HULL, and
        // PersistenceOwner joins it as a second element type.
        //
        // dope_cog_element.element_type deliberately carries NO db CHECK
        // (the Swift registry governs it), which is exactly why this is a
        // table RENAME plus a plain CREATE rather than the rebuild m0018
        // needed. The cog tables are empty db-wide, so there is nothing to
        // backfill — the UPDATE below is written anyway so the migration is
        // correct on any database, not just this one.
        migrator.registerMigration("m0019_cogHullsAndPersistenceOwner") { db in
            try db.execute(sql: """
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

        // m0020 — the merge base for per-element reconciliation.
        //
        // In-session the db is the working truth and dumps to the repo; the
        // files become the input only at a boundary (new session, new
        // branch, git merge). At that boundary the rule is per-element:
        // files win for anything this session never touched, and an element
        // edited here that ALSO moved on disk is a real conflict.
        //
        // A three-way merge needs a base, and nothing stored one. This is
        // it.
        //
        // KEYED BY DOT-PATH, NEVER BY UUID — the single most important
        // property of this table. dopeIngest is a whole-tree wipe+reinsert
        // that re-mints every child uuid, so a uuid-keyed provenance row
        // would be destroyed by the very operation it exists to inform.
        // Dot-path codes are already how dope refs address nodes.
        migrator.registerMigration("m0020_dopeElementProvenance") { db in
            try db.execute(sql: """
                CREATE TABLE dope_element_provenance (
                    \(baseColumns),
                    dope_scope_uuid TEXT NOT NULL
                        REFERENCES dope_scope(uuid) ON DELETE CASCADE,
                    dot_path TEXT NOT NULL,
                    element_kind TEXT NOT NULL,
                    -- Content hash at the last files -> db sync. NULL means
                    -- "this element has never been synced from a file", which
                    -- is different from "synced and unchanged".
                    synced_content_hash TEXT,
                    -- Set by every granular dope mutation, cleared on sync.
                    locally_modified INTEGER NOT NULL DEFAULT 0
                        CHECK (locally_modified IN (0, 1)),
                    UNIQUE(dope_scope_uuid, dot_path)
                );

                CREATE INDEX idx_dope_element_provenance_scope_fk
                    ON dope_element_provenance(dope_scope_uuid);
                CREATE INDEX idx_dope_element_provenance_dirty
                    ON dope_element_provenance(dope_scope_uuid, locally_modified)
                    WHERE locally_modified = 1;
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [20, Store.isoNow()]
            )
        }

        // m0021 — the diagram vocabulary migration, and the LAST rebuild of
        // diagram_element this schema should ever need.
        //
        // Four things ride together because they are one table rebuild each
        // and SQLite cannot ALTER a CHECK:
        //
        // 1. diagram_element loses BOTH literal-list CHECKs. This is the
        //    debt DopeCogElement.swift:11-19 already named in writing:
        //
        //      "The registry below is the whole extensibility story, and it
        //       exists because of a specific piece of debt. m0010's
        //       `diagram_element.element_type` carries a `CHECK
        //       (element_type IN (...))`, so adding a type there means
        //       rebuilding the table ... Adding a second element type is:
        //       one case, one registry entry, one subtype table. Never a
        //       migration."
        //
        //    Prompt 9 adds two types at once, which is the moment that debt
        //    comes due twice. Validity moves wholly into
        //    DiagramElementTypeSpec: both write paths validate against the
        //    registry, fetchElementInfo THROWS corruptState on an unknown
        //    element_type at read, and the subtype tables' UNIQUE
        //    element_uuid remains the structural proof that exactly one
        //    subtype row exists per element. That is the COGS mitigation
        //    verbatim, applied to the family COGS was written about.
        //
        //    The parent-nullability CHECK goes with it: top-levelness is now
        //    `spec.allowedParentTypes == nil`, a registry fact, so a new
        //    top-level type is also no longer a migration.
        //
        // 2. diagram drops the INSTANCE tier. The ladder is
        //    project/session/prompt; instance_uuid and its chain CHECK go
        //    away, and session/prompt still reach an instance transitively
        //    via session -> instance where anything needs one.
        //
        // 3. The `gmcc_diagram_path IS NULL OR tier != 'PROJECT'` CHECK goes
        //    away. It existed because only an instance carried a checkout
        //    path; screenshots now materialize under CKFS storage, which
        //    every tier has, so a PROJECT-tier diagram finally has a
        //    resolvable storage root.
        //
        // 4. The two new element types get their subtype tables, and strokes
        //    get their packed representation as plain ADD COLUMNs.
        //
        // Live blast radius: 2 diagram rows, 27 diagram_element rows, and 0
        // rows in every drawing/vertex table. Cheapest this will ever be.
        migrator.registerMigration("m0021_diagramVocabularyAndTierCollapse") { db in
            let elementsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let diagramsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram") ?? -1

            // INSTANCE-tier rows become PROJECT-tier rather than being
            // deleted — this db is append-only history. project_uuid is
            // already NOT NULL on every row, so the chain stays valid. A
            // (project_uuid, code) collision would break the partial unique
            // index, so collided codes take a suffix instead of failing the
            // migration. Zero such rows live today; the SQL still has to be
            // correct on any database.
            try db.execute(sql: """
                UPDATE diagram
                   SET code = code || '_from_instance_' || substr(uuid, 1, 8)
                 WHERE tier = 'INSTANCE'
                   AND EXISTS (SELECT 1 FROM diagram other
                                WHERE other.tier = 'PROJECT'
                                  AND other.project_uuid = diagram.project_uuid
                                  AND other.code = diagram.code);
                """)

            try db.execute(sql: """
                CREATE TABLE diagram_new (
                    \(baseColumns),
                    project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                    session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                    tier TEXT NOT NULL
                        CHECK (tier IN ('PROJECT', 'SESSION', 'PROMPT')),
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    gmcc_diagram_path TEXT,
                    dope_scope_code TEXT,
                    -- Ghost-tolerant kbite binding, on the dope_scope_code
                    -- precedent: a CODE resolved at read time, never an FK,
                    -- so a kbite can evolve out from under a diagram.
                    kbite_code TEXT,
                    revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                    CHECK ((session_uuid IS NOT NULL) = (tier IN ('SESSION', 'PROMPT'))),
                    CHECK ((prompt_uuid IS NOT NULL) = (tier = 'PROMPT'))
                );

                INSERT INTO diagram_new
                    (id, uuid, version, created_at, updated_at, project_uuid,
                     session_uuid, prompt_uuid, tier, code, name, description,
                     gmcc_diagram_path, dope_scope_code, revision)
                SELECT id, uuid, version, created_at, updated_at, project_uuid,
                       session_uuid, prompt_uuid,
                       CASE tier WHEN 'INSTANCE' THEN 'PROJECT' ELSE tier END,
                       code, name, description, gmcc_diagram_path,
                       dope_scope_code, revision
                  FROM diagram;

                DROP TABLE diagram;
                ALTER TABLE diagram_new RENAME TO diagram;

                CREATE UNIQUE INDEX idx_diagram_project_code
                    ON diagram(project_uuid, code) WHERE tier = 'PROJECT';
                CREATE UNIQUE INDEX idx_diagram_session_code
                    ON diagram(session_uuid, code) WHERE tier = 'SESSION';
                CREATE UNIQUE INDEX idx_diagram_prompt_code
                    ON diagram(prompt_uuid, code) WHERE tier = 'PROMPT';
                CREATE INDEX idx_diagram_project_fk ON diagram(project_uuid);
                CREATE INDEX idx_diagram_session_fk ON diagram(session_uuid);
                CREATE INDEX idx_diagram_prompt_fk ON diagram(prompt_uuid);
                CREATE INDEX idx_diagram_dope_scope_code ON diagram(dope_scope_code);
                CREATE INDEX idx_diagram_kbite_code ON diagram(kbite_code);
                """)

            // diagram_element: same shape, minus both literal-list CHECKs.
            // The self-reference guard STAYS — it is a structural fact, not
            // a vocabulary one, and no registry can express it.
            try db.execute(sql: """
                CREATE TABLE diagram_element_new (
                    \(baseColumns),
                    diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                    parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    -- NO CHECK: validity is DiagramElementTypeSpec's, enforced
                    -- on both write paths and thrown on at read. See the
                    -- migration comment above and DopeCogElement.swift:11-19.
                    element_type TEXT NOT NULL,
                    code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT ''
                        CHECK (length(description) <= 512),
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    center_x REAL NOT NULL DEFAULT 0,
                    center_y REAL NOT NULL DEFAULT 0,
                    element_z REAL NOT NULL DEFAULT 0,
                    scale REAL NOT NULL DEFAULT 1 CHECK (scale > 0),
                    UNIQUE(diagram_uuid, code),
                    CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                );

                INSERT INTO diagram_element_new
                    (id, uuid, version, created_at, updated_at, diagram_uuid,
                     parent_element_uuid, element_type, code, name, description,
                     sort_order, center_x, center_y, element_z, scale)
                SELECT id, uuid, version, created_at, updated_at, diagram_uuid,
                       parent_element_uuid, element_type, code, name, description,
                       sort_order, center_x, center_y, element_z, scale
                  FROM diagram_element;

                DROP TABLE diagram_element;
                ALTER TABLE diagram_element_new RENAME TO diagram_element;

                CREATE INDEX idx_diagram_element_diagram_fk
                    ON diagram_element(diagram_uuid);
                CREATE INDEX idx_diagram_element_parent_fk
                    ON diagram_element(parent_element_uuid);
                """)

            // drawing_text — the first bounded element that is NOT
            // vertex-derived. Markdown wrapping needs a known layout width,
            // so the size is explicit here rather than re-derived from a
            // vertex bounding box on every render. It lives on the SUBTYPE,
            // so diagram_element gains no width/height and the composing
            // `scale` is untouched.
            try db.execute(sql: """
                CREATE TABLE diagram_drawing_text (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    markdown TEXT NOT NULL DEFAULT '',
                    width REAL NOT NULL CHECK (width > 0),
                    height REAL NOT NULL CHECK (height > 0),
                    font_size REAL NOT NULL DEFAULT 13 CHECK (font_size > 0),
                    text_color TEXT NOT NULL DEFAULT '#1a1a1a',
                    background_color TEXT
                );

                CREATE INDEX idx_diagram_drawing_text_element_fk
                    ON diagram_drawing_text(element_uuid);
                """)

            // connector — the diagram subsystem's FIRST element-to-element
            // reference.
            //
            // target_element_uuid is NULLABLE with ON DELETE SET NULL, and
            // that is load-bearing: ON DELETE CASCADE here would delete this
            // SUBTYPE row while its diagram_element row survived with no
            // subtype row at all, which is corruptState on every subsequent
            // read of the whole diagram. SET NULL degrades a deleted target
            // to a renderable ghost instead, matching the ghost-tolerant
            // doctrine the dope code bindings already use.
            //
            // The self-reference half of the containment rule is cheap
            // enough to state in SQL. The sibling half ("may target a peer
            // of its own parent") cannot be: a CHECK cannot reference
            // another table, which is the same reason m0016's binding rule
            // is a Swift guard. It lives in DiagramContainment, called by
            // both write paths.
            try db.execute(sql: """
                CREATE TABLE diagram_connector (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    target_element_uuid TEXT
                        REFERENCES diagram_element(uuid) ON DELETE SET NULL,
                    stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                    stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0),
                    line_style TEXT NOT NULL DEFAULT 'solid',
                    head_kind TEXT NOT NULL DEFAULT 'arrow',
                    label TEXT NOT NULL DEFAULT '',
                    CHECK (target_element_uuid IS NULL
                           OR target_element_uuid != element_uuid)
                );

                CREATE INDEX idx_diagram_connector_element_fk
                    ON diagram_connector(element_uuid);
                CREATE INDEX idx_diagram_connector_target_fk
                    ON diagram_connector(target_element_uuid);
                """)

            // Packed strokes, purely additive. diagram_stroke_vertex and
            // diagram_shape_vertex are untouched and their
            // FK-to-subtype-unique-column proof is undisturbed; the two
            // representations coexist behind DiagramElementTypeSpec's
            // storage axis. Read precedence: packed_vertices when non-NULL,
            // else the vertex rows. The write path writes the blob AND
            // deletes that element's vertex rows, so a contradictory pair
            // cannot exist. No backfill — 0 rows.
            try db.execute(sql: """
                ALTER TABLE diagram_drawing_stroke ADD COLUMN packed_vertices BLOB;
                ALTER TABLE diagram_drawing_stroke ADD COLUMN vertex_count INTEGER;
                """)

            let elementsAfter =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let diagramsAfter =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram") ?? -1
            guard elementsBefore == elementsAfter, diagramsBefore == diagramsAfter else {
                throw StoreError.corruptState(
                    entity: "diagram",
                    detail: "m0021 row-count mismatch: elements "
                          + "\(elementsBefore)->\(elementsAfter), diagrams "
                          + "\(diagramsBefore)->\(diagramsAfter)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [21, Store.isoNow()]
            )
        }

        // m0022 — prompt_qualified_diagram: what a prompt UNDERSTOOD when it
        // read a rendered diagram.
        //
        // Deliberately NOT modelled on the clarify/arch/explore/review
        // families. Those carry a status machine, findings rows and an FTS
        // mirror because a report is BUILT across many turns and needs to say
        // when it became trustworthy. This surface holds one sentence's worth
        // of standing fact — this prompt looked at this diagram at this
        // revision, and here is what it means — so a machine around it would
        // be ceremony, not safety. The restraint is the design.
        //
        // Nor is it a prompt_artifact row with a new kind: an artifact is a
        // POINTER whose content stays in a file, and the qualification is
        // content the db owns.
        //
        // rendered_revision and render_fingerprint are what make a stale
        // qualification detectable at all. The fingerprint is the same
        // serialized DiagramRenderFingerprint the renderer drops beside the
        // PNG, so a reader compares against a current render without
        // re-deriving anything — and it has to be the fingerprint rather than
        // the revision alone, because a bound dope tree moves under the
        // picture without ever touching diagram.revision.
        migrator.registerMigration("m0022_promptQualifiedDiagram") { db in
            try db.execute(sql: """
                CREATE TABLE prompt_qualified_diagram (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                    rendered_path TEXT NOT NULL,
                    rendered_revision INTEGER NOT NULL,
                    render_fingerprint TEXT NOT NULL,
                    qualification TEXT NOT NULL,
                    -- One row per pair: re-qualifying UPSERTS, so a prompt's
                    -- reading of a diagram is always its CURRENT reading and
                    -- never a pile of drafts a reader has to disambiguate.
                    UNIQUE(prompt_uuid, diagram_uuid)
                );

                CREATE INDEX idx_prompt_qualified_diagram_prompt_fk
                    ON prompt_qualified_diagram(prompt_uuid);
                CREATE INDEX idx_prompt_qualified_diagram_diagram_fk
                    ON prompt_qualified_diagram(diagram_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [22, Store.isoNow()]
            )
        }

        // m0023 — agent_briefing + prompt_activation: the context package a
        // doper agent assembles for a phase, and the activation registry that
        // lets hooks attribute work without arguments.
        //
        // agent_briefing follows m0022's restraint, not the report families:
        // a briefing is spawn-time plumbing consumed once, not a report built
        // across turns — so no findings children, no FTS mirror, and a
        // two-state consumption gate instead of a status machine. Re-opening
        // an existing (owner, step) pair RESETS the row to building: a step's
        // briefing is always its CURRENT briefing, never a pile of drafts.
        //
        // briefing_for_step and status carry NO db CHECK on purpose (the
        // m0021 vocabulary rule): validity lives in BriefingStepSpec, so a
        // future step (pre_implementation, pre_review) is a registry entry,
        // never a migration.
        //
        // Ownership: session_uuid is ALWAYS populated (the daemon derives it
        // from the prompt's owner chain), because it is the attribution
        // anchor for task-owned rows and the single list key for GMVibes.
        // prompt_uuid is NULL exactly when a /gm_task run owns the briefing.
        // SQLite UNIQUE admits multiple NULLs, so uniqueness is a partial
        // index PAIR: prompt-owned rows unique per (prompt, step), task-owned
        // rows unique per (session, step). "The prompt belongs to the
        // session" is a Swift store guard (m0016 precedent — a CHECK cannot
        // reference another table).
        //
        // dope_scope_uuid + dope_scope_revision are the staleness evidence
        // (m0022's fingerprint principle): stamped SERVER-SIDE at complete so
        // the writing agent cannot mis-stamp, compared against the live scope
        // revision at every read — the reader is WARNED about drift, never
        // blocked, honoring the fetch-fresh-per-phase guardrail.
        //
        // dope_refs holds DOT-PATHS and kbite_refs {file_uuid, brief} pairs
        // as TEXT JSON: point-in-time, deliberately non-normalized, dangling
        // refs are legal and render as ghosts (diagram-binding precedent).
        migrator.registerMigration("m0023_agentBriefing") { db in
            try db.execute(sql: """
                CREATE TABLE agent_briefing (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                    briefing_for_step TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'building',
                    body TEXT NOT NULL DEFAULT '',
                    dope_refs TEXT NOT NULL DEFAULT '[]',
                    kbite_refs TEXT NOT NULL DEFAULT '[]',
                    dope_scope_uuid TEXT REFERENCES dope_scope(uuid) ON DELETE SET NULL,
                    dope_scope_revision INTEGER
                );

                CREATE UNIQUE INDEX idx_agent_briefing_prompt_step
                    ON agent_briefing(prompt_uuid, briefing_for_step)
                    WHERE prompt_uuid IS NOT NULL;
                CREATE UNIQUE INDEX idx_agent_briefing_session_step
                    ON agent_briefing(session_uuid, briefing_for_step)
                    WHERE prompt_uuid IS NULL;
                CREATE INDEX idx_agent_briefing_session_fk
                    ON agent_briefing(session_uuid);
                CREATE INDEX idx_agent_briefing_prompt_fk
                    ON agent_briefing(prompt_uuid);

                -- The activation registry. NOT a single pointer on the
                -- session row: several Claude Code instances routinely run
                -- DIFFERENT prompts on the same GMCC session at once, and a
                -- last-writer-wins column would let the second instance steal
                -- the first's attribution. One row per running instance
                -- (client_key = the caller's nearest claude-ancestor process
                -- identity, resolved client-side by gm): set-status
                -- implementing claims it, done releases it. Attribution
                -- resolves caller's-own-activation first, then the session's
                -- single activation when unambiguous, else stays unattributed.
                CREATE TABLE prompt_activation (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    client_key TEXT NOT NULL
                );

                CREATE UNIQUE INDEX idx_prompt_activation_client
                    ON prompt_activation(client_key);
                CREATE UNIQUE INDEX idx_prompt_activation_prompt
                    ON prompt_activation(prompt_uuid);
                CREATE INDEX idx_prompt_activation_session_fk
                    ON prompt_activation(session_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [23, Store.isoNow()]
            )
        }

        // m0024 — Diagram Studio: the visibility axis, the first diagram FTS
        // mirror, the uml_node subtype, and connector routing/tail vocabulary.
        //
        // visibility is a NEW axis, not a tier: DiagramTier stays pure
        // ownership and --promote-tier is untouched. PRIVATE = db-only;
        // PUBLIC = repo-serializable, legal ONLY on SESSION-tier rows — a
        // Swift store guard mirroring Store+DopeRepo.requireRepoWritableScope
        // (m0016 precedent: the rule crosses tables, so no CHECK can hold
        // it). The column itself is CHECKless like every vocabulary column
        // since m0021: validity lives in DiagramVisibility.
        //
        // diagram_uml_node: ONE table for every UML node kind (node_kind is
        // the vocabulary column, the drawing_shape/shape_kind precedent) —
        // six tables would make reshape a delete+recreate, which ghosts
        // every incoming connector via target_element_uuid's ON DELETE SET
        // NULL. Explicit width/height like drawing_text: markdown wrapping
        // needs a known layout width, and the kit never measures text.
        // Chrome columns are nullable — nil means "theme default" so a node
        // with no explicit colors renders correctly in both schemes.
        //
        // routing_kind/tail_kind defaults reproduce the pre-m0024 render
        // byte-for-byte: orthogonal_step IS today's routed polyline and
        // every existing connector has no tail decoration.
        //
        // diagram_fts: the update trigger is deliberately AFTER UPDATE OF
        // code, name, description — the diagram row is the first FTS source
        // that is HOT on unrelated columns (revision bumps on every stroke),
        // and a plain AFTER UPDATE would churn the index once per pencil
        // gesture. Any future rebuild of the diagram table must recreate
        // this mirror and its triggers (external content binds rowid —
        // m0015's lesson).
        migrator.registerMigration("m0024_diagramStudio") { db in
            try db.execute(sql: """
                ALTER TABLE diagram ADD COLUMN visibility TEXT NOT NULL DEFAULT 'PRIVATE';
                CREATE INDEX idx_diagram_visibility ON diagram(visibility);

                ALTER TABLE diagram_connector ADD COLUMN routing_kind TEXT NOT NULL DEFAULT 'orthogonal_step';
                ALTER TABLE diagram_connector ADD COLUMN tail_kind TEXT NOT NULL DEFAULT 'none';
                """)

            try db.execute(sql: """
                CREATE TABLE diagram_uml_node (
                    \(baseColumns),
                    element_uuid TEXT NOT NULL UNIQUE
                        REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                    node_kind TEXT NOT NULL,
                    width REAL NOT NULL CHECK (width > 0),
                    height REAL NOT NULL CHECK (height > 0),
                    markdown TEXT NOT NULL DEFAULT '',
                    font_size REAL CHECK (font_size IS NULL OR font_size > 0),
                    text_color TEXT,
                    stroke_color TEXT,
                    stroke_width REAL CHECK (stroke_width IS NULL OR stroke_width > 0),
                    fill_color TEXT
                );

                CREATE INDEX idx_diagram_uml_node_element_fk
                    ON diagram_uml_node(element_uuid);
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE diagram_fts USING fts5(
                    code, name, description,
                    content='diagram', content_rowid='id'
                );

                CREATE TRIGGER diagram_ai AFTER INSERT ON diagram BEGIN
                    INSERT INTO diagram_fts(rowid, code, name, description)
                    VALUES (new.id, new.code, new.name, new.description);
                END;
                CREATE TRIGGER diagram_ad AFTER DELETE ON diagram BEGIN
                    INSERT INTO diagram_fts(diagram_fts, rowid, code, name, description)
                    VALUES ('delete', old.id, old.code, old.name, old.description);
                END;
                CREATE TRIGGER diagram_au AFTER UPDATE OF code, name, description ON diagram BEGIN
                    INSERT INTO diagram_fts(diagram_fts, rowid, code, name, description)
                    VALUES ('delete', old.id, old.code, old.name, old.description);
                    INSERT INTO diagram_fts(rowid, code, name, description)
                    VALUES (new.id, new.code, new.name, new.description);
                END;

                INSERT INTO diagram_fts(diagram_fts) VALUES ('rebuild');
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [24, Store.isoNow()]
            )
        }

        // m0025 — Dynamic workflows train. PRECONDITION: a BACKUP.
        //
        // One train, not five: later slices build against final shapes.
        // Rebuilds use the m0005 create-copy-drop-rename grammar; every
        // rebuilt table drops its pre-m0021 CHECKs (vocabulary lives in
        // Swift registries); every FTS mirror on a rebuilt table is
        // recreated (m0015: external content binds rowid, DROP TABLE takes
        // the triggers with it).
        //
        // Deliberate data transformations (the only history rewrites):
        // - exploration_summary rows migrate as agent_type='synthesis' —
        //   which is what they were: per-prompt synthesis aggregates. The
        //   per-prompt seal IS the synthesis-type row from now on.
        // - exploration_key_file rows become findings (kind='key_file',
        //   title=path, agent_name='legacy'); the table and its mirror drop.
        // - agent_briefing bodies are DROPPED (user decision: briefings are
        //   opinion-free ref sets); dope_refs/kbite_refs explode into child
        //   rows. pre_architecture briefings retag to 'initial' where the
        //   slot is free, else delete (consumed one-shot spawn plumbing).
        // - clarification rows split: user/unanswered → question rows,
        //   bot_inferred → internal notes. refined_goal/refined_detail/
        //   backstory_note are preserved by seeding a care_package row per
        //   summary that carried text — nothing authored is destroyed.
        // - The finalize→prompt.goal copy is RETIRED in the Swift layer:
        //   ZERO bot write doors to prompt content remain.
        migrator.registerMigration("m0025_dynamicWorkflows") { db in
            // ---- Stash rows whose source columns are about to drop.
            let briefingRefs = try Row.fetchAll(db, sql: """
                SELECT uuid, dope_refs, kbite_refs FROM agent_briefing
                """)
            let summaryText = try Row.fetchAll(db, sql: """
                SELECT uuid, refined_goal, refined_detail, backstory_note
                FROM clarification_summary
                WHERE refined_goal != '' OR refined_detail != '' OR backstory_note != ''
                """)
            let explorationCounts = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM exploration_summary
                """) ?? 0

            // ---- agent_briefing: retag pre_architecture as initial
            // (user: "migrate everything as explore ones"), initial wins
            // collisions.
            try db.execute(sql: """
                DELETE FROM agent_briefing
                WHERE briefing_for_step = 'pre_architecture'
                  AND EXISTS (
                    SELECT 1 FROM agent_briefing b2
                    WHERE b2.briefing_for_step = 'initial'
                      AND (b2.prompt_uuid = agent_briefing.prompt_uuid
                           OR (b2.prompt_uuid IS NULL
                               AND agent_briefing.prompt_uuid IS NULL
                               AND b2.session_uuid = agent_briefing.session_uuid))
                  );
                UPDATE agent_briefing SET briefing_for_step = 'initial'
                WHERE briefing_for_step = 'pre_architecture';
                """)

            // ---- agent_briefing rebuild: body/dope_refs/kbite_refs drop.
            try db.execute(sql: """
                CREATE TABLE agent_briefing_new (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                    briefing_for_step TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'building',
                    agent_id TEXT,
                    dope_scope_uuid TEXT REFERENCES dope_scope(uuid) ON DELETE SET NULL,
                    dope_scope_revision INTEGER
                );
                INSERT INTO agent_briefing_new
                    (id, uuid, version, created_at, updated_at, session_uuid,
                     prompt_uuid, briefing_for_step, status, agent_id,
                     dope_scope_uuid, dope_scope_revision)
                SELECT id, uuid, version, created_at, updated_at, session_uuid,
                       prompt_uuid, briefing_for_step, status, NULL,
                       dope_scope_uuid, dope_scope_revision
                FROM agent_briefing;
                DROP TABLE agent_briefing;
                ALTER TABLE agent_briefing_new RENAME TO agent_briefing;

                CREATE UNIQUE INDEX idx_agent_briefing_prompt_step
                    ON agent_briefing(prompt_uuid, briefing_for_step)
                    WHERE prompt_uuid IS NOT NULL;
                CREATE UNIQUE INDEX idx_agent_briefing_session_step
                    ON agent_briefing(session_uuid, briefing_for_step)
                    WHERE prompt_uuid IS NULL;
                CREATE INDEX idx_agent_briefing_session_fk
                    ON agent_briefing(session_uuid);
                CREATE INDEX idx_agent_briefing_prompt_fk
                    ON agent_briefing(prompt_uuid);

                -- Briefing ref children. Dope refs are dot-path CODES, never
                -- FKs (diagram ghost-binding precedent: dope deletes must
                -- never block on or cascade into briefing history). Kbite
                -- and file-change refs use uuid FKs — stable ids whose
                -- deletion is an explicit destructive verb.
                CREATE TABLE agent_briefing_dope_persistence (
                    \(baseColumns),
                    agent_briefing_uuid TEXT NOT NULL
                        REFERENCES agent_briefing(uuid) ON DELETE CASCADE,
                    dope_code TEXT NOT NULL,
                    brief TEXT,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_agent_briefing_dope_persistence_fk
                    ON agent_briefing_dope_persistence(agent_briefing_uuid);

                CREATE TABLE agent_briefing_dope_kbite (
                    \(baseColumns),
                    agent_briefing_uuid TEXT NOT NULL
                        REFERENCES agent_briefing(uuid) ON DELETE CASCADE,
                    kbite_resource_file_uuid TEXT NOT NULL
                        REFERENCES kbite_resource_file(uuid) ON DELETE CASCADE,
                    brief TEXT,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_agent_briefing_dope_kbite_fk
                    ON agent_briefing_dope_kbite(agent_briefing_uuid);

                CREATE TABLE agent_session_file_change (
                    \(baseColumns),
                    agent_briefing_uuid TEXT NOT NULL
                        REFERENCES agent_briefing(uuid) ON DELETE CASCADE,
                    file_change_uuid TEXT NOT NULL
                        REFERENCES file_change(uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_agent_session_file_change_fk
                    ON agent_session_file_change(agent_briefing_uuid);
                """)

            // Explode the stashed TEXT-JSON refs into child rows. Survivors
            // only — retagged deletions above already removed their parents.
            let now = Store.isoNow()
            let survivors = try Set(String.fetchAll(db, sql: "SELECT uuid FROM agent_briefing"))
            for row in briefingRefs {
                let briefingUuid: String = row["uuid"]
                guard survivors.contains(briefingUuid) else { continue }
                let decoder = JSONDecoder()
                if let dopeData = (row["dope_refs"] as String?)?.data(using: .utf8),
                   let codes = try? decoder.decode([String].self, from: dopeData) {
                    for (i, code) in codes.enumerated() {
                        try db.execute(sql: """
                            INSERT INTO agent_briefing_dope_persistence
                                (uuid, version, created_at, updated_at,
                                 agent_briefing_uuid, dope_code, brief, seq)
                            VALUES (?, 0, ?, ?, ?, ?, NULL, ?)
                            """, arguments: [Store.newUuid(), now, now, briefingUuid, code, i])
                    }
                }
                struct KbiteRef: Decodable { let file_uuid: String; let brief: String? }
                if let kbiteData = (row["kbite_refs"] as String?)?.data(using: .utf8),
                   let refs = try? decoder.decode([KbiteRef].self, from: kbiteData) {
                    for (i, ref) in refs.enumerated() {
                        // Guard the FK: a ref to a since-deleted kbite file
                        // is dropped rather than failing the train.
                        let exists = try Bool.fetchOne(db, sql: """
                            SELECT EXISTS(SELECT 1 FROM kbite_resource_file WHERE uuid = ?)
                            """, arguments: [ref.file_uuid]) ?? false
                        guard exists else { continue }
                        try db.execute(sql: """
                            INSERT INTO agent_briefing_dope_kbite
                                (uuid, version, created_at, updated_at,
                                 agent_briefing_uuid, kbite_resource_file_uuid, brief, seq)
                            VALUES (?, 0, ?, ?, ?, ?, ?, ?)
                            """, arguments: [Store.newUuid(), now, now, briefingUuid,
                                             ref.file_uuid, ref.brief, i])
                    }
                }
            }

            // ---- exploration_summary rebuild: literal per-agent rows.
            try db.execute(sql: """
                DROP TABLE exploration_summary_fts;

                CREATE TABLE exploration_summary_new (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    agent_type TEXT NOT NULL DEFAULT 'general',
                    agent_id TEXT,
                    status TEXT NOT NULL DEFAULT 'exploring',
                    overview TEXT NOT NULL DEFAULT '',
                    UNIQUE(prompt_uuid, agent_type)
                );
                INSERT INTO exploration_summary_new
                    (id, uuid, version, created_at, updated_at, prompt_uuid,
                     agent_type, agent_id, status, overview)
                SELECT id, uuid, version, created_at, updated_at, prompt_uuid,
                       'synthesis', NULL, status, overview
                FROM exploration_summary;
                DROP TABLE exploration_summary;
                ALTER TABLE exploration_summary_new RENAME TO exploration_summary;

                CREATE INDEX idx_exploration_summary_prompt_uuid
                    ON exploration_summary(prompt_uuid);

                CREATE VIRTUAL TABLE exploration_summary_fts USING fts5(
                    overview,
                    content='exploration_summary',
                    content_rowid='id'
                );
                CREATE TRIGGER exploration_summary_ai AFTER INSERT ON exploration_summary BEGIN
                    INSERT INTO exploration_summary_fts(rowid, overview)
                    VALUES (new.id, new.overview);
                END;
                CREATE TRIGGER exploration_summary_ad AFTER DELETE ON exploration_summary BEGIN
                    INSERT INTO exploration_summary_fts(exploration_summary_fts, rowid, overview)
                    VALUES ('delete', old.id, old.overview);
                END;
                CREATE TRIGGER exploration_summary_au AFTER UPDATE ON exploration_summary BEGIN
                    INSERT INTO exploration_summary_fts(exploration_summary_fts, rowid, overview)
                    VALUES ('delete', old.id, old.overview);
                    INSERT INTO exploration_summary_fts(rowid, overview)
                    VALUES (new.id, new.overview);
                END;
                INSERT INTO exploration_summary_fts(exploration_summary_fts) VALUES ('rebuild');
                """)
            let migratedSummaries = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM exploration_summary") ?? 0
            guard migratedSummaries == explorationCounts else {
                throw DatabaseError(message: "m0025: exploration_summary parity failed")
            }

            // ---- exploration_finding rebuild: absorbs exploration_key_file.
            try db.execute(sql: """
                DROP TABLE exploration_finding_fts;
                DROP TABLE exploration_key_file_fts;

                CREATE TABLE exploration_finding_new (
                    \(baseColumns),
                    exploration_summary_uuid TEXT NOT NULL
                        REFERENCES exploration_summary(uuid) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    file_path TEXT,
                    agent_name TEXT NOT NULL,
                    agent_id TEXT,
                    finding_rating INTEGER
                );
                INSERT INTO exploration_finding_new
                    (id, uuid, version, created_at, updated_at,
                     exploration_summary_uuid, kind, title, body, file_path,
                     agent_name, agent_id, finding_rating)
                SELECT id, uuid, version, created_at, updated_at,
                       exploration_summary_uuid, kind, title, body, NULL,
                       agent_name, NULL, finding_rating
                FROM exploration_finding;
                INSERT INTO exploration_finding_new
                    (uuid, version, created_at, updated_at,
                     exploration_summary_uuid, kind, title, body, file_path,
                     agent_name, agent_id, finding_rating)
                SELECT uuid, version, created_at, updated_at,
                       exploration_summary_uuid, 'key_file', file_path, '',
                       file_path, 'legacy', NULL, NULL
                FROM exploration_key_file;
                DROP TABLE exploration_finding;
                DROP TABLE exploration_key_file;
                ALTER TABLE exploration_finding_new RENAME TO exploration_finding;

                CREATE INDEX idx_exploration_finding_summary_fk
                    ON exploration_finding(exploration_summary_uuid);

                CREATE VIRTUAL TABLE exploration_finding_fts USING fts5(
                    title, body, file_path,
                    content='exploration_finding',
                    content_rowid='id'
                );
                CREATE TRIGGER exploration_finding_ai AFTER INSERT ON exploration_finding BEGIN
                    INSERT INTO exploration_finding_fts(rowid, title, body, file_path)
                    VALUES (new.id, new.title, new.body, new.file_path);
                END;
                CREATE TRIGGER exploration_finding_ad AFTER DELETE ON exploration_finding BEGIN
                    INSERT INTO exploration_finding_fts(exploration_finding_fts, rowid, title, body, file_path)
                    VALUES ('delete', old.id, old.title, old.body, old.file_path);
                END;
                CREATE TRIGGER exploration_finding_au AFTER UPDATE ON exploration_finding BEGIN
                    INSERT INTO exploration_finding_fts(exploration_finding_fts, rowid, title, body, file_path)
                    VALUES ('delete', old.id, old.title, old.body, old.file_path);
                    INSERT INTO exploration_finding_fts(rowid, title, body, file_path)
                    VALUES (new.id, new.title, new.body, new.file_path);
                END;
                INSERT INTO exploration_finding_fts(exploration_finding_fts) VALUES ('rebuild');
                """)

            // ---- care_package (created BEFORE the summary rebuild so the
            // seeds below can preserve the dropping text columns).
            try db.execute(sql: """
                CREATE TABLE care_package (
                    \(baseColumns),
                    clarification_summary_uuid TEXT NOT NULL UNIQUE
                        REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                    clarified_intent TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT 'building',
                    dope_scope_uuid TEXT REFERENCES dope_scope(uuid) ON DELETE SET NULL,
                    dope_scope_revision INTEGER
                );

                CREATE TABLE care_package_dope_ref (
                    \(baseColumns),
                    care_package_uuid TEXT NOT NULL
                        REFERENCES care_package(uuid) ON DELETE CASCADE,
                    dope_code TEXT NOT NULL,
                    note TEXT,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_care_package_dope_ref_fk
                    ON care_package_dope_ref(care_package_uuid);

                CREATE TABLE care_package_kbite_ref (
                    \(baseColumns),
                    care_package_uuid TEXT NOT NULL
                        REFERENCES care_package(uuid) ON DELETE CASCADE,
                    kbite_resource_file_uuid TEXT NOT NULL
                        REFERENCES kbite_resource_file(uuid) ON DELETE CASCADE,
                    brief TEXT,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_care_package_kbite_ref_fk
                    ON care_package_kbite_ref(care_package_uuid);

                CREATE TABLE care_package_exploration_ref (
                    \(baseColumns),
                    care_package_uuid TEXT NOT NULL
                        REFERENCES care_package(uuid) ON DELETE CASCADE,
                    curated_title TEXT NOT NULL,
                    curated_body TEXT NOT NULL,
                    file_path TEXT,
                    source_finding_uuid TEXT
                        REFERENCES exploration_finding(uuid) ON DELETE SET NULL,
                    seq INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_care_package_exploration_ref_fk
                    ON care_package_exploration_ref(care_package_uuid);
                """)

            // Preserve legacy refined_goal/refined_detail/backstory_note —
            // after the rebuild nothing else holds that authored text.
            for row in summaryText {
                let summaryUuid: String = row["uuid"]
                var parts: [String] = []
                let goal: String = row["refined_goal"] ?? ""
                let detail: String = row["refined_detail"] ?? ""
                let note: String = row["backstory_note"] ?? ""
                if !goal.isEmpty { parts.append("# Refined goal (legacy)\n\n" + goal) }
                if !detail.isEmpty { parts.append("# Refined detail (legacy)\n\n" + detail) }
                if !note.isEmpty { parts.append("# Backstory note (legacy)\n\n" + note) }
                try db.execute(sql: """
                    INSERT INTO care_package
                        (uuid, version, created_at, updated_at,
                         clarification_summary_uuid, clarified_intent, status)
                    VALUES (?, 0, ?, ?, ?, ?, 'ready')
                    """, arguments: [Store.newUuid(), now, now, summaryUuid,
                                     parts.joined(separator: "\n\n")])
            }

            // ---- clarification_summary rebuild: the three text fields drop
            // (their mirror goes with them — nothing left to index).
            try db.execute(sql: """
                DROP TABLE clarification_summary_fts;

                CREATE TABLE clarification_summary_new (
                    \(baseColumns),
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    status TEXT NOT NULL DEFAULT 'building',
                    UNIQUE(prompt_uuid)
                );
                INSERT INTO clarification_summary_new
                    (id, uuid, version, created_at, updated_at, prompt_uuid, status)
                SELECT id, uuid, version, created_at, updated_at, prompt_uuid, status
                FROM clarification_summary;
                DROP TABLE clarification_summary;
                ALTER TABLE clarification_summary_new RENAME TO clarification_summary;

                CREATE INDEX idx_clarification_summary_prompt_uuid
                    ON clarification_summary(prompt_uuid);
                """)

            // ---- clarification split: questions / options / answers / notes.
            try db.execute(sql: """
                CREATE TABLE user_clarification_question (
                    \(baseColumns),
                    clarification_summary_uuid TEXT NOT NULL
                        REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL,
                    question TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'open',
                    answer_text TEXT,
                    agent_id TEXT,
                    agent_name TEXT,
                    UNIQUE(clarification_summary_uuid, seq)
                );
                CREATE INDEX idx_user_clarification_question_fk
                    ON user_clarification_question(clarification_summary_uuid);

                CREATE TABLE user_clarification_option (
                    \(baseColumns),
                    question_uuid TEXT NOT NULL
                        REFERENCES user_clarification_question(uuid) ON DELETE CASCADE,
                    seq INTEGER NOT NULL,
                    body TEXT NOT NULL,
                    UNIQUE(question_uuid, seq)
                );
                CREATE INDEX idx_user_clarification_option_fk
                    ON user_clarification_option(question_uuid);

                -- The selected answer(s): a junction, not an answer_uuid
                -- column — single-select is 0/1 rows, multi-select and
                -- GMVibes-side answering are purely additive later.
                CREATE TABLE user_clarification_answer (
                    \(baseColumns),
                    question_uuid TEXT NOT NULL
                        REFERENCES user_clarification_question(uuid) ON DELETE CASCADE,
                    option_uuid TEXT NOT NULL
                        REFERENCES user_clarification_option(uuid) ON DELETE CASCADE,
                    UNIQUE(question_uuid, option_uuid)
                );
                CREATE INDEX idx_user_clarification_answer_fk
                    ON user_clarification_answer(question_uuid);

                CREATE TABLE internal_clarification_note (
                    \(baseColumns),
                    clarification_summary_uuid TEXT NOT NULL
                        REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                    body TEXT NOT NULL,
                    confused_entity_uuid TEXT,
                    confused_entity_type TEXT,
                    weight INTEGER,
                    question_uuid TEXT
                        REFERENCES user_clarification_question(uuid) ON DELETE SET NULL,
                    agent_id TEXT,
                    agent_name TEXT
                );
                CREATE INDEX idx_internal_clarification_note_fk
                    ON internal_clarification_note(clarification_summary_uuid);

                -- Legacy copy: bot_inferred rows become internal notes,
                -- everything else becomes a user question.
                INSERT INTO user_clarification_question
                    (uuid, version, created_at, updated_at,
                     clarification_summary_uuid, seq, question, status,
                     answer_text, agent_id, agent_name)
                SELECT uuid, version, created_at, updated_at,
                       clarification_summary_uuid, seq, question, status,
                       answer, NULL, 'legacy'
                FROM clarification
                WHERE answer_source IS NULL OR answer_source != 'bot_inferred';

                INSERT INTO internal_clarification_note
                    (uuid, version, created_at, updated_at,
                     clarification_summary_uuid, body, weight, agent_name)
                SELECT uuid, version, created_at, updated_at,
                       clarification_summary_uuid,
                       'Q: ' || question || char(10) || 'A: ' || COALESCE(answer, ''),
                       NULL, 'legacy'
                FROM clarification
                WHERE answer_source = 'bot_inferred';

                DROP TABLE clarification_fts;
                DROP TABLE clarification;

                CREATE VIRTUAL TABLE user_clarification_question_fts USING fts5(
                    question, answer_text,
                    content='user_clarification_question',
                    content_rowid='id'
                );
                CREATE TRIGGER user_clarification_question_ai AFTER INSERT ON user_clarification_question BEGIN
                    INSERT INTO user_clarification_question_fts(rowid, question, answer_text)
                    VALUES (new.id, new.question, new.answer_text);
                END;
                CREATE TRIGGER user_clarification_question_ad AFTER DELETE ON user_clarification_question BEGIN
                    INSERT INTO user_clarification_question_fts(user_clarification_question_fts, rowid, question, answer_text)
                    VALUES ('delete', old.id, old.question, old.answer_text);
                END;
                CREATE TRIGGER user_clarification_question_au AFTER UPDATE ON user_clarification_question BEGIN
                    INSERT INTO user_clarification_question_fts(user_clarification_question_fts, rowid, question, answer_text)
                    VALUES ('delete', old.id, old.question, old.answer_text);
                    INSERT INTO user_clarification_question_fts(rowid, question, answer_text)
                    VALUES (new.id, new.question, new.answer_text);
                END;
                INSERT INTO user_clarification_question_fts(user_clarification_question_fts) VALUES ('rebuild');

                CREATE VIRTUAL TABLE internal_clarification_note_fts USING fts5(
                    body,
                    content='internal_clarification_note',
                    content_rowid='id'
                );
                CREATE TRIGGER internal_clarification_note_ai AFTER INSERT ON internal_clarification_note BEGIN
                    INSERT INTO internal_clarification_note_fts(rowid, body)
                    VALUES (new.id, new.body);
                END;
                CREATE TRIGGER internal_clarification_note_ad AFTER DELETE ON internal_clarification_note BEGIN
                    INSERT INTO internal_clarification_note_fts(internal_clarification_note_fts, rowid, body)
                    VALUES ('delete', old.id, old.body);
                END;
                CREATE TRIGGER internal_clarification_note_au AFTER UPDATE ON internal_clarification_note BEGIN
                    INSERT INTO internal_clarification_note_fts(internal_clarification_note_fts, rowid, body)
                    VALUES ('delete', old.id, old.body);
                    INSERT INTO internal_clarification_note_fts(rowid, body)
                    VALUES (new.id, new.body);
                END;
                INSERT INTO internal_clarification_note_fts(internal_clarification_note_fts) VALUES ('rebuild');
                """)

            // ---- architecture options + delta/dope linkage columns.
            try db.execute(sql: """
                CREATE TABLE architecture_option (
                    \(baseColumns),
                    architecture_summary_uuid TEXT NOT NULL
                        REFERENCES architecture_summary(uuid) ON DELETE CASCADE,
                    agent_name TEXT NOT NULL,
                    agent_id TEXT,
                    body TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'proposed',
                    UNIQUE(architecture_summary_uuid, agent_name)
                );
                CREATE INDEX idx_architecture_option_summary_fk
                    ON architecture_option(architecture_summary_uuid);

                ALTER TABLE architecture_summary
                    ADD COLUMN decision_rationale TEXT NOT NULL DEFAULT '';
                ALTER TABLE architecture_persistence_change
                    ADD COLUMN change_kind TEXT NOT NULL DEFAULT 'modify';
                ALTER TABLE architecture_persistence_change
                    ADD COLUMN dope_ref TEXT;
                ALTER TABLE architecture_persistence_field_change
                    ADD COLUMN change_kind TEXT NOT NULL DEFAULT 'add';
                ALTER TABLE architecture_persistence_field_change
                    ADD COLUMN renamed_from TEXT;
                ALTER TABLE architecture_persistence_field_change
                    ADD COLUMN dope_property_ref TEXT;
                """)

            // ---- file_change attribution axis + agent_id sweep.
            try db.execute(sql: """
                ALTER TABLE file_change ADD COLUMN agent_id TEXT;
                ALTER TABLE file_change ADD COLUMN agent_name TEXT;
                ALTER TABLE file_change ADD COLUMN workflow_phase TEXT;
                ALTER TABLE file_change ADD COLUMN origin TEXT NOT NULL DEFAULT 'hook';
                ALTER TABLE review_summary ADD COLUMN agent_id TEXT;
                ALTER TABLE review_finding ADD COLUMN agent_id TEXT;
                """)

            // ---- bot_workflow: the daemon-held workflow state machine row.
            // Deliberately thin: phase is DERIVED from db evidence at every
            // BOT_NEXT — last_served_phase is observability only, so resume
            // is literally the first-run code path. task variant gets NO
            // row (its write-nothing contract).
            try db.execute(sql: """
                CREATE TABLE bot_workflow (
                    \(baseColumns),
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                    variant TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active',
                    client_key TEXT,
                    last_served_phase TEXT,
                    reconcile_git_head TEXT
                );
                CREATE UNIQUE INDEX idx_bot_workflow_prompt_active
                    ON bot_workflow(prompt_uuid) WHERE status = 'active';
                CREATE UNIQUE INDEX idx_bot_workflow_client_active
                    ON bot_workflow(client_key)
                    WHERE status = 'active' AND client_key IS NOT NULL;
                CREATE INDEX idx_bot_workflow_session_fk
                    ON bot_workflow(session_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [25, Store.isoNow()]
            )
        }

        // m0026 — Session-bound hook attribution. PRECONDITION: a BACKUP.
        //
        // One attribution path, resolved from the PostToolUse payload plus
        // the db. claude_session_binding maps Claude Code's conversation uuid
        // to a gmcc session; agent_registration answers "who is agent X" for
        // an opaque agent_id; file_change grows the typed payload columns the
        // two resolve against. Pure ADD — file_change carries a CHECK only on
        // change_kind, which is untouched, so no table is rebuilt.
        //
        // claude_turn_id is THE naming trap of this migration. The payload
        // field is called prompt_id, but it is Claude Code's TURN id and has
        // nothing to do with a gmcc prompt uuid; the column is named for what
        // it holds so the confusion cannot be inherited by a reader.
        //
        // The new columns are NULL for every pre-m0026 row. There is no
        // backfill: nothing outside a payload can know a tool_use_id.
        migrator.registerMigration("m0026_claudeSessionAttribution") { db in
            // ---- claude_session_binding: the payload-side attribution key.
            // A gmcc session is instance+branch; this key is Claude Code's
            // conversation uuid — different things, hence the qualified name.
            // It pins the SESSION, not a prompt: at SessionStart the prompt
            // usually does not exist yet, and one conversation legitimately
            // walks several prompts, so the prompt stays live-derived from
            // the pinned session.
            try db.execute(sql: """
                CREATE TABLE claude_session_binding (
                    \(baseColumns),
                    claude_session_id TEXT NOT NULL,
                    session_uuid TEXT NOT NULL REFERENCES session(uuid) ON DELETE CASCADE
                );

                -- THIS INDEX IS THE PIN-ONCE DECISION: the binding is written
                -- once at SessionStart and an INSERT OR IGNORE re-run bounces
                -- off the index, so pin-once is a schema fact rather than a
                -- branch in Swift that some later caller can skip. There is
                -- deliberately NO other column here — a mid-session checkout
                -- leaves the binding pointing at the old branch's session and
                -- that staleness is ACCEPTED, undetected, by decision. A
                -- column nobody reads (a branch, a bound-at, an invalidated
                -- flag) is the first step back toward the drift detection and
                -- re-binding that were declined.
                CREATE UNIQUE INDEX idx_claude_session_binding_claude_session_id
                    ON claude_session_binding(claude_session_id);
                CREATE INDEX idx_claude_session_binding_session_fk
                    ON claude_session_binding(session_uuid);
                """)

            // ---- agent_registration: identity for an opaque agent_id.
            // Two writers merge into ONE row per agent: the SubagentStart
            // hook writes IDENTITY (agent_id, agent_type, claude ids, the
            // resolved session), AGENT_REGISTER writes AUTHORITY (role,
            // methodology, workflow_phase). The join happens at READ time, so
            // ordering is not a constraint — a spawner that only learns agent
            // ids when a dynamic workflow reports back registers late and
            // still explains rows already written.
            //
            // NOT a reuse of agent_briefing, and the two are adjacent enough
            // to be confused: a briefing answers "what refs did this agent
            // get", a registration answers "who is agent X". The briefing's
            // UNIQUE(prompt_uuid, briefing_for_step) cannot hold four
            // same-typed explorers, which is the exact case this table is for.
            try db.execute(sql: """
                CREATE TABLE agent_registration (
                    \(baseColumns),
                    -- Opaque, NEVER parsed. The shape varies by spawn kind
                    -- (a<hex> anonymous, a<name>-<hex> named) and reading
                    -- structure into it would make the registry wrong for
                    -- whichever shape ships next.
                    agent_id TEXT NOT NULL,
                    -- Locates the agent but cannot discriminate it: every
                    -- spawn shape shares the primary's conversation.
                    claude_session_id TEXT,
                    -- Claude Code's TURN id (payload field name: prompt_id).
                    -- NOT a gmcc prompt uuid — see the header note.
                    claude_turn_id TEXT,
                    session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                    prompt_uuid TEXT REFERENCES prompt(uuid),
                    -- Payload LABEL only, never authoritative: it is
                    -- overloaded by spawn shape — a plain subagent reports
                    -- its subagent_type, a bare workflow agent reports the
                    -- literal workflow-subagent, a named teammate reports
                    -- the NAME.
                    agent_type TEXT,
                    -- SPAWNER-authoritative, all three: no spawn shape
                    -- delivers role and methodology, and four identical
                    -- personas differ by agent_id alone. For a bare workflow
                    -- agent the role exists nowhere but the spawning script.
                    role TEXT,
                    methodology TEXT,
                    workflow_phase TEXT
                );

                -- UNIQUE on agent_id ALONE: the spawner holds exactly one
                -- identifier (the Agent tool hands agent_id back) and cannot
                -- see Claude Code's session_id from a shell, so any wider key
                -- would put the authority write out of reach of its writer.
                CREATE UNIQUE INDEX idx_agent_registration_agent_id
                    ON agent_registration(agent_id);
                CREATE INDEX idx_agent_registration_prompt_fk
                    ON agent_registration(prompt_uuid);
                """)

            // ---- file_change: the payload capture set, one typed column per
            // field rather than a blob, so every axis is queryable. agent_id
            // already exists and stays the single agent-id concept on this
            // table — the hook stamps it from the payload; agent_type here is
            // the payload's overloaded label alongside it.
            try db.execute(sql: """
                ALTER TABLE file_change ADD COLUMN claude_session_id TEXT;
                ALTER TABLE file_change ADD COLUMN claude_turn_id TEXT;
                ALTER TABLE file_change ADD COLUMN tool_use_id TEXT;
                ALTER TABLE file_change ADD COLUMN tool_name TEXT;
                ALTER TABLE file_change ADD COLUMN agent_type TEXT;
                ALTER TABLE file_change ADD COLUMN permission_mode TEXT;
                ALTER TABLE file_change ADD COLUMN duration_ms INTEGER;
                ALTER TABLE file_change ADD COLUMN transcript_path TEXT;
                -- The authoritative link from a change to the identity that
                -- made it. NULLABLE IS FORCED, not a softening: the primary
                -- carries no agent_id at all — that ABSENCE is the
                -- primary/subagent discriminator — so a primary write has
                -- nothing to point at and NOT NULL would make the primary
                -- unrecordable. NULL for primary writes, non-NULL for every
                -- agent write.
                ALTER TABLE file_change ADD COLUMN agent_registration_uuid TEXT
                    REFERENCES agent_registration(uuid);

                -- Idempotency, keyed on the PAIR. A bare UNIQUE(tool_use_id)
                -- would make Bash capture impossible: one `sed -i a b c` is
                -- one tool_use_id and three file_change rows. The unit is
                -- (tool call, file), which degenerates to one row per call
                -- for Edit/Write/NotebookEdit. Partial so the column stays
                -- free for every row that has no tool call behind it.
                CREATE UNIQUE INDEX idx_file_change_tool_use
                    ON file_change(tool_use_id, session_file_uuid)
                    WHERE tool_use_id IS NOT NULL;

                CREATE INDEX idx_file_change_claude_session_id
                    ON file_change(claude_session_id);
                CREATE INDEX idx_file_change_agent_id
                    ON file_change(agent_id);
                CREATE INDEX idx_file_change_agent_registration_fk
                    ON file_change(agent_registration_uuid);
                """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [26, Store.isoNow()]
            )
        }

        return migrator
    }
}
