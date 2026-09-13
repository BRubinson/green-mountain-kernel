import Foundation
import GRDB
import GmDaemonSdk
import XCTest

/// The agent test mutex (m0029), driven entirely over the wire.
///
/// Every case here writes through `TEST_LOCK_*` and reads back with read-only
/// SQL — no `Store`, no `@testable`. That is not ceremony: the lock exists to
/// keep two agents off one repository, and an agent reaches it over exactly this
/// socket, so testing it any other way would test something else.
///
/// Cases are ORDER-INDEPENDENT BY UNIQUENESS, which is the rule this whole
/// package runs on: each mints its own project rather than relying on a clean
/// database, because the database is shared and append-only and will not be
/// clean.
final class TestLockTests: KernelBackedTestCase {

    /// Mint a project + instance to hang a lock off, named uniquely so cases
    /// cannot collide no matter what order they run in.
    private func makeProject(_ label: String) throws -> (project: String, instance: String) {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let code = "t_\(label)_\(id)"
        let repo = env.root.appendingPathComponent("repos/\(code)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let response = try env.send(
            .contextEnsure,
            ContextEnsureRequest(
                project: ProjectContext(
                    gitRepoName: code, code: code, name: code,
                    gmfsRelativeStoragePath: "projects/\(code)"),
                instance: InstanceContext(
                    code: "\(code)_1", name: code,
                    absoluteFileSystemPath: repo.path,
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1"),
                session: SessionContext(
                    code: "main", name: "main", backstory: "", goal: "",
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main")),
            ContextEnsureResponse.self)
        return (response.projectUuid, response.instanceUuid)
    }

    /// A lock file a live holder would be holding. Returns the open descriptor —
    /// the caller closes it to simulate the holder dying.
    private func heldLockFile(_ name: String) throws -> (path: String, fd: Int32) {
        let path = env.root.appendingPathComponent("\(name).lock", isDirectory: false).path
        FileManager.default.createFile(atPath: path, contents: nil)
        let fd = open(path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        return (path, fd)
    }

    private func acquire(
        project: String, instance: String? = nil, lockPath: String?, suite: String = "kernel"
    ) throws -> TestLockResponse {
        try env.send(
            .testLockAcquire,
            TestLockAcquireRequest(
                projectUuid: project,
                targetInstanceUuid: instance,
                suiteId: suite,
                runRoot: env.root.path,
                lockPath: lockPath,
                holderPid: getpid(),
                doneKind: .process,
                doneCondition: #"{"kind":"process"}"#,
                doneHint: "exits non-zero on failure"),
            TestLockResponse.self)
    }

    // MARK: - Cases

    /// A project starts unlocked, and asking does not create work.
    func testAProjectStartsOpen() throws {
        let (project, _) = try makeProject("open")
        let status = try env.send(
            .testLockStatus, TestLockStatusRequest(projectUuid: project), TestLockResponse.self)
        XCTAssertEqual(status.state, .open)
        XCTAssertNil(status.heldByRunUuid)
    }

    /// Claiming records the run AND the hint another agent reads.
    ///
    /// `doneHint` is the ask's "a description of how to tell when the test is
    /// done running", and it comes back inlined on the lock response so a
    /// waiting agent learns whether it can proceed in ONE round trip.
    func testAcquireRecordsTheRunAndItsDoneHint() throws {
        let (project, instance) = try makeProject("acquire")
        let lock = try heldLockFile("acquire")
        defer { flock(lock.fd, LOCK_UN); close(lock.fd) }

        let held = try acquire(project: project, instance: instance, lockPath: lock.path)
        XCTAssertEqual(held.state, .held)
        XCTAssertFalse(held.reclaimed)
        XCTAssertEqual(held.targetInstanceUuid, instance)
        XCTAssertEqual(held.run?.doneHint, "exits non-zero on failure")
        XCTAssertEqual(held.run?.state, .queued)
    }

    /// THE POINT OF THE FEATURE: a second agent is refused while the first lives.
    func testASecondAgentIsRefusedWhileTheHolderLives() throws {
        let (project, _) = try makeProject("refuse")
        let lock = try heldLockFile("refuse")
        defer { flock(lock.fd, LOCK_UN); close(lock.fd) }

        _ = try acquire(project: project, lockPath: lock.path)
        XCTAssertThrowsError(try acquire(project: project, lockPath: lock.path)) { error in
            XCTAssertTrue(
                "\(error)".contains("held by run"),
                "the refusal must name the holder so a human can find it, got: \(error)")
        }
    }

    /// THE CASE THAT MATTERS MOST: a holder that dies without releasing.
    ///
    /// Dropping the flock is exactly what the kernel does when a process exits,
    /// including under `kill -9`, which no cooperative release can catch. The
    /// lock must read as OPEN immediately — no timeout, no lease expiry, no
    /// reaper daemon. Liveness is DERIVED from a lock we can win, the same way
    /// `KernelOwnership` derives the kernel's own authority.
    func testADeadHolderReadsAsOpenWithNoTimeout() throws {
        let (project, _) = try makeProject("dead")
        let lock = try heldLockFile("dead")

        let held = try acquire(project: project, lockPath: lock.path)
        XCTAssertEqual(held.state, .held)

        // The holder dies.
        flock(lock.fd, LOCK_UN)
        close(lock.fd)

        let afterDeath = try env.send(
            .testLockStatus, TestLockStatusRequest(projectUuid: project), TestLockResponse.self)
        XCTAssertEqual(afterDeath.state, .open,
                       "a dead holder must free the lock at the NEXT read, with no timeout")
    }

    /// Reclaiming marks the orphan `abandoned`, not `failed`.
    ///
    /// The distinction is load-bearing. "We never found out" is not "it went
    /// red", and collapsing them would let a crashed run masquerade as a real
    /// result — the kind of false signal that erodes trust in a suite.
    func testReclaimAbandonsTheOrphanRatherThanFailingIt() throws {
        let (project, _) = try makeProject("reclaim")
        let lock = try heldLockFile("reclaim")

        let orphaned = try acquire(project: project, lockPath: lock.path)
        let orphanUuid = try XCTUnwrap(orphaned.run?.uuid)
        flock(lock.fd, LOCK_UN)
        close(lock.fd)

        let lock2 = try heldLockFile("reclaim2")
        defer { flock(lock2.fd, LOCK_UN); close(lock2.fd) }
        let reclaimed = try acquire(project: project, lockPath: lock2.path)
        XCTAssertTrue(reclaimed.reclaimed, "stepping over a dead holder must be reported, not silent")

        let orphan = try env.send(
            .testRunStatus, TestRunStatusRequest(runUuid: orphanUuid), TestRunResponse.self)
        XCTAssertEqual(orphan.runs.first?.state, .abandoned)
    }

    /// History survives a re-lock — the whole reason the ask's single row
    /// became two tables.
    ///
    /// Verified in SQL rather than over the wire, because what is being asserted
    /// is a PERSISTENCE property: the append-only ledger kept both rows while
    /// the mutable claim cell was overwritten twice.
    func testRunHistorySurvivesRelocking() throws {
        let (project, _) = try makeProject("history")
        for round in 0..<3 {
            let lock = try heldLockFile("history\(round)")
            let held = try acquire(project: project, lockPath: lock.path)
            _ = try env.send(
                .testLockRelease,
                TestLockReleaseRequest(
                    projectUuid: project,
                    runUuid: try XCTUnwrap(held.run?.uuid),
                    finalState: .passed, exitCode: 0, summary: "round \(round)"),
                TestLockResponse.self)
            flock(lock.fd, LOCK_UN); close(lock.fd)
        }

        let db = try env.readOnlyDatabase()
        let runs = try db.read {
            try Int.fetchOne($0,
                sql: "SELECT COUNT(*) FROM test_run WHERE project_uuid = ?",
                arguments: [project])
        }
        XCTAssertEqual(runs, 3, "the ledger must keep every run; only the claim cell is mutable")

        let cells = try db.read {
            try Int.fetchOne($0,
                sql: "SELECT COUNT(*) FROM project_test_lock WHERE project_uuid = ?",
                arguments: [project])
        }
        XCTAssertEqual(cells, 1, "UNIQUE(project_uuid) IS the one-entity-per-project rule")
    }

    /// Releasing a lock you do not hold is refused.
    func testReleasingSomebodyElsesLockIsRefused() throws {
        let (project, _) = try makeProject("wrongrelease")
        let lock = try heldLockFile("wrongrelease")
        defer { flock(lock.fd, LOCK_UN); close(lock.fd) }

        _ = try acquire(project: project, lockPath: lock.path)
        XCTAssertThrowsError(try env.send(
            .testLockRelease,
            TestLockReleaseRequest(
                projectUuid: project,
                runUuid: UUID().uuidString.lowercased(),
                finalState: .passed),
            TestLockResponse.self))
    }

    /// A release stamps the run terminal and re-opens the project.
    func testReleaseStampsTheRunAndReopensTheProject() throws {
        let (project, _) = try makeProject("release")
        let lock = try heldLockFile("release")
        defer { flock(lock.fd, LOCK_UN); close(lock.fd) }

        let held = try acquire(project: project, lockPath: lock.path)
        let runUuid = try XCTUnwrap(held.run?.uuid)

        _ = try env.send(
            .testRunStart,
            TestRunStartRequest(runUuid: runUuid, expectedVersion: try XCTUnwrap(held.run?.version)),
            TestRunResponse.self)

        let released = try env.send(
            .testLockRelease,
            TestLockReleaseRequest(
                projectUuid: project, runUuid: runUuid,
                finalState: .passed, exitCode: 0, summary: "ok"),
            TestLockResponse.self)
        XCTAssertEqual(released.state, .open)

        let final = try env.send(
            .testRunStatus, TestRunStatusRequest(runUuid: runUuid), TestRunResponse.self)
        XCTAssertEqual(final.runs.first?.state, .passed)
        XCTAssertEqual(final.runs.first?.exitCode, 0)
        XCTAssertNotNil(final.runs.first?.startedAt)
        XCTAssertNotNil(final.runs.first?.finishedAt)
    }

    /// Suites are declared in the REPO, so a project with no manifest reports
    /// none — and says where it looked, which is how you tell "none declared"
    /// from "wrong checkout".
    func testSuiteListReportsWhereItLooked() throws {
        let (project, _) = try makeProject("suites")
        let suites = try env.send(
            .testSuiteList, TestSuiteListRequest(projectUuid: project), TestSuiteListResponse.self)
        XCTAssertTrue(suites.suites.isEmpty)
        XCTAssertNil(suites.manifestPath, "no manifest means nil, not an empty path")
    }
}
