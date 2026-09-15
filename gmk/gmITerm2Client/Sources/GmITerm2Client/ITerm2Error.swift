import Foundation

/// Every way reaching iTerm2 can fail, as a closed set.
///
/// This REPLACES `it2cli`'s `IT2Error`, which was a flat enum of `String`
/// payloads — fine for a CLI that prints and exits, wrong for a repo whose
/// failure discipline is typed (`StoreError`, `DaemonError.invalidTransition(reason:)`).
/// Re-typing it on the way in was a condition of the transport decision, not a
/// tidy-up.
///
/// **NO `LocalizedError` CONFORMANCE, DELIBERATELY.** The caller's exhaustive
/// `switch` over these cases is a real compile-time guard: add a case and every
/// call site that has to say something about it fails to build until it does. A
/// default `errorDescription` would hand every call site a plausible-looking
/// string and defeat that entirely — the new case would ship silently, phrased
/// by nobody.
public enum ITerm2Error: Error, Sendable, Equatable {
    /// The bundle id `com.googlecode.iterm2` does not resolve to an app.
    case appNotInstalled

    /// iTerm2 is running (or was launched) but never bound its API socket.
    ///
    /// Overwhelmingly this means the Python API is switched off, which is why
    /// callers are expected to collapse it into the same message as
    /// ``apiDisabled`` rather than reporting a generic timeout.
    case apiServerUnavailable(socketPath: String)

    /// The WebSocket handshake returned 401. The Python API is off.
    case apiDisabled

    /// `osascript` produced no cookie — almost always TCC denying the Apple
    /// event, i.e. Automation permission was never granted (or was revoked).
    case automationDenied

    /// The handshake returned something that was neither 101 nor 401.
    case handshakeFailed(status: String)

    /// connect / send / recv failed at the socket layer.
    case transportFailed(reason: String, errno: Int32?)

    /// The request went out but its answer never came back — the connection
    /// dropped or the read timed out AFTER the bytes were away.
    ///
    /// Distinct from `transportFailed` because the two demand OPPOSITE
    /// handling: a send that failed can be retried, whereas a lost response
    /// means iTerm2 MAY ALREADY HAVE DONE THE WORK. `CreateTabRequest` is not
    /// idempotent, so retrying this one opens a second window running a second
    /// `claude` against the same prompt — a worse outcome than the failure it
    /// would be papering over. NEVER retry on this case.
    case responseLost(reason: String)

    /// `ServerOriginatedMessage.error` came back populated.
    case serverError(String)

    /// `CreateTabResponse.Status` was not `OK`.
    case launchRejected(status: String)

    /// A path destined for the profile's `Command` holds a character the
    /// argv-split form cannot carry safely.
    case unsafeCommandPath(String)

    /// The launch was cancelled while it was waiting.
    case cancelled
}
