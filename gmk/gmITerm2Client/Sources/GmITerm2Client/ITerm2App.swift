import AppKit
import Foundation

/// The AppKit half: resolve the bundle, get iTerm2 running, bring it forward.
///
/// Deliberately kept OUT of the actor. Everything here needs the main thread
/// and none of it blocks on a socket, so mixing the two would force one of them
/// onto the wrong executor.
@MainActor
public enum ITerm2App {
    /// iTerm2's bundle id.
    ///
    /// NOTE: the bundle on disk is `iTerm.app`, **not** `iTerm2.app`. The
    /// identifier is what matters and this is the same lookup GMVibes' existing
    /// launcher already does, so do not "correct" either one to match the other.
    public static let bundleIdentifier = "com.googlecode.iterm2"

    /// Where the API server binds, for a caller that wants to report it.
    public static var socketPath: String { SocketConnection.socketPath() }

    /// Resolve the installed application, or fail.
    public static func appURL() throws(ITerm2Error) -> URL {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw .appNotInstalled
        }
        return url
    }

    /// Make sure iTerm2 is running AND its API socket is bound.
    ///
    /// The two are not the same thing, and the gap between them is the race
    /// this function exists to close.
    public static func ensureRunning(
        progress: @Sendable (LaunchStage) -> Void = { _ in }
    ) async throws(ITerm2Error) {
        let path = SocketConnection.socketPath()

        // 1. WARM PATH — and the test is CONNECTABILITY, NEVER `fileExists`.
        //
        //    iTerm2 unlinks this path only immediately BEFORE binding
        //    (`iTermAPIServer.m`) and never on quit, so a bound AF_UNIX path
        //    survives as an inode after the listening process exits. On any
        //    machine where iTerm2 has EVER run with the Python API on, the file
        //    is there forever — running or not.
        //
        //    A `fileExists` warm path therefore returns "the server is up" on
        //    the ordinary daily state of iTerm2 being quit, skips the entire
        //    cold start below, and leaves every caller to die on ECONNREFUSED
        //    with no way to recover by pressing Play again. DO NOT "simplify"
        //    this back to a stat.
        if SocketConnection.isServerListening(path: path) { return }

        let url = try appURL()
        let wasRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty

        // 2. COLD START. Launch without activating — bringing iTerm2 forward
        //    now would steal focus before there is anything to look at. The
        //    activate comes after a successful create.
        //
        //    THIS AWAIT RETURNS ONCE THE APP IS *LAUNCHED*, WHICH IS NOT THE
        //    SAME AS API-SERVER-BOUND. That gap is the race; step 3 is the fix.
        if !wasRunning {
            progress(.startingApp)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url, configuration: configuration
                )
            } catch {
                throw .transportFailed(
                    reason: "Could not launch iTerm2: \(error.localizedDescription)",
                    errno: nil
                )
            }
        }

        // 3. POLL FOR THE SOCKET at 200ms.
        //
        //    A short budget when the app was ALREADY running: if iTerm2 is up
        //    and the socket still is not there, waiting longer proves nothing —
        //    it is not coming. A long budget on a cold launch, where the app
        //    genuinely needs time to get to the point of binding.
        let budget = wasRunning ? 1.0 : 10.0
        let deadline = Date().addingTimeInterval(budget)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 200 * 1_000_000)
            } catch {
                throw .cancelled
            }
            // Same rule as the warm path: a STALE socket file left by a
            // previous run would satisfy `fileExists` on the very first poll
            // and let us proceed against a server that has not bound yet.
            if SocketConnection.isServerListening(path: path) { return }
        }

        // 4. BUDGET EXHAUSTED.
        //
        //    This is reported as `.apiServerUnavailable`, which callers
        //    COLLAPSE INTO THE SAME UI TREATMENT AS `.apiDisabled`. That is
        //    deliberate: "iTerm2 came up but never bound its socket" is
        //    overwhelmingly "the Python API is switched off", and THAT is the
        //    thing the user must act on. A generic `.timedOut` would be
        //    technically honest and practically useless — it would tell someone
        //    that waiting failed without telling them what to do about it.
        throw .apiServerUnavailable(socketPath: path)
    }

    /// Bring iTerm2 to the front.
    ///
    /// **THIS CALL IS NOT REDUNDANT AND MUST NOT BE DELETED.** It looks
    /// redundant, because `CreateTabRequest` already orders the new window
    /// front — so somebody tidying up will eventually find it and remove it.
    ///
    /// `iTermAPIHelper.m:2389` sets `launcher.canActivate = NO` on EVERY
    /// API-created session. THE API SERVER DELIBERATELY SUPPRESSES CROSS-APP
    /// ACTIVATION. `select_tab` orders the window front WITHIN iTerm2, but it
    /// does not bring iTerm2 forward over the app that asked. Without this call
    /// a fully successful launch leaves the new window BEHIND GMVibes, and to
    /// the user that is indistinguishable from Play having done nothing at all.
    ///
    /// Making success legible is a requirement here, not a nicety.
    public static func activate() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ) {
            app.activate()
        }
    }
}
