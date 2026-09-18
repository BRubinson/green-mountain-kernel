import Foundation
import GRDB
import GmDaemonSdk

/// TEST_* data access — the agent-scoped test mutex, run INSIDE a Store-owned
/// transaction. It is a mutex for AGENTS above the kernel's own single-writer
/// `flock`, and what it serialises is the BUILD and the CHECKOUT.
/// Liveness is DERIVED, never asserted: the primary test is `flock(LOCK_NB)` on
/// the holder's own `run.lock`, so a SIGKILLed holder is provably gone.
/// `expires_at` serves `holder_kind == .lease` only and must never become the
/// primary check, since a TTL fails toward HOLDING. Reaping is LAZY, inside the
/// next `acquire`: a reaper timer would hop threads inside a StoreBoundary.
struct TestRunRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Verbs

    /// The runnable suites, read from a file in the CHECKOUT rather than from a
    /// table. A manifest in the db would be a second copy of what the checkout
    /// already states, and the two would disagree the moment the repo is cloned
    /// into another environment, which every beta and test refresh does. A file
    /// travels with the clone; a row does not.
    /// An absent manifest is NOT an error, and `manifestPath` comes back so a
    /// caller staring at an empty list can tell "none declared" from "looked in
    /// the wrong tree".
    func suiteList(_ req: TestSuiteListRequest) throws -> TestSuiteListResponse {
        guard
            let instance = try InstanceRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM instance WHERE project_uuid = ?
                     ORDER BY created_at ASC LIMIT 1
                    """,
                arguments: [req.projectUuid]
            )
        else {
            throw StoreError.notFound(entity: "instance", key: "project \(req.projectUuid)")
        }
        let repo = URL(fileURLWithPath: instance.absoluteFileSystemPath, isDirectory: true)
        // Repo root first, then this repo's own gmk/ layout. Checked in order
        // so a project can override without knowing anything about gmk.
        let candidates = [
            repo.appendingPathComponent("test-suites.json"),
            repo.appendingPathComponent("gmk/test-suites.json"),
        ]
        guard let manifest = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return TestSuiteListResponse(suites: [], manifestPath: nil)
        }
        let data = try Data(contentsOf: manifest)
        let decoded = try JSONDecoder().decode(TestSuiteManifest.self, from: data)
        return TestSuiteListResponse(suites: decoded.suites, manifestPath: manifest.path)
    }

    /// Report the lock. WRITES NOTHING — not the claim cell, not a reclaim.
    ///
    /// It does NOT fetch-or-OPEN the cell: a project nobody has locked has no
    /// row, and `open` is synthesised rather than persisted, because creating a
    /// row on read would need a write transaction inside a read-only verb.
    /// It REPORTS a dead holder as `open` without reclaiming it, since a read
    /// that silently broke somebody else's lock would make inspection
    /// destructive. Reclaiming is `acquire`'s job.
    func lockStatus(_ req: TestLockStatusRequest) throws -> TestLockResponse {
        try requireProject(req.projectUuid)
        guard let cell = try cell(projectUuid: req.projectUuid) else {
            // Never locked. Nothing to write, nothing to report but `open`.
            return TestLockResponse(
                projectUuid: req.projectUuid,
                state: .open,
                version: 0
            )
        }
        let stale = try isHolderGone(cell)
        if cell.state == TestLockState.held.rawValue, stale {
            return response(cell: cell, run: try run(uuid: cell.heldByRunUuid), overrideState: .open)
        }
        return response(cell: cell, run: try run(uuid: cell.heldByRunUuid))
    }

    func acquire(_ req: TestLockAcquireRequest) throws -> TestLockResponse {
        let cell = try fetchOrOpenCell(projectUuid: req.projectUuid)
        var reclaimed = false

        if cell.state == TestLockState.held.rawValue {
            guard try isHolderGone(cell) else {
                throw StoreError.badRequest(
                    detail: "test lock for project \(req.projectUuid) is held by run "
                        + "\(cell.heldByRunUuid ?? "?") (pid \(cell.holderPid.map(String.init) ?? "?")). "
                        + "TEST_LOCK_STATUS reports how to tell when it is done."
                )
            }
            // LAZY RECLAIM. The holder's process is gone — proven, not guessed,
            // because we took its flock. Mark its run abandoned rather than
            // failed: "we never found out" is not "it went red", and collapsing
            // them would let a crashed run masquerade as a real result.
            if let orphan = cell.heldByRunUuid {
                try abandon(runUuid: orphan)
            }
            reclaimed = true
        }

        let now = StoreCore.isoNow()
        let runUuid = try core.insertBase(
            db,
            table: "test_run",
            now: now,
            extra: [
                "project_uuid": req.projectUuid,
                "instance_uuid": req.targetInstanceUuid,
                "session_uuid": req.sessionUuid,
                "agent_id": req.agentId,
                "run_root": req.runRoot,
                "suite_id": req.suiteId,
                "git_sha": req.gitSha,
                "git_branch": req.gitBranch,
                "state": TestRunState.queued.rawValue,
                "done_kind": req.doneKind.rawValue,
                "done_condition": req.doneCondition,
                "done_hint": req.doneHint,
            ]
        )

        // holder_kind is derived from what the caller actually supplied rather
        // than from what it claimed: a lockPath means a real flock is available,
        // and absent one we degrade to a lease and say so in the row.
        let holderKind: TestHolderKind = req.lockPath == nil ? .lease : .process
        let expiresAt: String? =
            holderKind == .lease
            ? StoreCore.isoNow(offsetSeconds: req.leaseSeconds ?? 3600)
            : nil

        try core.updateBase(
            db,
            table: "project_test_lock",
            uuid: cell.uuid,
            expectedVersion: cell.version,
            set: [
                "state": TestLockState.held.rawValue,
                "held_by_run_uuid": runUuid,
                "target_instance_uuid": req.targetInstanceUuid,
                "holder_kind": holderKind.rawValue,
                "lock_path": req.lockPath,
                "holder_pid": req.holderPid.map { Int($0) },
                "claimed_at": now,
                "expires_at": expiresAt,
            ]
        )

        try core.appendEvent(
            db,
            kind: .testLockChange,
            subjectUuid: cell.uuid,
            payload: Store.jsonPayload([
                "action": reclaimed ? "reclaim" : "acquire",
                "project_uuid": req.projectUuid,
                "run_uuid": runUuid,
                "suite_id": req.suiteId,
            ])
        )

        let fresh = try requireCell(uuid: cell.uuid)
        return response(cell: fresh, run: try run(uuid: runUuid), reclaimed: reclaimed)
    }

    func release(_ req: TestLockReleaseRequest) throws -> TestLockResponse {
        let cell = try fetchOrOpenCell(projectUuid: req.projectUuid)

        // Releasing a lock you do not hold is the mistake worth refusing.
        // `force` exists because a human sometimes genuinely must break one —
        // and it EVENTS, so a forced release stays distinguishable from a clean
        // one afterwards rather than looking identical in the record.
        if !req.force, cell.heldByRunUuid != req.runUuid {
            throw StoreError.badRequest(
                detail: "run \(req.runUuid) does not hold the test lock for project "
                    + "\(req.projectUuid) (held by \(cell.heldByRunUuid ?? "nobody")). "
                    + "Pass force to break it deliberately."
            )
        }

        try finish(
            runUuid: req.runUuid,
            state: req.finalState,
            exitCode: req.exitCode,
            summary: req.summary
        )

        try core.updateBase(
            db,
            table: "project_test_lock",
            uuid: cell.uuid,
            expectedVersion: cell.version,
            set: [
                "state": TestLockState.open.rawValue,
                "held_by_run_uuid": nil,
                "target_instance_uuid": nil,
                "lock_path": nil,
                "holder_pid": nil,
                "claimed_at": nil,
                "expires_at": nil,
            ]
        )

        try core.appendEvent(
            db,
            kind: .testLockChange,
            subjectUuid: cell.uuid,
            payload: Store.jsonPayload([
                "action": req.force ? "force_release" : "release",
                "project_uuid": req.projectUuid,
                "run_uuid": req.runUuid,
                "final_state": req.finalState.rawValue,
            ])
        )

        let fresh = try requireCell(uuid: cell.uuid)
        return response(cell: fresh, run: try run(uuid: req.runUuid))
    }

    func runStart(_ req: TestRunStartRequest) throws -> TestRunResponse {
        try core.updateBase(
            db,
            table: "test_run",
            uuid: req.runUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "state": TestRunState.running.rawValue,
                "started_at": StoreCore.isoNow(),
            ]
        )
        guard let row = try run(uuid: req.runUuid) else {
            throw StoreError.notFound(entity: "test_run", key: req.runUuid)
        }
        return TestRunResponse(runs: [row])
    }

    func runStatus(_ req: TestRunStatusRequest) throws -> TestRunResponse {
        if let uuid = req.runUuid {
            guard let row = try run(uuid: uuid) else {
                throw StoreError.notFound(entity: "test_run", key: uuid)
            }
            return TestRunResponse(runs: [row])
        }
        guard let project = req.projectUuid else {
            throw StoreError.badRequest(detail: "TEST_RUN_STATUS needs run_uuid or project_uuid")
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM test_run WHERE project_uuid = ?
                 ORDER BY created_at DESC LIMIT ?
                """,
            arguments: [project, min(max(req.limit ?? 20, 1), 200)]
        )
        return TestRunResponse(runs: rows.map(summary(from:)))
    }

    // MARK: - Liveness

    /// THE DEADLOCK ANSWER. Returns true when the current holder is provably
    /// gone. For `.process` holders this takes the holder's own `run.lock` with
    /// `LOCK_NB`: success means the kernel already released it, which happens
    /// exactly when the holding process died, `kill -9` included. The probe
    /// unlocks and closes immediately so it never becomes a holder itself.
    /// A MISSING lock file counts as gone, because the run root is wiped on
    /// teardown; failing the other way would strand the lock forever on exactly
    /// the tidy path.
    private func isHolderGone(_ cell: ProjectTestLockRecord) -> Bool {
        guard cell.state == TestLockState.held.rawValue else { return true }
        guard cell.holderKind == TestHolderKind.process.rawValue,
            let path = cell.lockPath
        else {
            return leaseExpired(cell)
        }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(fd, LOCK_UN)
        return true
    }

    /// Lease mode only — the degraded path. Absent an expiry we report NOT
    /// expired, because inventing one would silently break a live holder.
    private func leaseExpired(_ cell: ProjectTestLockRecord) -> Bool {
        guard let expires = cell.expiresAt,
            let deadline = StoreCore.parseIso(expires)
        else { return false }
        return deadline < Date()
    }

    // MARK: - Rows

    /// Fetch the project's claim cell, opening an `open` one on first contact.
    /// Fetch-or-open rather than requiring a separate registration step: the
    /// cell is a property of the project, and making callers create it first
    /// would just be a second way to fail.
    /// An unknown project is NOT_FOUND rather than a silently-open lock. A typo
    /// in a uuid must not read as "go ahead, nobody is testing that".
    private func requireProject(_ projectUuid: String) throws {
        guard
            try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM project WHERE uuid = ?",
                arguments: [projectUuid]
            ) != nil
        else {
            throw StoreError.notFound(entity: "project", key: projectUuid)
        }
    }

    /// Fetch-or-open. Called ONLY from the write verbs — see `lockStatus` for
    /// why a read must never reach this.
    private func fetchOrOpenCell(projectUuid: String) throws -> ProjectTestLockRecord {
        try requireProject(projectUuid)
        if let existing = try cell(projectUuid: projectUuid) { return existing }
        let uuid = try core.insertBase(
            db,
            table: "project_test_lock",
            extra: [
                "project_uuid": projectUuid,
                "state": TestLockState.open.rawValue,
                "holder_kind": TestHolderKind.process.rawValue,
            ]
        )
        return try requireCell(uuid: uuid)
    }

    private func cell(projectUuid: String) throws -> ProjectTestLockRecord? {
        try ProjectTestLockRecord.fetchOne(
            db,
            sql: "SELECT * FROM project_test_lock WHERE project_uuid = ?",
            arguments: [projectUuid]
        )
    }

    private func requireCell(uuid: String) throws -> ProjectTestLockRecord {
        guard
            let row = try ProjectTestLockRecord.fetchOne(
                db,
                sql: "SELECT * FROM project_test_lock WHERE uuid = ?",
                arguments: [uuid]
            )
        else {
            throw StoreError.notFound(entity: "project_test_lock", key: uuid)
        }
        return row
    }

    private func run(uuid: String?) throws -> TestRunSummary? {
        guard let uuid else { return nil }
        guard
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM test_run WHERE uuid = ?",
                arguments: [uuid]
            )
        else { return nil }
        return summary(from: row)
    }

    private func abandon(runUuid: String) throws {
        try finish(
            runUuid: runUuid,
            state: .abandoned,
            exitCode: nil,
            summary: "holder process exited without releasing the lock"
        )
    }

    /// Stamp a terminal state. Reads the current version rather than taking one
    /// from the caller: the release path already proved who holds the lock, and
    /// demanding a second version the caller has no reason to be holding would
    /// turn a legitimate release into a VERSION_CONFLICT it cannot fix.
    private func finish(
        runUuid: String,
        state: TestRunState,
        exitCode: Int32?,
        summary: String?
    ) throws {
        guard
            let current = try Int64.fetchOne(
                db,
                sql: "SELECT version FROM test_run WHERE uuid = ?",
                arguments: [runUuid]
            )
        else {
            throw StoreError.notFound(entity: "test_run", key: runUuid)
        }
        try core.updateBase(
            db,
            table: "test_run",
            uuid: runUuid,
            expectedVersion: current,
            set: [
                "state": state.rawValue,
                "finished_at": StoreCore.isoNow(),
                "exit_code": exitCode.map { Int($0) },
                "summary": summary,
            ]
        )
    }

    // MARK: - Mapping

    private func response(
        cell: ProjectTestLockRecord,
        run: TestRunSummary?,
        overrideState: TestLockState? = nil,
        reclaimed: Bool = false
    ) -> TestLockResponse {
        let state =
            overrideState
            ?? TestLockState(rawValue: cell.state)
            ?? .open
        return TestLockResponse(
            projectUuid: cell.projectUuid,
            state: state,
            heldByRunUuid: state == .held ? cell.heldByRunUuid : nil,
            targetInstanceUuid: state == .held ? cell.targetInstanceUuid : nil,
            holderKind: TestHolderKind(rawValue: cell.holderKind),
            lockPath: cell.lockPath,
            holderPid: cell.holderPid.map { Int32($0) },
            claimedAt: cell.claimedAt,
            expiresAt: cell.expiresAt,
            version: cell.version,
            run: run,
            reclaimed: reclaimed
        )
    }

    private func summary(from row: Row) -> TestRunSummary {
        TestRunSummary(
            uuid: row["uuid"],
            projectUuid: row["project_uuid"],
            instanceUuid: row["instance_uuid"],
            sessionUuid: row["session_uuid"],
            agentId: row["agent_id"],
            runRoot: row["run_root"],
            suiteId: row["suite_id"],
            gitSha: row["git_sha"],
            gitBranch: row["git_branch"],
            // An unknown state on the wire is reported as abandoned rather than
            // crashing the read: the column carries no CHECK by design, so a
            // row written by newer bits must degrade rather than poison a list.
            state: TestRunState(rawValue: row["state"] ?? "") ?? .abandoned,
            doneKind: TestDoneKind(rawValue: row["done_kind"] ?? "") ?? .process,
            doneCondition: row["done_condition"] ?? "{}",
            doneHint: row["done_hint"],
            startedAt: row["started_at"],
            finishedAt: row["finished_at"],
            exitCode: (row["exit_code"] as Int?).map { Int32($0) },
            summary: row["summary"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            version: row["version"]
        )
    }
}

/// The on-disk shape of a repo's `test-suites.json`.
///
/// Decoded with a plain `JSONDecoder` and NO key strategy, so the file's keys
/// are exactly the wire keys (`doneKind`, `doneHint`) — a manifest a human
/// writes should match what the tool prints back, and a snake_case-only reader
/// would silently return an empty suite list for a hand-written camelCase file.
struct TestSuiteManifest: Decodable {
    let suites: [TestSuiteSpec]
}
