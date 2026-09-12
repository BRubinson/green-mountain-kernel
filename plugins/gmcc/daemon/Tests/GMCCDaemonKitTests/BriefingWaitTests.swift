import XCTest
import GMCCDaemonKit

// The --wait loop's timeout/poll semantics, exercised with an injected
// clock, sleeper, and scripted fetches — a silent regression here reverts
// the whole doper-ordering gate invisibly.
final class BriefingWaitTests: XCTestCase {

    private func row(status: String, version: Int64 = 0) -> AgentBriefingRow {
        AgentBriefingRow(
            uuid: "b-uuid", version: version, sessionUuid: "s-uuid",
            promptUuid: "p-uuid", briefingForStep: "initial", status: status,
            agentId: nil, dopeScopeUuid: nil, dopeScopeRevision: nil,
            dopeRefs: status == "ready"
                ? [AgentBriefingDopeRefRow(uuid: "r-1", dopeCode: "the.briefing", brief: nil, seq: 1)]
                : [],
            kbiteRefs: [], fileChangeRefs: [],
            createdAt: "", updatedAt: "")
    }

    private func response(status: String, version: Int64 = 0) -> BriefingGetResponse {
        BriefingGetResponse(
            briefing: row(status: status, version: version),
            staleness: BriefingStaleness(
                stampedRevision: nil, currentRevision: nil,
                drifted: false, ghostDotPaths: []))
    }

    /// Scripted fetch: replays the given results in order, holding the last
    /// one for every poll past the end of the script.
    private func scripted(_ results: [BriefingGetResponse?]) -> () -> BriefingGetResponse? {
        var index = 0
        return {
            defer { index += 1 }
            return results[min(index, results.count - 1)]
        }
    }

    /// A fake wall clock: sleeps advance it by the slept interval, and
    /// `fetchLatency` seconds elapse inside every fetch — so tests can model
    /// both an instant daemon and a slow one.
    private final class Clock {
        var seconds: TimeInterval = 0
        var sleeps = 0
        func now() -> Date { Date(timeIntervalSince1970: seconds) }
        func sleep(_ micros: UInt32) {
            sleeps += 1
            seconds += TimeInterval(micros) / 1_000_000
        }
    }

    func testReadyOnFirstPollReturnsWithoutSleeping() {
        let clock = Clock()
        let outcome = awaitBriefingReady(
            timeoutSeconds: 90, sleeper: clock.sleep, now: clock.now,
            fetch: scripted([response(status: "ready")]))
        guard case .ready(let got) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(got.briefing.dopeRefs.map(\.dopeCode), ["the.briefing"])
        XCTAssertEqual(clock.sleeps, 0)
    }

    func testBuildingThenReadyPollsThrough() {
        let clock = Clock()
        let outcome = awaitBriefingReady(
            timeoutSeconds: 90, sleeper: clock.sleep, now: clock.now,
            fetch: scripted([
                response(status: "building"),
                response(status: "building"),
                response(status: "ready", version: 2),
            ]))
        guard case .ready(let got) = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
        XCTAssertEqual(got.briefing.version, 2)
        XCTAssertEqual(clock.sleeps, 2)
    }

    func testAbsentThenReadyPollsThroughNilFetches() {
        let clock = Clock()
        let outcome = awaitBriefingReady(
            timeoutSeconds: 90, sleeper: clock.sleep, now: clock.now,
            fetch: scripted([nil, nil, response(status: "ready")]))
        guard case .ready = outcome else {
            return XCTFail("expected .ready, got \(outcome)")
        }
    }

    func testTimeoutOnPersistentBuildingReportsLastSeenRow() {
        // 3s budget at 1s polls: fetches at t=0,1,2,3 then the deadline
        // check fails — never ready, three sleeps.
        let clock = Clock()
        let outcome = awaitBriefingReady(
            timeoutSeconds: 3, sleeper: clock.sleep, now: clock.now,
            fetch: scripted([response(status: "building", version: 1)]))
        guard case .timedOut(let lastSeen) = outcome else {
            return XCTFail("expected .timedOut, got \(outcome)")
        }
        XCTAssertEqual(lastSeen?.status, "building")
        XCTAssertEqual(lastSeen?.version, 1)
        XCTAssertEqual(clock.sleeps, 3)
    }

    func testSlowFetchesSpendTheBudgetToo() {
        // Every fetch costs 2s of wall clock; a 3s budget survives only two
        // of them — the deadline is time-based, not attempt-based.
        let clock = Clock()
        var fetches = 0
        let outcome = awaitBriefingReady(
            timeoutSeconds: 3, sleeper: clock.sleep, now: clock.now,
            fetch: {
                fetches += 1
                clock.seconds += 2
                return self.response(status: "building")
            })
        guard case .timedOut = outcome else {
            return XCTFail("expected .timedOut, got \(outcome)")
        }
        XCTAssertEqual(fetches, 2)
        XCTAssertEqual(clock.sleeps, 1)
    }

    func testTimeoutOnPersistentAbsenceHasNoLastSeen() {
        let clock = Clock()
        let outcome = awaitBriefingReady(
            timeoutSeconds: 2, sleeper: clock.sleep, now: clock.now,
            fetch: scripted([nil]))
        guard case .timedOut(let lastSeen) = outcome else {
            return XCTFail("expected .timedOut, got \(outcome)")
        }
        XCTAssertNil(lastSeen)
    }

    func testFetchErrorsPropagateImmediately() {
        struct Boom: Error {}
        XCTAssertThrowsError(
            try awaitBriefingReady(
                timeoutSeconds: 90, sleeper: { _ in XCTFail("must not sleep after a throw") },
                fetch: { throw Boom() })
        ) { XCTAssert($0 is Boom) }
    }
}
