import Foundation
import GRDB

extension Migrations {
    // m0005 — purge the legacy concepts: three rebuilds plus a backfill, so no
    // row carries yeet_type, legacy_unstated, or a missing summary.
    // SQLite cannot alter a CHECK, so clarification, review_summary and
    // prompt_artifact rebuild. Registered with NO foreignKeyChecks: argument —
    // GRDB's default .deferred IS the SQLite 12-step, and with FK enforcement
    // live the review_summary drop would CASCADE every review_finding away. NO
    // PRAGMA in this body. Each rebuild copies `id` explicitly (the FTS5 mirrors
    // join on content_rowid) and recreates the triggers DROP TABLE removes.
    /// Registers migration m0005 to purge legacy concepts from the schema.
    ///
    /// Rebuilds tables to drop legacy enum values and performs a backfill of placeholder
    /// summaries for prompts that predate database-native clarifications and architectures.
    /// - Parameter migrator: The database migrator to register the migration with.
    static func m0005_purgeLegacyConcepts(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0005_purgeLegacyConcepts") { db in
            // Step 1 — data motion FIRST, so the narrowed CHECKs hold when the
            // rebuilt tables are populated.
            try db.execute(
                sql: """
                    UPDATE clarification SET category = 'detail'
                     WHERE category = 'yeet_type';

                    UPDATE review_summary SET verdict = 'approved'
                     WHERE verdict = 'legacy_unstated';
                    """
            )

            // Step 2 — clarification: drop yeet_type from the category CHECK.
            try db.execute(
                sql: """
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
                    """
            )

            // Step 3 — review_summary: drop legacy_unstated from the verdict
            // CHECK. review_finding CASCADE-references this table by uuid;
            // ordering is create-new / copy / drop-old / rename-new so the
            // only ALTER renames a table with zero referrers.
            try db.execute(
                sql: """
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
                    """
            )

            // Step 4 — prompt_artifact: drop the kind column. Every legal
            // value described a pre-migration report file except 'other',
            // which is the only value a current bot may write; a column with
            // one legal value carries no information. Rows keep file_path and
            // note. No FTS mirror on this table.
            try db.execute(
                sql: """
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
                    """
            )

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
                try db.execute(
                    sql: """
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
                        """
                )
            }

            // Step 6 — the backfill. Every prompt gets a clarification and an
            // architecture summary so SUMMARY_ABSENT can never again mean
            // "this one is legacy, go read a file". Placeholders land at
            // terminal status (complete / approved) so no lifecycle gate sees
            // a half-open summary, and carry ZERO child rows — a placeholder
            // asserts nothing it cannot back up. The body is a pointer to the
            // on-disk file, which stays the real record.
            let now = Store.isoNow()

            let missingClarification = try Row.fetchAll(
                db,
                sql: """
                    SELECT p.uuid AS prompt_uuid, p.ckfs_relative_storage_path AS storage_path
                      FROM prompt p
                     WHERE NOT EXISTS (
                         SELECT 1 FROM clarification_summary c WHERE c.prompt_uuid = p.uuid
                     )
                    """
            )
            for row in missingClarification {
                let promptUuid: String = row["prompt_uuid"]
                let storagePath: String = row["storage_path"]
                let pointer = """
                    m0005 placeholder. This prompt predates db-native \
                    clarifications; the real record, if any, is the file at \
                    \(storagePath)/memory/qualified.md
                    """
                try db.execute(
                    sql: """
                        INSERT INTO clarification_summary
                            (uuid, version, created_at, updated_at, prompt_uuid,
                             status, backstory_note, refined_goal, refined_detail)
                        VALUES (?, 0, ?, ?, ?, 'complete', ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString.lowercased(), now, now, promptUuid,
                        "Backfilled by m0005; not authored by a bot run.",
                        pointer, pointer,
                    ]
                )
            }

            let missingArchitecture = try Row.fetchAll(
                db,
                sql: """
                    SELECT p.uuid AS prompt_uuid, p.ckfs_relative_storage_path AS storage_path
                      FROM prompt p
                     WHERE NOT EXISTS (
                         SELECT 1 FROM architecture_summary a WHERE a.prompt_uuid = p.uuid
                     )
                    """
            )
            for row in missingArchitecture {
                let promptUuid: String = row["prompt_uuid"]
                let storagePath: String = row["storage_path"]
                let pointer = """
                    m0005 placeholder. This prompt predates db-native \
                    architectures; the real record, if any, is the file at \
                    \(storagePath)/memory/architecture.md
                    """
                try db.execute(
                    sql: """
                        INSERT INTO architecture_summary
                            (uuid, version, created_at, updated_at, prompt_uuid,
                             body, status)
                        VALUES (?, 0, ?, ?, ?, ?, 'approved')
                        """,
                    arguments: [
                        UUID().uuidString.lowercased(), now, now, promptUuid, pointer,
                    ]
                )
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [5, Store.isoNow()]
            )
        }
    }
}
