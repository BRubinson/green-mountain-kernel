import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0002 is the first migration that cannot be fixed by wiping the db. The
/// fixture shape is derived from the SILENT failure mode, not the loud one:
/// a wrong rebuild body (FK pragma inside the transaction) aborts loudly on a
/// db that has a NO-ACTION referrer of prompt (file_change.prompt_uuid) but
/// CASCADE-deletes every prompt_artifact row and COMMITS on a db without one.
/// The fixture therefore must contain, at minimum: a prompt_artifact (CASCADE),
/// a prompt_active_kbite (CASCADE), and a file_change with non-null
/// prompt_uuid (NO ACTION) — and assert all three counts survive.
final class MigrationTests: XCTestCase {

    private func makeV1Fixture() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: "m0001_baseSchema")
        try queue.write { db in
            let now = "2026-08-01T00:00:00Z"
            func base(_ uuid: String, id: Int64? = nil) -> String {
                let idSql = id.map { String($0) } ?? "NULL"
                return "\(idSql), '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');

                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo', 'projects/repo/instances/repo_1');

                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');

                -- Three prompts across every legacy status; explicit ids 1..3
                -- so the uuid→id pairwise-identity assertion is meaningful.
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (1, 'prompt-a', 3, '\(now)', '\(now)', 'sess-1', 1, 'p1', 'one',
                        '', '', '', '', 'clarified', ''),
                       (2, 'prompt-b', 0, '\(now)', '\(now)', 'sess-1', 2, 'p2', 'two',
                        '', '', '', '', 'draft', ''),
                       (3, 'prompt-c', 1, '\(now)', '\(now)', 'sess-1', 3, 'p3', 'three',
                        '', '', '', '', 'clarifying', '');

                INSERT INTO prompt_artifact (id, uuid, version, created_at, updated_at,
                    prompt_uuid, file_path, kind, note)
                VALUES (\(base("art-1")), 'prompt-a', '/m/qualified.md', 'qualified', NULL),
                       (NULL, 'art-2', 0, '\(now)', '\(now)', 'prompt-a', '/m/architecture.md', 'architecture', NULL);

                INSERT INTO kbite (id, uuid, version, created_at, updated_at, code)
                VALUES (\(base("kb-1")), 'swift');

                INSERT INTO prompt_active_kbite (id, uuid, version, created_at, updated_at,
                    prompt_uuid, kbite_uuid)
                VALUES (\(base("pak-1")), 'prompt-a', 'kb-1');

                INSERT INTO session_file (id, uuid, version, created_at, updated_at,
                    session_uuid, relative_path, active)
                VALUES (\(base("sf-1")), 'sess-1', 'Sources/App.swift', 1);

                INSERT INTO file_change (id, uuid, version, created_at, updated_at,
                    session_file_uuid, session_uuid, prompt_uuid, change_kind)
                VALUES (\(base("fc-1")), 'sf-1', 'sess-1', 'prompt-a', 'edit');
                """)
        }
        return queue
    }

    func testM0002PreservesDataAndMapsStatuses() throws {
        let queue = try makeV1Fixture()
        let idsBefore = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT uuid, id FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["id"] as Int64) }
        }

        try Migrations.migrator.migrate(queue)

        try queue.read { db in
            // Row counts: the CASCADE children and the NO-ACTION referrer all survive.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_active_kbite"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_change"), 1)

            // Status mapping: clarified → done; draft/clarifying untouched.
            let statuses = try Row.fetchAll(db, sql: "SELECT uuid, status, version FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["status"] as String, $0["version"] as Int64) }
            XCTAssertEqual(statuses[0].0, "prompt-a"); XCTAssertEqual(statuses[0].1, "done")
            XCTAssertEqual(statuses[1].0, "prompt-b"); XCTAssertEqual(statuses[1].1, "draft")
            XCTAssertEqual(statuses[2].0, "prompt-c"); XCTAssertEqual(statuses[2].1, "clarifying")
            // Versions copied verbatim (rebuild is not a write).
            XCTAssertEqual(statuses[0].2, 3)

            // uuid→id PAIRS preserved (counts/sums are invariant under the
            // permutation an id-less copy produces — verified failure mode).
            let idsAfter = try Row.fetchAll(db, sql: "SELECT uuid, id FROM prompt ORDER BY uuid")
                .map { ($0["uuid"] as String, $0["id"] as Int64) }
            XCTAssertEqual(idsBefore.map { "\($0.0):\($0.1)" }, idsAfter.map { "\($0.0):\($0.1)" })

            // Child FK clauses still reference prompt, not a rebuild artifact.
            for child in ["prompt_artifact", "prompt_active_kbite", "file_change"] {
                let sql = try String.fetchOne(
                    db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [child]) ?? ""
                XCTAssertTrue(sql.contains("REFERENCES prompt(uuid)") || sql.contains("REFERENCES prompt (uuid)"),
                              "\(child) FK clause lost the prompt reference: \(sql)")
                XCTAssertFalse(sql.contains("prompt_new"), "\(child) references the rebuild table")
            }

            // Index + UNIQUEs regenerated.
            let indexNames = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'prompt'")
            XCTAssertTrue(indexNames.contains("idx_prompt_session_uuid"))
            let promptSql = try String.fetchOne(
                db, sql: "SELECT sql FROM sqlite_master WHERE name = 'prompt'") ?? ""
            XCTAssertTrue(promptSql.contains("UNIQUE(session_uuid, code)"))
            XCTAssertTrue(promptSql.contains("UNIQUE(session_uuid, seq)"))
            XCTAssertTrue(promptSql.contains("'architecting'"))

            // sqlite_sequence stays monotonic (max id was 3 before and after).
            let seqValue = try Int.fetchOne(
                db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'prompt'")
            XCTAssertEqual(seqValue, 3)

            // New tables exist and daemon_config is seeded.
            for table in ["clarification_summary", "user_clarification_question",
                          "internal_clarification_note", "architecture_summary",
                          "architecture_persistence_change", "architecture_persistence_field_change",
                          "architecture_general_change", "daemon_config"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [table]), 1, "missing table \(table)")
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daemon_config"), 4)

            // Ledger + FK health. The full migrator runs every registered
            // migration, so the ledger tracks currentSchemaVersion — and the
            // m0002 row itself must exist (it is the legacy epoch).
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 2"), 1)
            let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            XCTAssertTrue(violations.isEmpty, "foreign_key_check reported \(violations.count) violations")
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// Runs whatever migrations the copy still owes, against real accumulated
    /// data. Assertions are phrased so they hold whether the copy is pre-m0002
    /// or (as any copy of ~/gmcc/gmcc.db now is) already several migrations in:
    /// `clarified` maps INTO `done` rather than replacing it, so the expected
    /// count is the sum of both before-counts.
    func testAgainstLiveDbCopy() throws {
        // Point GMCC_TEST_LIVE_DB_COPY at a COPY of ~/gmcc/gmcc.db (never the
        // live file) to prove the migrations against real accumulated data.
        guard let path = ProcessInfo.processInfo.environment["GMCC_TEST_LIVE_DB_COPY"] else {
            throw XCTSkip("GMCC_TEST_LIVE_DB_COPY not set")
        }
        let store = try Store(path: path)
        let before: (prompts: Int, artifacts: Int, done: Int, clarified: Int,
                     clarifications: Int, reviewFindings: Int, uuidIds: [String]) =
            try store.dbQueue.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'done'") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'clarified'") ?? -1,
                 (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM user_clarification_question") ?? 0)
                     + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM internal_clarification_note") ?? 0),
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_finding") ?? 0,
                 try String.fetchAll(db, sql: "SELECT uuid || ':' || id FROM prompt ORDER BY uuid"))
            }

        try store.migrate()

        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt"), before.prompts)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact"), before.artifacts)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'done'"),
                before.done + before.clarified)
            // Rebuilds move values, never rows: the clarification population
            // (questions plus internal notes) and review_finding survive
            // intact, the latter through the CASCADE-parent review_summary
            // rebuild.
            XCTAssertEqual(
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM user_clarification_question") ?? 0)
                    + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM internal_clarification_note") ?? 0),
                before.clarifications)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_finding"), before.reviewFindings)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_summary WHERE verdict = 'legacy_unstated'"), 0)
            // The backfill leaves no PRE-EXISTING prompt without either
            // summary — scoped by the ledger's own applied_at, because a
            // prompt opened afterwards reaches `clarifying` long before it
            // has an architecture and must not be read as a backfill miss.
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM prompt p
                 WHERE p.status != 'draft'
                   AND p.created_at < (SELECT applied_at FROM schema_migrations WHERE version = 5)
                   AND NOT EXISTS
                    (SELECT 1 FROM clarification_summary c WHERE c.prompt_uuid = p.uuid)
                """), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM prompt p
                 WHERE p.status != 'draft'
                   AND p.created_at < (SELECT applied_at FROM schema_migrations WHERE version = 5)
                   AND NOT EXISTS
                    (SELECT 1 FROM architecture_summary a WHERE a.prompt_uuid = p.uuid)
                """), 0)
            // No draft prompt keeps an m0005 placeholder (m0006). The
            // placeholder text now sits in the care package m0025 seeded from
            // the summary's authored columns, so that is where it is hunted.
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM care_package cp
                  JOIN clarification_summary c ON c.uuid = cp.clarification_summary_uuid
                  JOIN prompt p ON p.uuid = c.prompt_uuid
                 WHERE p.status = 'draft'
                   AND cp.clarified_intent LIKE '%Backfilled by m0005%'
                """), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt WHERE status = 'clarified'"), 0)
            XCTAssertEqual(
                try String.fetchAll(db, sql: "SELECT uuid || ':' || id FROM prompt ORDER BY uuid"),
                before.uuidIds)
            // m0026 lands on a table with thousands of accumulated rows. It
            // ADDs columns, so every one of them must be present and NULL —
            // nothing outside a payload can know a tool_use_id, and a
            // backfill that invented one would be the misattribution this
            // axis exists to prevent.
            for column in ["claude_session_id", "claude_turn_id", "tool_use_id", "tool_name",
                           "agent_type", "permission_mode", "duration_ms", "transcript_path",
                           "agent_registration_uuid"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM pragma_table_info('file_change') WHERE name = ?
                        """, arguments: [column]), 1, "file_change lost \(column)")
            }
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM file_change WHERE tool_use_id IS NOT NULL
                    """), 0, "m0026 invented a tool_use_id for a pre-existing row")
            // The partial UNIQUE applied cleanly, which it only can if no two
            // accumulated rows already share a (tool call, file) pair.
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM sqlite_master
                     WHERE type = 'index' AND name = 'idx_file_change_tool_use'
                    """), 1)

            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// m0004 is pure ADD — no rebuild, no data motion. Assert the five report
    /// tables + their FTS mirrors/triggers exist, the CHECKs hold, and the
    /// `_ad` triggers keep the mirrors synced through an FK cascade delete
    /// (the recursive_triggers contract).
    func testM0004AddsReportTablesWithSyncedFtsMirrors() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0004-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let store = try Store(path: dbPath)
        try store.migrate()

        try store.dbQueue.write { db in
            // m0025 merged exploration_key_file into exploration_finding —
            // the table and its mirror must be GONE at head.
            for retired in ["exploration_key_file", "exploration_key_file_fts"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [retired]), 0, "retired table \(retired) survived m0025")
            }
            for table in ["exploration_summary", "exploration_finding",
                          "review_summary", "review_finding"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: [table]), 1, "missing table \(table)")
                XCTAssertEqual(
                    try Int.fetchOne(db, sql:
                        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                        arguments: ["\(table)_fts"]), 1, "missing FTS mirror for \(table)")
                for suffix in ["ai", "ad", "au"] {
                    XCTAssertEqual(
                        try Int.fetchOne(db, sql:
                            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?",
                            arguments: ["\(table)_\(suffix)"]), 1, "missing trigger \(table)_\(suffix)")
                }
            }
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                Migrations.currentSchemaVersion)

            // Minimal chain + one summary + one finding.
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'r', 'r', 'r', 'p/r');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'r_1', 'r_1', '/tmp/r', 'p/r/i');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active', 'p/r/i/s');
                INSERT INTO prompt (uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES ('prompt-x', 0, '\(now)', '\(now)', 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                INSERT INTO exploration_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, status, overview)
                VALUES ('exs-1', 0, '\(now)', '\(now)', 'prompt-x', 'exploring', '');
                INSERT INTO exploration_finding (uuid, version, created_at, updated_at,
                    exploration_summary_uuid, kind, title, body, agent_name, finding_rating)
                VALUES ('exf-1', 0, '\(now)', '\(now)', 'exs-1', 'other', 'searchable finding title',
                        'searchable finding body', 'tester', NULL);
                """)

            // m0025 dropped the pre-m0021 CHECKs from the rebuilt tables:
            // rating validity lives in Swift (Store.validateRating), so the
            // raw insert is ACCEPTED at the SQL layer now.
            try db.execute(sql: """
                INSERT INTO exploration_finding (uuid, version, created_at, updated_at,
                    exploration_summary_uuid, kind, title, body, agent_name, finding_rating)
                VALUES ('exf-checkless', 0, '\(now)', '\(now)', 'exs-1', 'other', 't', 'b', 'a', 1000)
                """)
            try db.execute(sql: "DELETE FROM exploration_finding WHERE uuid = 'exf-checkless'")
            // review_summary: complete requires a verdict.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO review_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, status, verdict, overview)
                VALUES ('rvs-bad', 0, '\(now)', '\(now)', 'prompt-x', 'complete', NULL, '')
                """))

            // FTS mirror is live…
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM exploration_finding_fts WHERE exploration_finding_fts MATCH 'searchable'"), 1)
            // …and stays synced through the prompt-delete FK cascade.
            try db.execute(sql: "DELETE FROM prompt WHERE uuid = 'prompt-x'")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exploration_summary"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exploration_finding"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM exploration_finding_fts WHERE exploration_finding_fts MATCH 'searchable'"), 0)

            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// m0005 is three table rebuilds plus a backfill against accumulated
    /// data — the riskiest migration since m0002. The fixture is built at
    /// m0004 (the last schema that still accepts the retired values), seeded
    /// with every row shape m0005 must move, then migrated the rest of the
    /// way.
    func testM0005PurgesLegacyValuesAndBackfillsPlaceholders() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0005-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let queue = try DatabaseQueue(path: dbPath)
        try Migrations.migrator.migrate(queue, upTo: "m0004_explorationReviewReports")

        let now = "2026-08-01T00:00:00Z"
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'r', 'r', 'r', 'projects/r');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'r_1', 'r_1', '/tmp/r', 'projects/r/instances/r_1');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/r/instances/r_1/sessions/main');

                -- p1 carries db-native rows; p2 is the pre-m0002 shape with none.
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (1, 'prompt-1', 0, '\(now)', '\(now)', 'sess-1', 1, 'p1', 'one', '', '', '', '', 'done',
                        'projects/r/instances/r_1/sessions/main/prompts/1_one'),
                       (2, 'prompt-2', 0, '\(now)', '\(now)', 'sess-1', 2, 'p2', 'two', '', '', '', '', 'done',
                        'projects/r/instances/r_1/sessions/main/prompts/2_two'),
                       -- p3 is still draft: m0005 backfills it, m0006 takes it
                       -- back off again (a draft must be able to author its own
                       -- clarification, which a terminal placeholder blocks).
                       (3, 'prompt-3', 0, '\(now)', '\(now)', 'sess-1', 3, 'p3', 'three', '', '', '', '', 'draft',
                        'projects/r/instances/r_1/sessions/main/prompts/3_three');

                INSERT INTO clarification_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, status, backstory_note, refined_goal, refined_detail)
                VALUES ('cls-1', 0, '\(now)', '\(now)', 'prompt-1', 'complete', '', 'g', 'd');

                -- One row per retired + surviving category; ids pinned so the
                -- rowid-stability assertion is meaningful.
                INSERT INTO clarification (id, uuid, version, created_at, updated_at,
                    clarification_summary_uuid, seq, category, question, answer, answer_source, status)
                VALUES (10, 'clr-goal', 0, '\(now)', '\(now)', 'cls-1', 1, 'goal', 'q goal', 'a', 'user', 'answered'),
                       (11, 'clr-yeet', 2, '\(now)', '\(now)', 'cls-1', 2, 'yeet_type', 'searchable q yeet',
                        'a', 'bot_inferred', 'answered'),
                       (12, 'clr-det', 0, '\(now)', '\(now)', 'cls-1', 3, 'detail', 'q detail', NULL, NULL, 'open');

                INSERT INTO architecture_summary (uuid, version, created_at, updated_at,
                    prompt_uuid, body, status)
                VALUES ('ars-1', 0, '\(now)', '\(now)', 'prompt-1', 'b', 'approved');

                -- Every retired artifact kind plus the surviving one.
                INSERT INTO prompt_artifact (uuid, version, created_at, updated_at,
                    prompt_uuid, file_path, kind, note)
                VALUES ('art-1', 0, '\(now)', '\(now)', 'prompt-1', 'm/qualified.md', 'qualified', 'n1'),
                       ('art-2', 0, '\(now)', '\(now)', 'prompt-1', 'm/architecture.md', 'architecture', NULL),
                       ('art-3', 0, '\(now)', '\(now)', 'prompt-1', 'm/explore.md', 'explore', NULL),
                       ('art-4', 0, '\(now)', '\(now)', 'prompt-1', 'm/review.md', 'review', NULL),
                       ('art-5', 0, '\(now)', '\(now)', 'prompt-1', 'm/notes.md', 'other', 'n5');

                -- legacy_unstated + a survivor; review_finding CASCADE-children
                -- of the summary being rebuilt.
                INSERT INTO review_summary (id, uuid, version, created_at, updated_at,
                    prompt_uuid, status, verdict, overview)
                VALUES (20, 'rvs-1', 3, '\(now)', '\(now)', 'prompt-1', 'complete', 'legacy_unstated',
                        'searchable overview one'),
                       (21, 'rvs-2', 0, '\(now)', '\(now)', 'prompt-2', 'complete', 'changes_requested',
                        'searchable overview two');

                INSERT INTO review_finding (uuid, version, created_at, updated_at,
                    review_summary_uuid, kind, title, body, agent_name, finding_rating)
                VALUES ('rvf-1', 0, '\(now)', '\(now)', 'rvs-1', 'other', 't1', 'b1', 'a', 5),
                       ('rvf-2', 0, '\(now)', '\(now)', 'rvs-1', 'other', 't2', 'b2', 'a', 500);
                """)
        }

        try Migrations.migrator.migrate(queue)

        try queue.write { db in
            // m0025 split the clarification table: user/unanswered rows are
            // questions, bot_inferred rows are internal notes, uuids kept.
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM user_clarification_question"), 2)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM internal_clarification_note"), 1)
            XCTAssertEqual(try String.fetchOne(
                db, sql: "SELECT answer_text FROM user_clarification_question WHERE uuid = 'clr-goal'"), "a")
            let noteBody = try String.fetchOne(
                db, sql: "SELECT body FROM internal_clarification_note WHERE uuid = 'clr-yeet'") ?? ""
            XCTAssertTrue(noteBody.contains("searchable q yeet"), noteBody)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM review_summary WHERE verdict = 'legacy_unstated'"), 0)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM review_summary WHERE verdict = 'approved'"), 1)

            // review_summary kept its m0005-era CHECK (m0025 only ADDed a
            // column there — additive ALTERs never relax constraints).
            XCTAssertThrowsError(try db.execute(sql: """
                UPDATE review_summary SET verdict = 'legacy_unstated' WHERE uuid = 'rvs-2'
                """), "verdict CHECK still accepts legacy_unstated")

            // prompt_artifact kept every row and lost the column.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_artifact"), 5)
            XCTAssertEqual(try String.fetchOne(
                db, sql: "SELECT note FROM prompt_artifact WHERE uuid = 'art-1'"), "n1")
            let artifactSql = try String.fetchOne(
                db, sql: "SELECT sql FROM sqlite_master WHERE name = 'prompt_artifact'") ?? ""
            XCTAssertFalse(artifactSql.contains("kind"), "kind column survived the rebuild")
            XCTAssertTrue(artifactSql.contains("UNIQUE(prompt_uuid, file_path)"))

            // review_finding CASCADE-children survived the review_summary drop.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_finding"), 2)

            // Versions copied verbatim through the m0025 split (uuids are the
            // stable identity across the reshape); review_summary untouched.
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT version FROM internal_clarification_note WHERE uuid = 'clr-yeet'"), 2)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT id FROM review_summary WHERE uuid = 'rvs-1'"), 20)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT version FROM review_summary WHERE uuid = 'rvs-1'"), 3)

            // The m0025 mirrors index the migrated text.
            for table in ["user_clarification_question", "internal_clarification_note", "review_summary"] {
                for suffix in ["ai", "ad", "au"] {
                    XCTAssertEqual(try Int.fetchOne(
                        db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?",
                        arguments: ["\(table)_\(suffix)"]), 1, "missing trigger \(table)_\(suffix)")
                }
            }
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM internal_clarification_note_fts WHERE internal_clarification_note_fts MATCH 'searchable'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM review_summary_fts WHERE review_summary_fts MATCH 'searchable'"), 2)

            // The backfill: every prompt PAST DRAFT now has both summaries,
            // so SUMMARY_ABSENT can never again mean "this one is legacy".
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM prompt p WHERE p.status != 'draft' AND NOT EXISTS
                    (SELECT 1 FROM clarification_summary c WHERE c.prompt_uuid = p.uuid)
                """), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM prompt p WHERE p.status != 'draft' AND NOT EXISTS
                    (SELECT 1 FROM architecture_summary a WHERE a.prompt_uuid = p.uuid)
                """), 0)
            // …and m0006 took the draft prompt's placeholders back off, so it
            // can still open a `building` summary and author its own rows.
            XCTAssertNil(try String.fetchOne(
                db, sql: "SELECT uuid FROM clarification_summary WHERE prompt_uuid = 'prompt-3'"))
            XCTAssertNil(try String.fetchOne(
                db, sql: "SELECT uuid FROM architecture_summary WHERE prompt_uuid = 'prompt-3'"))
            // m0025 dropped refined_goal/refined_detail — but preserved the
            // authored text by seeding a care_package per summary that
            // carried any (append-only-history spirit: nothing authored is
            // destroyed).
            let intent1 = try String.fetchOne(db, sql: """
                SELECT cp.clarified_intent FROM care_package cp
                  JOIN clarification_summary s ON s.uuid = cp.clarification_summary_uuid
                 WHERE s.prompt_uuid = 'prompt-1'
                """) ?? ""
            XCTAssertTrue(intent1.contains("g"), intent1)
            XCTAssertTrue(intent1.contains("d"), intent1)
            // …and the placeholder text points at the on-disk file, preserved
            // into prompt-2's seeded care package; the summary stays terminal.
            let placeholder = try String.fetchOne(db, sql: """
                SELECT cp.clarified_intent FROM care_package cp
                  JOIN clarification_summary s ON s.uuid = cp.clarification_summary_uuid
                 WHERE s.prompt_uuid = 'prompt-2'
                """) ?? ""
            XCTAssertTrue(placeholder.contains("2_two/memory/qualified.md"), placeholder)
            XCTAssertEqual(try String.fetchOne(
                db, sql: "SELECT status FROM clarification_summary WHERE prompt_uuid = 'prompt-2'"), "complete")
            XCTAssertEqual(try String.fetchOne(
                db, sql: "SELECT status FROM architecture_summary WHERE prompt_uuid = 'prompt-2'"), "approved")
            // A placeholder asserts nothing it cannot back up: no child rows.
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM user_clarification_question c
                  JOIN clarification_summary s ON s.uuid = c.clarification_summary_uuid
                 WHERE s.prompt_uuid = 'prompt-2'
                """), 0)

            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                           Migrations.currentSchemaVersion)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// m0026 is pure ADD, so the interesting assertions are not "did the
    /// table appear" but "do the three indexes actually decide what they were
    /// designed to decide". Each one has a silent failure mode: a missing
    /// UNIQUE on claude_session_id lets a conversation re-pin to a second
    /// session and attribution starts drifting mid-run; a wider key than
    /// agent_id alone puts the spawner's authority write out of reach of its
    /// only identifier; and a BARE UNIQUE(tool_use_id) would silently make
    /// one `sed -i a b c` unrecordable past its first file.
    func testM0026AttributionKeysDecideWhatTheyAreFor() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0026-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let store = try Store(path: dbPath)
        try store.migrate()

        let now = Store.isoNow()
        try store.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'r', 'r', 'r', 'p/r');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'r_1', 'r_1', '/tmp/r', 'p/r/i');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-main', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active', 'p/r/i/s'),
                       ('sess-other', 0, '\(now)', '\(now)', 'inst-1', 'other', 'other', '', '', 'active', 'p/r/i/s2');
                INSERT INTO prompt (uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES ('prompt-x', 0, '\(now)', '\(now)', 'sess-main', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                INSERT INTO session_file (uuid, version, created_at, updated_at,
                    session_uuid, relative_path, active)
                VALUES ('sf-a', 0, '\(now)', '\(now)', 'sess-main', 'Sources/A.swift', 1),
                       ('sf-b', 0, '\(now)', '\(now)', 'sess-main', 'Sources/B.swift', 1);
                """)
        }

        try store.dbQueue.write { db in
            // ---- The pin holds once, and a re-run bounces off the index
            // rather than off a branch in Swift.
            try db.execute(sql: """
                INSERT INTO claude_session_binding (uuid, version, created_at, updated_at,
                    claude_session_id, session_uuid)
                VALUES ('csb-1', 0, '\(now)', '\(now)', 'claude-abc', 'sess-main')
                """)
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO claude_session_binding (uuid, version, created_at, updated_at,
                    claude_session_id, session_uuid)
                VALUES ('csb-2', 0, '\(now)', '\(now)', 'claude-abc', 'sess-other')
                """), "a second pin for one conversation was accepted")
            try db.execute(sql: """
                INSERT OR IGNORE INTO claude_session_binding (uuid, version, created_at, updated_at,
                    claude_session_id, session_uuid)
                VALUES ('csb-3', 0, '\(now)', '\(now)', 'claude-abc', 'sess-other')
                """)
            XCTAssertEqual(
                try String.fetchOne(db, sql: """
                    SELECT session_uuid FROM claude_session_binding WHERE claude_session_id = 'claude-abc'
                    """), "sess-main", "the pin moved")

            // ---- agent_id ALONE: a differing conversation does not buy a
            // second row for the same agent.
            try db.execute(sql: """
                INSERT INTO agent_registration (uuid, version, created_at, updated_at,
                    agent_id, claude_session_id, claude_turn_id, session_uuid, prompt_uuid,
                    agent_type, role, methodology, workflow_phase)
                VALUES ('areg-1', 0, '\(now)', '\(now)', 'a1f2', 'claude-abc', 'turn-1',
                        'sess-main', 'prompt-x', 'gmcc:code-explorer', NULL, NULL, NULL)
                """)
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO agent_registration (uuid, version, created_at, updated_at,
                    agent_id, claude_session_id)
                VALUES ('areg-dup', 0, '\(now)', '\(now)', 'a1f2', 'claude-zzz')
                """), "UNIQUE(agent_id) is not on agent_id alone")
            // The authority half merges into the identity row, late.
            try db.execute(sql: """
                UPDATE agent_registration
                   SET role = 'explorer', methodology = 'data_flow', workflow_phase = 'exploring'
                 WHERE agent_id = 'a1f2'
                """)
            // Four same-typed personas coexist — the case agent_briefing's
            // (prompt_uuid, step) key cannot hold.
            for i in 0..<4 {
                try db.execute(sql: """
                    INSERT INTO agent_registration (uuid, version, created_at, updated_at,
                        agent_id, prompt_uuid, agent_type, methodology)
                    VALUES ('areg-p\(i)', 0, '\(now)', '\(now)', 'a-explorer-\(i)', 'prompt-x',
                            'gmcc:code-explorer', 'm\(i)')
                    """)
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM agent_registration
                 WHERE prompt_uuid = 'prompt-x' AND agent_type = 'gmcc:code-explorer'
                """), 5)

            // ---- (tool call, file) is the unit: one Bash tool_use_id across
            // two files is two legal rows; the same pair twice is not.
            func insertChange(_ uuid: String, file: String, toolUse: String?, reg: String?) throws {
                try db.execute(sql: """
                    INSERT INTO file_change (uuid, version, created_at, updated_at,
                        session_file_uuid, session_uuid, prompt_uuid, change_kind,
                        origin, claude_session_id, claude_turn_id, tool_use_id, tool_name,
                        agent_id, agent_type, permission_mode, duration_ms, transcript_path,
                        agent_registration_uuid)
                    VALUES (?, 0, ?, ?, ?, 'sess-main', 'prompt-x', 'edit',
                            'command', 'claude-abc', 'turn-1', ?, 'Bash',
                            'a1f2', 'gmcc:code-explorer', 'acceptEdits', 120, '/t/x.jsonl', ?)
                    """, arguments: [uuid, now, now, file, toolUse, reg])
            }
            try insertChange("fc-1", file: "sf-a", toolUse: "toolu_bash", reg: "areg-1")
            try insertChange("fc-2", file: "sf-b", toolUse: "toolu_bash", reg: "areg-1")
            XCTAssertThrowsError(
                try insertChange("fc-3", file: "sf-a", toolUse: "toolu_bash", reg: "areg-1"),
                "a replay of one (tool call, file) was accepted twice")

            // The index is partial: manual rows carry no tool call and must
            // not collide with each other.
            try insertChange("fc-4", file: "sf-a", toolUse: nil, reg: nil)
            try insertChange("fc-5", file: "sf-a", toolUse: nil, reg: nil)

            // ---- The registration FK is real, and NULL is legal because the
            // primary has no agent_id to point at.
            XCTAssertThrowsError(
                try insertChange("fc-bad", file: "sf-b", toolUse: "toolu_x", reg: "areg-missing"),
                "agent_registration_uuid accepted a dangling uuid")
            try insertChange("fc-primary", file: "sf-b", toolUse: "toolu_primary", reg: nil)

            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"),
                           Migrations.currentSchemaVersion)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }

        // Every index the attribution path reads through exists under the
        // name the repositories will query by.
        try store.dbQueue.read { db in
            let indexes = try Set(String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            for index in ["idx_claude_session_binding_claude_session_id",
                          "idx_claude_session_binding_session_fk",
                          "idx_agent_registration_agent_id",
                          "idx_agent_registration_prompt_fk",
                          "idx_file_change_tool_use",
                          "idx_file_change_claude_session_id",
                          "idx_file_change_agent_id",
                          "idx_file_change_agent_registration_fk"] {
                XCTAssertTrue(indexes.contains(index), "missing index \(index)")
            }
            // change_kind keeps its CHECK: m0026 ADDs columns and never
            // rebuilds this table, so the one constraint it has survives.
            let fileChangeSql = try String.fetchOne(
                db, sql: "SELECT sql FROM sqlite_master WHERE name = 'file_change'") ?? ""
            XCTAssertTrue(fileChangeSql.contains("CHECK (change_kind IN"), fileChangeSql)
        }
    }
}
