import Foundation
import GRDB

// TEST_* — the agent-scoped test mutex. Bodies live in TestRunRepository; these
// wrappers own the transaction.
//
// All six COMPOSE inside `inTransaction { }` and none needs a
// `StoreError.notComposable` refusal, unlike the two families that do:
// `checkpointTruncate`, because a WAL checkpoint inside a transaction is illegal
// in SQLite, and the four-phase repo verbs, whose phase 3 does filesystem work.
// The flock probe in `acquire` is neither: one open, one flock, one close.

extension Store {

    /// List test suites from the repo manifest file.
    ///
    /// The repo declares suites in a file, never in a table, to avoid a second copy that
    /// silently disagrees when the repo is cloned into another environment.
    /// - Parameter req: The TEST_SUITE_LIST request.
    /// - Returns: The test suite list response.
    /// - Throws: Repository or file reading errors.
    func testSuiteList(_ req: TestSuiteListRequest) throws -> TestSuiteListResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).suiteList(req)
        }
    }

    /// Report the test lock status without reclaiming.
    ///
    /// Does NOT reclaim; a read that silently broke someone else's lock would make
    /// inspection destructive.
    /// - Parameter req: The TEST_LOCK_STATUS request.
    /// - Returns: The test lock response.
    /// - Throws: Repository errors.
    func testLockStatus(_ req: TestLockStatusRequest) throws -> TestLockResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).lockStatus(req)
        }
    }

    /// Claim the test lock for a project.
    ///
    /// Opens the ledger row and takes the lock in one transaction, so no window exists
    /// where a run could exist without holding its lock.
    /// - Parameter req: The TEST_LOCK_ACQUIRE request.
    /// - Returns: The test lock response.
    /// - Throws: Repository or lock acquisition errors.
    func testLockAcquire(_ req: TestLockAcquireRequest) throws -> TestLockResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).acquire(req)
        }
    }

    /// Release the test lock.
    /// - Parameter req: The TEST_LOCK_RELEASE request.
    /// - Returns: The test lock response.
    /// - Throws: Repository or lock release errors.
    func testLockRelease(_ req: TestLockReleaseRequest) throws -> TestLockResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).release(req)
        }
    }

    /// Mark a test run as started.
    /// - Parameter req: The TEST_RUN_START request.
    /// - Returns: The test run response.
    /// - Throws: Repository or run state errors.
    func testRunStart(_ req: TestRunStartRequest) throws -> TestRunResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).runStart(req)
        }
    }

    /// Report test run status.
    /// - Parameter req: The TEST_RUN_STATUS request.
    /// - Returns: The test run response.
    /// - Throws: Repository or query errors.
    func testRunStatus(_ req: TestRunStatusRequest) throws -> TestRunResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).runStatus(req)
        }
    }
}
