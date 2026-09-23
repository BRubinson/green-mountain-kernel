import Foundation
import GRDB

extension Migrations {
    // m0025 — Dynamic workflows train. PRECONDITION: a BACKUP. One train, not
    // five, so later slices build against final shapes. Rebuilds use the m0005
    // create-copy-drop-rename grammar, drop their pre-m0021 CHECKs (vocabulary
    // lives in Swift registries) and recreate every FTS mirror, because external
    // content binds rowid and DROP TABLE takes the triggers with it.
    // The data transformations below rewrite history deliberately: exploration
    // summaries become agent_type='synthesis', key files become findings, and
    // clarification text is preserved as a care_package row per summary.
    /// Registers the dynamic workflows migration.
    ///
    /// - Parameter migrator: The database migrator to register the migration with.
    static func m0025_dynamicWorkflows(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0025_dynamicWorkflows") { db in
            // ---- Stash rows whose source columns are about to drop.
            let briefingRefs = try Row.fetchAll(
                db,
                sql: """
                    SELECT uuid, dope_refs, kbite_refs FROM agent_briefing
                    """
            )
            let summaryText = try Row.fetchAll(
                db,
                sql: """
                    SELECT uuid, refined_goal, refined_detail, backstory_note
                    FROM clarification_summary
                    WHERE refined_goal != '' OR refined_detail != '' OR backstory_note != ''
                    """
            )
            let explorationCounts =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM exploration_summary
                        """
                ) ?? 0

            // ---- agent_briefing: retag pre_architecture as initial
            // (user: "migrate everything as explore ones"), initial wins
            // collisions.
            try db.execute(
                sql: """
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
                    """
            )

            // ---- agent_briefing rebuild: body/dope_refs/kbite_refs drop.
            try db.execute(
                sql: """
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
                    """
            )

            // Explode the stashed TEXT-JSON refs into child rows. Survivors
            // only — retagged deletions above already removed their parents.
            let now = Store.isoNow()
            let survivors = try Set(String.fetchAll(db, sql: "SELECT uuid FROM agent_briefing"))
            for row in briefingRefs {
                let briefingUuid: String = row["uuid"]
                guard survivors.contains(briefingUuid) else { continue }
                let decoder = JSONDecoder()
                if let dopeData = (row["dope_refs"] as String?)?.data(using: .utf8),
                    let codes = try? decoder.decode([String].self, from: dopeData)
                {
                    for (i, code) in codes.enumerated() {
                        try db.execute(
                            sql: """
                                INSERT INTO agent_briefing_dope_persistence
                                    (uuid, version, created_at, updated_at,
                                     agent_briefing_uuid, dope_code, brief, seq)
                                VALUES (?, 0, ?, ?, ?, ?, NULL, ?)
                                """,
                            arguments: [Store.newUuid(), now, now, briefingUuid, code, i]
                        )
                    }
                }
                struct KbiteRef: Decodable { let file_uuid: String; let brief: String? }
                if let kbiteData = (row["kbite_refs"] as String?)?.data(using: .utf8),
                    let refs = try? decoder.decode([KbiteRef].self, from: kbiteData)
                {
                    for (i, ref) in refs.enumerated() {
                        // Guard the FK: a ref to a since-deleted kbite file
                        // is dropped rather than failing the train.
                        let exists =
                            try Bool.fetchOne(
                                db,
                                sql: """
                                    SELECT EXISTS(SELECT 1 FROM kbite_resource_file WHERE uuid = ?)
                                    """,
                                arguments: [ref.file_uuid]
                            ) ?? false
                        guard exists else { continue }
                        try db.execute(
                            sql: """
                                INSERT INTO agent_briefing_dope_kbite
                                    (uuid, version, created_at, updated_at,
                                     agent_briefing_uuid, kbite_resource_file_uuid, brief, seq)
                                VALUES (?, 0, ?, ?, ?, ?, ?, ?)
                                """,
                            arguments: [
                                Store.newUuid(), now, now, briefingUuid,
                                ref.file_uuid, ref.brief, i,
                            ]
                        )
                    }
                }
            }

            // ---- exploration_summary rebuild: literal per-agent rows.
            try db.execute(
                sql: """
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
                    """
            )
            let migratedSummaries =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM exploration_summary"
                ) ?? 0
            guard migratedSummaries == explorationCounts else {
                throw DatabaseError(message: "m0025: exploration_summary parity failed")
            }

            // ---- exploration_finding rebuild: absorbs exploration_key_file.
            try db.execute(
                sql: """
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
                    """
            )

            // ---- care_package (created BEFORE the summary rebuild so the
            // seeds below can preserve the dropping text columns).
            try db.execute(
                sql: """
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
                    """
            )

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
                try db.execute(
                    sql: """
                        INSERT INTO care_package
                            (uuid, version, created_at, updated_at,
                             clarification_summary_uuid, clarified_intent, status)
                        VALUES (?, 0, ?, ?, ?, ?, 'ready')
                        """,
                    arguments: [
                        Store.newUuid(), now, now, summaryUuid,
                        parts.joined(separator: "\n\n"),
                    ]
                )
            }

            // ---- clarification_summary rebuild: the three text fields drop
            // (their mirror goes with them — nothing left to index).
            try db.execute(
                sql: """
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
                    """
            )

            // ---- clarification split: questions / options / answers / notes.
            try db.execute(
                sql: """
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
                    """
            )

            // ---- architecture options + delta/dope linkage columns.
            try db.execute(
                sql: """
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
                    """
            )

            // ---- file_change attribution axis + agent_id sweep.
            try db.execute(
                sql: """
                    ALTER TABLE file_change ADD COLUMN agent_id TEXT;
                    ALTER TABLE file_change ADD COLUMN agent_name TEXT;
                    ALTER TABLE file_change ADD COLUMN workflow_phase TEXT;
                    ALTER TABLE file_change ADD COLUMN origin TEXT NOT NULL DEFAULT 'hook';
                    ALTER TABLE review_summary ADD COLUMN agent_id TEXT;
                    ALTER TABLE review_finding ADD COLUMN agent_id TEXT;
                    """
            )

            // ---- bot_workflow: the daemon-held workflow state machine row.
            // Deliberately thin: phase is DERIVED from db evidence at every
            // BOT_NEXT — last_served_phase is observability only, so resume
            // is literally the first-run code path. task variant gets NO
            // row (its write-nothing contract).
            try db.execute(
                sql: """
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
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [25, Store.isoNow()]
            )
        }
    }
}
