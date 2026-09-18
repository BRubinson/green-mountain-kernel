import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0029 — Agent-scoped test mutual exclusion.
    //
    // The cheapest class in the ledger: two pure CREATE TABLEs. No table
    // rebuild, no column rename, no FTS mirror, no trigger, no backfill,
    // and both tables start empty — so there is no row this migration can
    // lose. No BACKUP precondition for that reason.
    //
    // TWO TABLES, NOT ONE, and the split is load-bearing. The ask described
    // a single row holding the run id, the done-signal description and the
    // targeted instance. Written that way the lock cell IS the history, so
    // every re-lock overwrites the record of the previous run — a deletion
    // by another name, in a db whose whole contract is that it never loses
    // history. `test_run` is the append-only ledger; `project_test_lock` is
    // the one mutable claim cell, and it POINTS at the ledger row rather
    // than duplicating it, so the split costs nothing to read.
    //
    // NO CHECK CONSTRAINTS on state / done_kind / holder_kind. Post-m0021
    // the vocabulary lives in a Swift enum (TestRunState / TestDoneKind /
    // TestLockState), and m0025 removed the pre-m0021 CHECKs for exactly
    // this reason: an inline CHECK cannot be dropped without the documented
    // twelve-step table rebuild, so encoding a five-arm enum in SQL buys a
    // rebuild the first time a sixth arm is wanted.
    //
    // The inline UNIQUE on project_test_lock.project_uuid IS the one
    // rebuild-cost item here, and it is CHOSEN rather than inherited: it is
    // the "one entity per project" rule itself, expressed in the schema
    // where it cannot be forgotten. A lock table without uniqueness is not
    // a lock. SQLite backs it with a sqlite_autoindex_* that DROP INDEX
    // refuses, so removing it later means the m0028 rebuild dance — worth
    // it for the one constraint whose violation is the bug the table exists
    // to prevent.
    static func m0029_testRunLock(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0029_testRunLock") { db in
            // ---- test_run: APPEND-ONLY HISTORY. One row per run, forever.
            //
            // agent_id joins agent_registration.agent_id but is deliberately
            // NOT a foreign key: that row is written by a party which may not
            // have arrived yet (agent_registration's own header says so), and a
            // real FK would make claiming fail on registration ORDERING rather
            // than on anything about the claim.
            //
            // run_root holds the ephemeral root this run owns. HARD CONSTRAINT
            // on whatever generates it: sun_path is 104 bytes on macOS and the
            // server binds NWEndpoint.unix(path:), so a long root path yields a
            // listener that cannot bind. Run ids must be SHORT.
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
                    """)

            // ---- project_test_lock: the single mutable claim cell.
            //
            // lock_path is the deadlock answer. Liveness is a flock(LOCK_NB)
            // probe on that file, not a TTL: authority is DERIVED from a won
            // lock exactly as KernelOwnership derives it, so SIGKILLing the
            // holder makes the next status call report `open` with no timeout
            // and no reaper process. expires_at exists only for holder_kind
            // 'lease' — the degraded path for a holder that cannot keep an fd
            // open — and must never become the primary liveness test, because
            // a TTL fails toward HOLDING a stuck lock, which for a mutex is the
            // worst available direction.
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
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [29, Store.isoNow()]
            )
        }
    }
}
