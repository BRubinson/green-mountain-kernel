import Foundation
import GRDB

extension Migrations {
    // m0029 — agent-scoped test mutual exclusion. Two pure CREATE TABLEs, both
    // starting empty, so no BACKUP precondition. TWO TABLES, and the split is
    // load-bearing: a single row holding the claim would make every re-lock
    // overwrite the record of the previous run. `test_run` is the append-only
    // ledger and `project_test_lock` is the one mutable claim cell pointing at it.
    // NO CHECKs on state / done_kind / holder_kind — vocabulary lives in Swift.
    // The inline UNIQUE on project_uuid IS the one-lock-per-project rule, chosen
    // knowing a later removal costs the m0028 rebuild dance.
    /// Creates test run and project test lock tables for mutual exclusion.
    /// - Parameter migrator: The database migrator.
    static func m0029_testRunLock(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0029_testRunLock") { db in
            // ---- test_run: APPEND-ONLY HISTORY. One row per run, forever.
            // agent_id joins agent_registration.agent_id but is deliberately NOT
            // a foreign key: that row may not have arrived yet, and a real FK
            // would make claiming fail on registration ORDERING rather than on
            // anything about the claim.
            // run_root holds the ephemeral root this run owns. HARD CONSTRAINT on
            // whatever generates it: sun_path is 104 bytes on macOS and the server
            // binds NWEndpoint.unix(path:), so run ids must be SHORT.
            try db.execute(
                sql: """
                    CREATE TABLE test_run (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                        instance_uuid TEXT REFERENCES instance(uuid) ON DELETE SET NULL,
                        session_uuid TEXT REFERENCES session(uuid) ON DELETE SET NULL,
                        agent_id TEXT,
                        run_root TEXT NOT NULL,
                        suite_id TEXT NOT NULL,
                        git_sha TEXT,
                        git_branch TEXT,
                        state TEXT NOT NULL,
                        done_kind TEXT NOT NULL,
                        done_condition TEXT NOT NULL,
                        done_hint TEXT,
                        started_at TEXT,
                        finished_at TEXT,
                        exit_code INTEGER,
                        summary TEXT
                    );
                    CREATE INDEX idx_test_run_project
                        ON test_run(project_uuid, created_at);
                    CREATE INDEX idx_test_run_state
                        ON test_run(state);
                    """
            )

            // ---- project_test_lock: the single mutable claim cell.
            // lock_path is the deadlock answer. Liveness is a flock(LOCK_NB)
            // probe on that file, not a TTL: authority is DERIVED from a won
            // lock as KernelOwnership derives it, so SIGKILLing the holder makes
            // the next status call report `open` with no timeout and no reaper.
            // expires_at serves holder_kind 'lease' only, and must never become
            // the primary liveness test: a TTL fails toward HOLDING a stuck lock,
            // the worst available direction for a mutex.
            try db.execute(
                sql: """
                    CREATE TABLE project_test_lock (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL UNIQUE REFERENCES project(uuid) ON DELETE CASCADE,
                        state TEXT NOT NULL DEFAULT 'open',
                        held_by_run_uuid TEXT REFERENCES test_run(uuid) ON DELETE SET NULL,
                        target_instance_uuid TEXT REFERENCES instance(uuid) ON DELETE SET NULL,
                        holder_kind TEXT NOT NULL DEFAULT 'process',
                        lock_path TEXT,
                        holder_pid INTEGER,
                        claimed_at TEXT,
                        expires_at TEXT
                    );
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [29, Store.isoNow()]
            )
        }
    }
}
