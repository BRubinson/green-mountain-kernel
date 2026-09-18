import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // The prompt lifecycle collapse. TWO independent halves in one
    // migration, and they are here together only because they were decided
    // together — neither needs the other to be correct.
    //
    // (a) DATA. The four middle prompt states fold into `initiated`. Safe
    // because phase was never derived from status — BOT_NEXT reads db
    // evidence — so no in-flight prompt loses its place.
    //
    // This is NOT the bare UPDATE it looks like it should be. `prompt.status`
    // carries a CHECK naming all six old states, so the data and the
    // constraint have to move together or each rejects the other: an UPDATE
    // to 'initiated' fails the OLD check, and installing the NEW check first
    // fails on the rows still holding old values. The remap therefore rides
    // inside `prompt`'s own rebuild, as a CASE in the copy.
    //
    // (b) SCHEMA. Six per-prompt UNIQUE constraints come off, so a prompt
    // sent back to draft can be run a second time and get a second set of
    // summaries. SQLite cannot drop an inline UNIQUE: the constraint is a
    // `sqlite_autoindex_*` that DROP INDEX refuses. Each table therefore
    // goes through the documented 12-step rebuild — seven of them, `prompt`
    // included.
    //
    // THREE THINGS THE REBUILD MUST NOT GET WRONG, all of them silent:
    //
    //  1. `id` MUST be copied, not regenerated. The FTS5 indexes are
    //     EXTERNAL CONTENT keyed on `rowid`, which is `id`. Let SQLite
    //     assign fresh ids and every FTS row points at a different record —
    //     search keeps working and starts lying.
    //  2. The AFTER INSERT/UPDATE/DELETE triggers are dropped with their
    //     table and must be recreated verbatim. DROP TABLE does NOT fire
    //     DELETE triggers, which is what keeps the FTS content intact while
    //     the table is away.
    //  3. `legacy_alter_table` is ON across the renames. Modern SQLite
    //     "helpfully" rewrites references to a renamed table; here the
    //     children already reference the FINAL name and must be left alone.
    //
    // Foreign keys are disabled for the duration by GRDB's default
    // `.deferred` checks, which also runs `PRAGMA foreign_key_check` at the
    // end — so the CASCADE children cannot be collected when the old table
    // is dropped, and a broken reference still fails the migration.
    static func m0028_promptLifecycleCollapse(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0028_promptLifecycleCollapse") { db in
            let retiredStates = ["clarifying", "architecting", "implementing", "reviewing"]

            // Rebuilt tables and their row counts, captured before anything
            // moves. The m0012/m0027 precedent: a rebuild cannot lose rows, so
            // this is cheap insurance that makes "data preserved" a CHECKED
            // claim rather than a hoped-for one.
            let rebuilt = [
                "prompt",
                "exploration_summary", "clarification_summary", "architecture_summary",
                "review_summary", "care_package", "architecture_option",
            ]
            let before = try rebuilt.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }

            // (a) AND (b) ARE ONE PASS FOR `prompt`, not two, and the ordering
            // is the reason. `prompt.status` carries a CHECK naming all six old
            // states, so the remap and the constraint have to change together:
            // a bare UPDATE to 'initiated' would be rejected by the OLD check,
            // and installing the NEW check before the remap would be rejected by
            // the rows still holding old values. Mapping inside the rebuild's
            // INSERT ... SELECT sidesteps both — the new table never sees a
            // value its constraint forbids.
            //
            // `retiredStates` drives that CASE, so the list and the SQL cannot
            // drift.
            let remapList = retiredStates.map { "'\($0)'" }.joined(separator: ", ")
            let promptStatusExpr = "CASE WHEN status IN (\(remapList)) THEN 'initiated' ELSE status END"

            // (b) The schema half.
            //
            // Each entry is the table's CURRENT definition with the UNIQUE
            // removed, its explicit column list (never `SELECT *` — column
            // ORDER is the contract here), and the indexes and triggers that
            // die with the old table.
            struct Rebuild {
                let table: String
                let createSql: String
                /// Destination columns, in order. Never `SELECT *` — column
                /// ORDER is the contract between the two halves of the copy.
                let columns: String
                /// Source expressions, defaulting to `columns`. Overridden only
                /// where a value is transformed on the way across.
                let selectColumns: String
                let after: [String]

                init(
                    table: String, createSql: String, columns: String,
                    selectColumns: String? = nil, after: [String]
                ) {
                    self.table = table
                    self.createSql = createSql
                    self.columns = columns
                    self.selectColumns = selectColumns ?? columns
                    self.after = after
                }
            }

            let rebuilds: [Rebuild] = [
                // `prompt` FIRST: it is the table the retired states live in,
                // and its CHECK is what makes this a rebuild rather than an
                // UPDATE.
                Rebuild(
                    table: "prompt",
                    createSql: """
                        CREATE TABLE new_prompt (
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
                                CHECK (status IN ('draft', 'initiated', 'done')),
                            gmfs_relative_storage_path TEXT NOT NULL,
                            UNIQUE(session_uuid, code),
                            UNIQUE(session_uuid, seq)
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, session_uuid, seq, \
                        code, name, backstory, goal, detail, command, status, \
                        gmfs_relative_storage_path
                        """,
                    // Same list, with `status` mapped through the CASE. The two
                    // UNIQUE constraints are KEPT — only the status CHECK
                    // changes here.
                    selectColumns: """
                        id, uuid, version, created_at, updated_at, session_uuid, seq, \
                        code, name, backstory, goal, detail, command, \(promptStatusExpr), \
                        gmfs_relative_storage_path
                        """,
                    after: [
                        "CREATE INDEX idx_prompt_session_uuid ON prompt(session_uuid)",
                        """
                        CREATE TRIGGER prompt_ai AFTER INSERT ON prompt BEGIN
                            INSERT INTO prompt_fts(rowid, name, goal, detail, backstory)
                            VALUES (new.id, new.name, new.goal, new.detail, new.backstory);
                        END
                        """,
                        """
                        CREATE TRIGGER prompt_ad AFTER DELETE ON prompt BEGIN
                            INSERT INTO prompt_fts(prompt_fts, rowid, name, goal, detail, backstory)
                            VALUES ('delete', old.id, old.name, old.goal, old.detail, old.backstory);
                        END
                        """,
                        """
                        CREATE TRIGGER prompt_au AFTER UPDATE ON prompt BEGIN
                            INSERT INTO prompt_fts(prompt_fts, rowid, name, goal, detail, backstory)
                            VALUES ('delete', old.id, old.name, old.goal, old.detail, old.backstory);
                            INSERT INTO prompt_fts(rowid, name, goal, detail, backstory)
                            VALUES (new.id, new.name, new.goal, new.detail, new.backstory);
                        END
                        """,
                    ]
                ),
                Rebuild(
                    table: "exploration_summary",
                    createSql: """
                        CREATE TABLE new_exploration_summary (
                            \(baseColumns),
                            prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                            agent_type TEXT NOT NULL DEFAULT 'general',
                            agent_id TEXT,
                            status TEXT NOT NULL DEFAULT 'exploring',
                            overview TEXT NOT NULL DEFAULT ''
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, prompt_uuid, \
                        agent_type, agent_id, status, overview
                        """,
                    after: [
                        """
                        CREATE INDEX idx_exploration_summary_prompt_uuid
                            ON exploration_summary(prompt_uuid)
                        """,
                        """
                        CREATE TRIGGER exploration_summary_ai AFTER INSERT ON exploration_summary BEGIN
                            INSERT INTO exploration_summary_fts(rowid, overview)
                            VALUES (new.id, new.overview);
                        END
                        """,
                        """
                        CREATE TRIGGER exploration_summary_ad AFTER DELETE ON exploration_summary BEGIN
                            INSERT INTO exploration_summary_fts(exploration_summary_fts, rowid, overview)
                            VALUES ('delete', old.id, old.overview);
                        END
                        """,
                        """
                        CREATE TRIGGER exploration_summary_au AFTER UPDATE ON exploration_summary BEGIN
                            INSERT INTO exploration_summary_fts(exploration_summary_fts, rowid, overview)
                            VALUES ('delete', old.id, old.overview);
                            INSERT INTO exploration_summary_fts(rowid, overview)
                            VALUES (new.id, new.overview);
                        END
                        """,
                    ]
                ),
                Rebuild(
                    table: "clarification_summary",
                    createSql: """
                        CREATE TABLE new_clarification_summary (
                            \(baseColumns),
                            prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                            status TEXT NOT NULL DEFAULT 'building'
                        )
                        """,
                    columns: "id, uuid, version, created_at, updated_at, prompt_uuid, status",
                    after: [
                        """
                        CREATE INDEX idx_clarification_summary_prompt_uuid
                            ON clarification_summary(prompt_uuid)
                        """
                    ]
                ),
                Rebuild(
                    table: "architecture_summary",
                    createSql: """
                        CREATE TABLE new_architecture_summary (
                            \(baseColumns),
                            prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                            body TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL DEFAULT 'drafting'
                                CHECK (status IN ('drafting', 'proposed', 'approved')),
                            decision_rationale TEXT NOT NULL DEFAULT ''
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, prompt_uuid, \
                        body, status, decision_rationale
                        """,
                    after: [
                        """
                        CREATE INDEX idx_architecture_summary_prompt_uuid
                            ON architecture_summary(prompt_uuid)
                        """,
                        """
                        CREATE TRIGGER architecture_summary_ai AFTER INSERT ON architecture_summary BEGIN
                            INSERT INTO architecture_summary_fts(rowid, body)
                            VALUES (new.id, new.body);
                        END
                        """,
                        """
                        CREATE TRIGGER architecture_summary_ad AFTER DELETE ON architecture_summary BEGIN
                            INSERT INTO architecture_summary_fts(architecture_summary_fts, rowid, body)
                            VALUES ('delete', old.id, old.body);
                        END
                        """,
                        """
                        CREATE TRIGGER architecture_summary_au AFTER UPDATE ON architecture_summary BEGIN
                            INSERT INTO architecture_summary_fts(architecture_summary_fts, rowid, body)
                            VALUES ('delete', old.id, old.body);
                            INSERT INTO architecture_summary_fts(rowid, body)
                            VALUES (new.id, new.body);
                        END
                        """,
                    ]
                ),
                Rebuild(
                    table: "review_summary",
                    createSql: """
                        CREATE TABLE new_review_summary (
                            \(baseColumns),
                            prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                            status TEXT NOT NULL DEFAULT 'reviewing'
                                CHECK (status IN ('reviewing', 'complete')),
                            verdict TEXT
                                CHECK (verdict IN ('approved', 'approved_with_nits',
                                                   'changes_requested')),
                            overview TEXT NOT NULL DEFAULT '',
                            agent_id TEXT,
                            CHECK (status != 'complete' OR verdict IS NOT NULL)
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, prompt_uuid, \
                        status, verdict, overview, agent_id
                        """,
                    after: [
                        """
                        CREATE INDEX idx_review_summary_prompt_uuid
                            ON review_summary(prompt_uuid)
                        """,
                        """
                        CREATE TRIGGER review_summary_ai AFTER INSERT ON review_summary BEGIN
                            INSERT INTO review_summary_fts(rowid, overview)
                            VALUES (new.id, new.overview);
                        END
                        """,
                        """
                        CREATE TRIGGER review_summary_ad AFTER DELETE ON review_summary BEGIN
                            INSERT INTO review_summary_fts(review_summary_fts, rowid, overview)
                            VALUES ('delete', old.id, old.overview);
                        END
                        """,
                        """
                        CREATE TRIGGER review_summary_au AFTER UPDATE ON review_summary BEGIN
                            INSERT INTO review_summary_fts(review_summary_fts, rowid, overview)
                            VALUES ('delete', old.id, old.overview);
                            INSERT INTO review_summary_fts(rowid, overview)
                            VALUES (new.id, new.overview);
                        END
                        """,
                    ]
                ),
                Rebuild(
                    table: "care_package",
                    createSql: """
                        CREATE TABLE new_care_package (
                            \(baseColumns),
                            clarification_summary_uuid TEXT NOT NULL
                                REFERENCES clarification_summary(uuid) ON DELETE CASCADE,
                            clarified_intent TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL DEFAULT 'building',
                            dope_scope_uuid TEXT REFERENCES dope_scope(uuid) ON DELETE SET NULL,
                            dope_scope_revision INTEGER
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, \
                        clarification_summary_uuid, clarified_intent, status, \
                        dope_scope_uuid, dope_scope_revision
                        """,
                    after: [
                        // The dropped UNIQUE was also this FK's only index.
                        // Replace it with a plain one rather than leaving the
                        // lookup unindexed.
                        """
                        CREATE INDEX idx_care_package_clarification_fk
                            ON care_package(clarification_summary_uuid)
                        """
                    ]
                ),
                Rebuild(
                    table: "architecture_option",
                    createSql: """
                        CREATE TABLE new_architecture_option (
                            \(baseColumns),
                            architecture_summary_uuid TEXT NOT NULL
                                REFERENCES architecture_summary(uuid) ON DELETE CASCADE,
                            agent_name TEXT NOT NULL,
                            agent_id TEXT,
                            body TEXT NOT NULL,
                            status TEXT NOT NULL DEFAULT 'proposed'
                        )
                        """,
                    columns: """
                        id, uuid, version, created_at, updated_at, \
                        architecture_summary_uuid, agent_name, agent_id, body, status
                        """,
                    after: [
                        """
                        CREATE INDEX idx_architecture_option_summary_fk
                            ON architecture_option(architecture_summary_uuid)
                        """
                    ]
                ),
            ]

            try db.execute(sql: "PRAGMA legacy_alter_table = ON;")
            for rebuild in rebuilds {
                try db.execute(sql: rebuild.createSql)
                try db.execute(
                    sql: """
                        INSERT INTO new_\(rebuild.table) (\(rebuild.columns))
                        SELECT \(rebuild.selectColumns) FROM \(rebuild.table);
                        """)
                try db.execute(sql: "DROP TABLE \(rebuild.table);")
                try db.execute(
                    sql: "ALTER TABLE new_\(rebuild.table) RENAME TO \(rebuild.table);")
                for statement in rebuild.after {
                    try db.execute(sql: statement)
                }
            }
            try db.execute(sql: "PRAGMA legacy_alter_table = OFF;")

            let after = try rebuilt.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            guard before == after else {
                throw StoreError.corruptState(
                    entity: "prompt",
                    detail: "m0028 row-count mismatch: before \(before) after \(after)")
            }

            // The one check a row count cannot make. FTS is external content
            // keyed on rowid, so a rebuild that renumbered ids would preserve
            // every count and still leave the index pointing at the wrong rows.
            // Assert the id sets survived instead.
            for table in [
                "prompt", "exploration_summary", "architecture_summary", "review_summary",
            ] {
                let orphaned =
                    try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) FROM \(table) WHERE id IS NULL OR id <= 0
                            """) ?? -1
                guard orphaned == 0 else {
                    throw StoreError.corruptState(
                        entity: table,
                        detail: "m0028 lost rowid identity on \(orphaned) rows; FTS would be stale")
                }
            }

            // Any prompt left in a state this build cannot decode is a
            // corrupt row from here on — PromptRepository.setStatus throws
            // corruptState on an unknown status, so catch it here instead.
            let stranded =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM prompt
                         WHERE status NOT IN ('draft', 'initiated', 'done')
                        """) ?? -1
            guard stranded == 0 else {
                throw StoreError.corruptState(
                    entity: "prompt",
                    detail: "m0028 left \(stranded) prompt rows outside draft/initiated/done")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [28, Store.isoNow()]
            )
        }
    }
}
