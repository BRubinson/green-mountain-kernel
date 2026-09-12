import Foundation

/// Outcome of one briefing-readiness poll session.
public enum BriefingWaitOutcome {
    case ready(BriefingGetResponse)
    /// Deadline hit; `lastSeen` is the most recent row observed (nil when
    /// every poll came back absent — i.e. the briefing was never opened).
    case timedOut(lastSeen: AgentBriefingRow?)
}

/// The client-side loop behind every "wait until the briefing is ready": re-issue
/// the GET until the briefing reads `ready`, sleeping between polls. `fetch`
/// returns nil for a RETRYABLE absence (SUMMARY_ABSENT under a selector form —
/// the doper-opens-it-itself window) and throws everything else immediately.
/// The deadline is WALL-CLOCK so fetch latency spends the budget too — the
/// timeout must fire before the caller's own harness timeout, however slow the
/// daemon answers. Injected sleeper/clock keep it testable without a live daemon
/// or real time.
///
/// THIS LIVES IN THE KIT, NOT IN A FRONT-END. Both the MCP server's
/// `wait_for_briefing` tool and the shell client need it, and two copies of a
/// polling loop drift apart in exactly the way that makes a gate silently stop
/// gating.
///
/// CALLER TIMEOUT CEILING: an MCP tool call issued from the main conversation
/// that runs past ~2 minutes is moved to a background task and silently returns
/// control to the caller. Any MCP-facing wrapper must therefore cap
/// `timeoutSeconds` well under that and report a timeout as a RESULT the caller
/// loops on — never as an error.
public func awaitBriefingReady(
    timeoutSeconds: Int,
    pollIntervalMicros: UInt32 = 1_000_000,
    sleeper: (UInt32) -> Void = { usleep($0) },
    now: () -> Date = { Date() },
    fetch: () throws -> BriefingGetResponse?
) rethrows -> BriefingWaitOutcome {
    let deadline = now().addingTimeInterval(TimeInterval(timeoutSeconds))
    var lastSeen: AgentBriefingRow?
    while true {
        if let response = try fetch() {
            if response.briefing.status == "ready" { return .ready(response) }
            lastSeen = response.briefing
        }
        if now() >= deadline { return .timedOut(lastSeen: lastSeen) }
        sleeper(pollIntervalMicros)
    }
}
