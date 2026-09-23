import Foundation

/// Outcome of one briefing-readiness poll session.
enum BriefingWaitOutcome {
    case ready(BriefingGetResponse)
    /// Deadline hit; `lastSeen` is the most recent row observed (nil when
    /// every poll came back absent — i.e. the briefing was never opened).
    case timedOut(lastSeen: AgentBriefingRow?)
}

/// Polls the briefing state until ready or timeout.
///
/// The client-side loop behind every "wait until the briefing is ready" operation.
/// `fetch` returns nil for retryable absence and throws immediately otherwise.
/// Deadline is wall-clock; fetch latency consumes the budget. MCP tool calls past
/// ~2 minutes move to background and silently return. An MCP-facing wrapper must cap
/// `timeoutSeconds` under that ceiling and report timeout as a result, never as error.
///
/// - Parameters:
///   - timeoutSeconds: The maximum seconds to wait; moves to background if exceeded.
///   - pollIntervalMicros: The sleep duration between fetches; defaults to 1 second.
///   - sleeper: The sleep function; defaults to `usleep`.
///   - now: The current time function; defaults to `Date()`.
///   - fetch: A closure returning the briefing or nil; throws to fail immediately.
/// - Returns: `.ready` when the briefing is ready, or `.timedOut` when deadline is hit.
/// - Throws: Errors from the fetch closure; retryable absence is nil, not an error.
func awaitBriefingReady(
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
