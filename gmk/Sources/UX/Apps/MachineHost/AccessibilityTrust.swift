import ApplicationServices
import Foundation
import Observation

/// Whether this app holds the Accessibility grant, as an observable, first-class state.
///
/// An ad-hoc re-signed build loses the grant silently, so "not trusted" is expected and shown, never assumed
/// away. Polling runs only while a caller asks for it.
@MainActor
@Observable
final class AccessibilityTrust {
    /// True when the process is trusted for Accessibility.
    private(set) var isTrusted = AXIsProcessTrusted()

    /// The poll timer while polling.
    @ObservationIgnored private var timer: Timer?

    /// Creates a trust monitor with the current grant read once.
    init() {}

    /// Re-reads the grant now.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Re-reads the grant every second until `stopPolling`.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Stops the poll.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Asks the system to show its Accessibility prompt for this app.
    func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Clears this app's stale Accessibility entry with `tccutil`, then prompts again.
    ///
    /// A rebuilt app keeps a greyed-out entry that does not match its signature; the reset removes it.
    func resetAndPrompt() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return prompt() }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleId]
        try? reset.run()
        reset.waitUntilExit()
        prompt()
    }
}
