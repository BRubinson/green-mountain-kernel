import Foundation
import GmDaemon
import GmDaemonSdk

// TEST_* — the agent-scoped test mutex (m0029, wire v29).
//
// A mutex for AGENTS, sitting above the kernel's own single-writer flock:
// flock stops two KERNELS writing one database, these stop two AGENTS building
// and testing one repository.
//
// Note what is absent: there is no "run the tests" verb. Execution needs
// process supervision, output streaming and cancellation, none of which is this
// change. TEST_RUN_START records that a run began and what will signal its
// completion, which is exactly what another agent needs in order to decide
// whether to wait — and it keeps the surface small enough to be correct.

/// TEST_SUITE_LIST — the suites a project declares, read from the CHECKOUT.
enum TestSuiteListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestSuiteListRequest.self, from: line)
        return try okResult(.testSuiteList, head, try store.testSuiteList(request))
    }
}

/// TEST_LOCK_STATUS — who holds the project, and whether they are still alive.
/// Reports a dead holder without reclaiming: a read that silently broke
/// someone's lock would make inspection destructive.
enum TestLockStatusHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestLockStatusRequest.self, from: line)
        return try okResult(.testLockStatus, head, try store.testLockStatus(request))
    }
}

/// TEST_LOCK_ACQUIRE — claim the project, opening the ledger row and taking the
/// cell in ONE transaction. Reclaims a lock whose holder is provably gone.
enum TestLockAcquireHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestLockAcquireRequest.self, from: line)
        return try okResult(.testLockAcquire, head, try store.testLockAcquire(request))
    }
}

/// TEST_LOCK_RELEASE — hand the project back and stamp the run terminal.
enum TestLockReleaseHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestLockReleaseRequest.self, from: line)
        return try okResult(.testLockRelease, head, try store.testLockRelease(request))
    }
}

/// TEST_RUN_START — a claimed run actually began. Split from acquire because
/// claiming and starting are different moments, and "claimed but never started"
/// is a state worth being able to see.
enum TestRunStartHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestRunStartRequest.self, from: line)
        return try okResult(.testRunStart, head, try store.testRunStart(request))
    }
}

/// TEST_RUN_STATUS — one run, or a project's recent history.
enum TestRunStatusHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(TestRunStatusRequest.self, from: line)
        return try okResult(.testRunStatus, head, try store.testRunStatus(request))
    }
}
