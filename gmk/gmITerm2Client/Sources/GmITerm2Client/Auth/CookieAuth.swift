import Foundation

/// Obtains the cookie/key pair the WebSocket handshake authenticates with.
///
/// Lifted from `it2cli/Sources/it2/Auth/CookieAuth.swift`: `$ITERM2_COOKIE` /
/// `$ITERM2_KEY` first, otherwise a single-use cookie requested through
/// `/usr/bin/osascript`, whose output is `COOKIE KEY` split on ONE space.
///
/// ## THE LOAD-BEARING CONSEQUENCE, STATED UP FRONT
///
/// **GMVibes is not running inside iTerm2, so it NEVER has those environment
/// variables, so the `osascript` branch is ALWAYS taken.** That subprocess
/// inherits GMVibes' TCC identity. Therefore:
///
/// **`NSAppleEventsUsageDescription` IS A HARD PREREQUISITE ON THE SOCKET ARM
/// TOO.** Choosing the unix socket over AppleScript did not escape it — it only
/// moved it one level down. Without that key macOS denies the Apple event,
/// `osascript` exits non-zero, this returns `nil`, and the handshake fails with
/// no cookie. The first successful request also pops a one-time "GMVibes wants
/// to control iTerm2" dialog, which under `LSUIElement = YES` (no Dock icon) is
/// easy to miss entirely; the caller owes the user a line pointing at
/// System Settings > Privacy & Security > Automation.
///
/// The upstream `reusable` / `ITERM_SESSION_ID` path is dropped. It exists to
/// announce itself in the terminal session that asked, and there is no such
/// session here — GMVibes is the originator.
enum CookieAuth {
    /// Credentials for the handshake, or `(nil, nil)` if none could be had.
    ///
    /// The caller maps `(nil, nil)` to ``ITerm2Error/automationDenied``: on this
    /// path a missing cookie is overwhelmingly a denied or never-granted
    /// Automation permission, and that is the thing a human can act on.
    static func credentials() -> (cookie: String?, key: String?) {
        let env = ProcessInfo.processInfo.environment
        if let cookie = env["ITERM2_COOKIE"] {
            return (cookie, env["ITERM2_KEY"])
        }
        return requestCookie()
    }

    // MARK: - Private

    /// The AppleScript target. `IT2_APP_PATH` aims at a specific bundle (a
    /// nightly, say); otherwise the application named "iTerm2".
    private static var appTarget: String {
        if let path = ProcessInfo.processInfo.environment["IT2_APP_PATH"] {
            return "application \"\(path)\""
        }
        return "application \"iTerm2\""
    }

    private static func requestCookie() -> (cookie: String?, key: String?) {
        let script = "tell \(appTarget) to request cookie and key for app named \"GMVibes\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (nil, nil)
        }

        // Read BEFORE waiting. The pair is short, so the pipe buffer cannot
        // realistically fill — but draining first is the form that cannot
        // deadlock, and getting it the other way round is a hang, not an error.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return (nil, nil) }

        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return (nil, nil)
        }

        // Output format: "COOKIE KEY", one space.
        let parts = output.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return (nil, nil) }

        return (String(parts[0]), String(parts[1]))
    }
}
