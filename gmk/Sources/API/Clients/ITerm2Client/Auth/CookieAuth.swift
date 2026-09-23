import Foundation

enum CookieAuth {
    /// Fetches iTerm2 authentication credentials from the environment or AppleScript.
    ///
    /// First checks for `ITERM2_COOKIE` and `ITERM2_KEY` environment variables;
    /// if not found, requests credentials via AppleScript from iTerm2.
    ///
    /// - Returns: A tuple of optional cookie and key strings; both nil if unavailable.
    static func credentials() -> (cookie: String?, key: String?) {
        let env = ProcessInfo.processInfo.environment
        if let cookie = env["ITERM2_COOKIE"] {
            return (cookie, env["ITERM2_KEY"])
        }
        return requestCookie()
    }

    private static var appTarget: String {
        if let path = ProcessInfo.processInfo.environment["IT2_APP_PATH"] {
            return "application \"\(path)\""
        }
        return "application \"iTerm2\""
    }

    /// Requests iTerm2 authentication credentials via AppleScript.
    ///
    /// Invokes osascript to ask iTerm2 for the cookie and key for GMVibes.
    /// Returns nil for either value on failure or if iTerm2 does not respond.
    ///
    /// - Returns: A tuple of optional cookie and key strings.
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

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return (nil, nil) }

        guard
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return (nil, nil)
        }

        let parts = output.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return (nil, nil) }

        return (String(parts[0]), String(parts[1]))
    }
}
