import Foundation
import GRDB
import GmDaemonSdk

// TEST_* — the agent-scoped test mutex (m0029). Bodies live in
// TestRunRepository; these wrappers own the transaction.
//
// All six COMPOSE inside `inTransaction { }` and none of them needs a
// `StoreError.notComposable` refusal, which is worth saying explicitly because
// the two families that DO refuse look superficially similar. `checkpointTruncate`
// refuses because a WAL checkpoint inside a transaction is illegal in SQLite;
// the four-phase repo verbs refuse because their phase 3 does filesystem work
// holding no db lock, so composing one would pin the single writer across disk
// I/O.
//
// The flock probe in `acquire` is neither. It is one `open` + one `flock` +
// one `close` on a path already in hand — microseconds of syscall, no disk
// I/O, no lock held across it, and no thread hop. Pinning the writer for that
// long is the same order as the row write beside it.

extension Store {

    /// The repo declares its own suites, so this reads a FILE and never a
    /// table. That asymmetry is deliberate: the ask was that repo tests be
    /// configured in the repo, and a manifest living in the db would be a
    /// second copy that silently disagrees with the checkout the moment the
    /// repo is cloned into another environment.
    public func testSuiteList(_ req: TestSuiteListRequest) throws -> TestSuiteListResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).suiteList(req)
        }
    }

    /// Reports the lock, including whether the current holder is already gone.
    /// Deliberately does NOT reclaim: a read that silently broke somebody
    /// else's lock would make inspection destructive, which is the same reason
    /// `BOT_NEXT` stopped advancing prompts.
    public func testLockStatus(_ req: TestLockStatusRequest) throws -> TestLockResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).lockStatus(req)
        }
    }

    /// Claim the project. Opens the ledger row and takes the cell in ONE
    /// transaction, so there is no window where a run exists without holding
    /// the lock it was created for.
    public func testLockAcquire(_ req: TestLockAcquireRequest) throws -> TestLockResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).acquire(req)
        }
    }

    public func testLockRelease(_ req: TestLockReleaseRequest) throws -> TestLockResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).release(req)
        }
    }

    public func testRunStart(_ req: TestRunStartRequest) throws -> TestRunResponse {
        try boundary { db in
            try TestRunRepository(db: db, core: core).runStart(req)
        }
    }

    public func testRunStatus(_ req: TestRunStatusRequest) throws -> TestRunResponse {
        try boundaryRead { db in
            try TestRunRepository(db: db, core: core).runStatus(req)
        }
    }
}
