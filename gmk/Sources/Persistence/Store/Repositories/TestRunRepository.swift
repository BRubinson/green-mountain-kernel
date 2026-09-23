import Foundation
import GRDB

/// TEST_* data access — the agent-scoped test mutex, run INSIDE a Store-owned transaction.
///
/// Mutex for AGENTS above the kernel's single-writer `flock`; serialises BUILD
/// and CHECKOUT. Liveness is DERIVED via `flock(LOCK_NB)` on the holder's own
/// `run.lock`: a SIGKILLed holder is provably gone. `expires_at` serves
/// `holder_kind == .lease` only, never the primary check (TTL fails toward
/// HOLDING). Reaping is LAZY inside the next `acquire`: a reaper timer would
/// hop threads inside a StoreBoundary.
struct TestRunRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Verbs

    /// Fetches the runnable test suites from a repository manifest file.
    ///
    /// The manifest is read from the checkout directory rather than the database
    /// to ensure it stays synchronized with the actual repository. A file travels
    /// with a cloned repository, whereas a database row would not. An absent
    /// manifest is not an error; the caller can determine whether that means no
    /// suites were declared or the lookup targeted the wrong directory.
    ///
    /// - Parameter req: The project UUID and target instance UUID for the lookup.
    /// - Returns: A response containing the list of suites and the manifest's file
    ///   path, or `nil` if no manifest was found.
    /// - Throws: `StoreError.notFound` when the project does not exist.
    func suiteList(_ req: TestSuiteListRequest) throws -> TestSuiteListResponse {
        guard
            let instance =
                try InstanceRecord
                .filter(InstanceRecord.Columns.projectUuid == req.projectUuid)
                .orderedByCreatedAt()
                .fetchOne(db)
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

    /// Reports the current state of the test lock for a project.
    ///
    /// This read-only operation writes nothing: neither the claim cell nor a
    /// reclaim is performed. A project that has never been locked has no row; the
    /// lock state is synthesized as open rather than persisted. A dead holder is
    /// reported as open without reclaiming it, since a read operation must not
    /// silently break another process's lock. Reclaiming is `acquire`'s job.
    ///
    /// - Parameter req: The project UUID for which to report the lock state.
    /// - Returns: The current lock response for the project.
    /// - Throws: `StoreError.notFound` when the project does not exist.
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

    /// Acquires the test lock for a project, creating a new test run.
    ///
    /// - Parameter req: The lock request containing the project UUID, target instance,
    ///   session details, and holder information.
    /// - Returns: The lock response with the newly acquired lock state and run details.
    /// - Throws: `StoreError.badRequest` when the test lock is held by another active
    ///   run.
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
            ],
            now: now
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

    /// Releases the test lock held by a specific run.
    ///
    /// - Parameter req: The release request containing the project UUID, run UUID,
    ///   final state, exit code, and force flag.
    /// - Returns: The lock response with the updated lock state.
    /// - Throws: `StoreError.badRequest` when the run does not hold the lock and
    ///   `force` is false.
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

    /// Marks a test run as started.
    ///
    /// - Parameter req: The start request containing the run UUID and expected
    ///   version.
    /// - Returns: The updated test run response.
    /// - Throws: `StoreError.versionConflict` when the expected version is stale.
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

    /// Fetches the status of a specific test run or all runs for a project.
    ///
    /// - Parameter req: The status request containing the run UUID or project UUID,
    ///   and optional result limit.
    /// - Returns: The test run response with the matching run details.
    /// - Throws: `StoreError.badRequest` when neither run UUID nor project UUID is
    ///   provided; `StoreError.notFound` when the specified run is not found.
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
        let rows =
            try TestRunRecord
            .filter(TestRunRecord.Columns.projectUuid == project)
            .order(TestRunRecord.Columns.createdAt.desc)
            .limit(min(max(req.limit ?? 20, 1), 200))
            .fetchAll(db)
        return TestRunResponse(runs: rows.map { $0.dto() })
    }

    // MARK: - Liveness

    /// Returns true when the holder of the lock is provably gone.
    ///
    /// For process holders, attempts to acquire the holder's own `run.lock` with
    /// `LOCK_NB`; success indicates the kernel released it and the process has
    /// died. The probe unlocks immediately and never becomes a holder. A missing
    /// lock file counts as gone because the run root is wiped on teardown;
    /// otherwise an orphaned lock would strand forever.
    ///
    /// - Parameter cell: The project test lock record to check.
    /// - Returns: `true` when the lock holder is provably gone; `false` otherwise.
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

    /// Returns true when a lease-mode lock has expired.
    ///
    /// If no expiry time is set, returns false to avoid silently breaking a live
    /// holder by inventing a deadline that was never specified.
    ///
    /// - Parameter cell: The project test lock record to check.
    /// - Returns: `true` when the lease has passed its expiration time; `false`
    ///   otherwise or when no expiry is set.
    private func leaseExpired(_ cell: ProjectTestLockRecord) -> Bool {
        guard let expires = cell.expiresAt,
            let deadline = StoreCore.parseIso(expires)
        else { return false }
        return deadline < Date()
    }

    // MARK: - Rows

    /// Verifies that a project exists.
    ///
    /// - Parameter projectUuid: The UUID of the project to verify.
    /// - Throws: `StoreError.notFound` when the project does not exist.
    private func requireProject(_ projectUuid: String) throws {
        guard try ProjectRecord.exists(db, key: ["uuid": projectUuid]) else {
            throw StoreError.notFound(entity: "project", key: projectUuid)
        }
    }

    /// Fetches the test lock cell for a project, creating an open one if needed.
    ///
    /// This method combines the fetch and open operations to avoid requiring a
    /// separate registration step. The cell is a property of the project, and
    /// making callers create it first would introduce an unnecessary failure path.
    ///
    /// - Parameter projectUuid: The UUID of the project.
    /// - Returns: The project test lock cell, newly created if it did not exist.
    /// - Throws: `StoreError.notFound` when the project does not exist.
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

    /// Fetches the test lock cell for a project, if it exists.
    ///
    /// - Parameter projectUuid: The UUID of the project.
    /// - Returns: The project test lock cell, or `nil` if none exists.
    /// - Throws: Any error from the database query.
    private func cell(projectUuid: String) throws -> ProjectTestLockRecord? {
        try ProjectTestLockRecord
            .filter(ProjectTestLockRecord.Columns.projectUuid == projectUuid)
            .fetchOne(db)
    }

    /// Fetches the test lock cell by UUID, requiring it to exist.
    ///
    /// - Parameter uuid: The UUID of the test lock cell.
    /// - Returns: The project test lock cell.
    /// - Throws: `StoreError.notFound` when the cell does not exist.
    private func requireCell(uuid: String) throws -> ProjectTestLockRecord {
        try ProjectTestLockRecord.require(db, uuid: uuid)
    }

    /// Fetches a test run by UUID as a summary.
    ///
    /// - Parameter uuid: The UUID of the test run to fetch, or `nil`.
    /// - Returns: The test run summary, or `nil` if the UUID is `nil` or the run
    ///   does not exist.
    /// - Throws: Any error from the database query.
    private func run(uuid: String?) throws -> TestRunSummary? {
        guard let uuid else { return nil }
        return try TestRunRecord.fetch(db, uuid: uuid)?.dto()
    }

    /// Marks a test run as abandoned.
    ///
    /// - Parameter runUuid: The UUID of the test run to abandon.
    /// - Throws: Any error from the database update.
    private func abandon(runUuid: String) throws {
        try finish(
            runUuid: runUuid,
            state: .abandoned,
            exitCode: nil,
            summary: "holder process exited without releasing the lock"
        )
    }

    /// Marks a test run with a terminal state.
    ///
    /// The current version is read from the database rather than taken from the
    /// caller, because the release path has already proven who holds the lock.
    /// Demanding a version the caller has no reason to be holding would turn a
    /// legitimate release into a version conflict it cannot fix.
    ///
    /// - Parameters:
    ///   - runUuid: The UUID of the test run.
    ///   - state: The terminal state to set on the run.
    ///   - exitCode: The process exit code, or `nil` if not applicable.
    ///   - summary: A summary message about the run's outcome, or `nil` for none.
    /// - Throws: `StoreError.notFound` when the test run does not exist.
    private func finish(
        runUuid: String,
        state: TestRunState,
        exitCode: Int32?,
        summary: String?
    ) throws {
        guard
            let current = try TestRunRecord.all().withUuid(runUuid)
                .select(TestRunRecord.Columns.version, as: Int64.self)
                .fetchOne(db)
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

    /// Constructs a test lock response from a cell record and optional run.
    ///
    /// - Parameters:
    ///   - cell: The project test lock cell to construct the response from.
    ///   - run: The associated test run summary, or `nil` if not available.
    ///   - overrideState: An override lock state to use instead of the cell's
    ///     state, or `nil` to use the cell's state.
    ///   - reclaimed: Whether the lock was reclaimed from a dead holder.
    /// - Returns: The lock response constructed from these components.
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
            version: cell.version,
            heldByRunUuid: state == .held ? cell.heldByRunUuid : nil,
            targetInstanceUuid: state == .held ? cell.targetInstanceUuid : nil,
            holderKind: TestHolderKind(rawValue: cell.holderKind),
            lockPath: cell.lockPath,
            holderPid: cell.holderPid.map { Int32($0) },
            claimedAt: cell.claimedAt,
            expiresAt: cell.expiresAt,
            run: run,
            reclaimed: reclaimed
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
