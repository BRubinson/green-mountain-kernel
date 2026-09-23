import Foundation

struct PaneProfileProperty: Sendable, Equatable {
    let key: String
    let jsonValue: String

    /// Creates a pane profile property with a raw JSON value.
    ///
    /// - Parameters:
    ///   - key: The property key name.
    ///   - jsonValue: The raw JSON string value.
    init(key: String, jsonValue: String) {
        self.key = key
        self.jsonValue = jsonValue
    }

    /// Creates a string-typed pane profile property.
    ///
    /// Escapes special characters (quotes, backslashes, control chars) for
    /// JSON encoding.
    ///
    /// - Parameters:
    ///   - key: The property key name.
    ///   - value: The string value to encode.
    /// - Returns: A `PaneProfileProperty` with escaped JSON string value.
    static func string(_ key: String, _ value: String) -> PaneProfileProperty {
        var escaped = ""
        escaped.reserveCapacity(value.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case let s where s.value < 0x20:
                escaped += String(format: "\\u%04x", s.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return PaneProfileProperty(key: key, jsonValue: "\"\(escaped)\"")
    }

    /// Creates a boolean-typed pane profile property.
    ///
    /// - Parameters:
    ///   - key: The property key name.
    ///   - value: The boolean value to encode.
    /// - Returns: A `PaneProfileProperty` with JSON boolean value.
    static func bool(_ key: String, _ value: Bool) -> PaneProfileProperty {
        PaneProfileProperty(key: key, jsonValue: value ? "true" : "false")
    }
}

struct PaneLaunchRequest: Sendable, Equatable {
    let profileName: String?
    let profileProperties: [PaneProfileProperty]

    /// Creates a pane launch request with optional profile and properties.
    ///
    /// - Parameters:
    ///   - profileName: The iTerm2 profile name, or nil to use the default.
    ///   - profileProperties: Custom profile properties to override.
    init(profileName: String?, profileProperties: [PaneProfileProperty]) {
        self.profileName = profileName
        self.profileProperties = profileProperties
    }
}

struct PaneSession: Sendable, Equatable {
    let windowId: String
    let tabId: Int32
    let sessionId: String

    let usedDefaultProfile: Bool

    /// Creates a pane session result from iTerm2.
    ///
    /// - Parameters:
    ///   - windowId: The iTerm2 window identifier.
    ///   - tabId: The tab number within the window.
    ///   - sessionId: The iTerm2 session identifier.
    ///   - usedDefaultProfile: Whether the default profile was used.
    init(windowId: String, tabId: Int32, sessionId: String, usedDefaultProfile: Bool) {
        self.windowId = windowId
        self.tabId = tabId
        self.sessionId = sessionId
        self.usedDefaultProfile = usedDefaultProfile
    }
}

@MainActor
enum ITerm2Launcher {
    /// Launches a pane in iTerm2 with the given profile and properties.
    ///
    /// - Parameters:
    ///   - request: The pane launch configuration.
    ///   - progress: A closure called with launch stage updates.
    /// - Returns: The created `PaneSession`.
    /// - Throws: `ITerm2Error` if the operation fails.
    @discardableResult
    static func launchPane(
        _ request: PaneLaunchRequest,
        progress: @Sendable (LaunchStage) -> Void = { _ in }
    ) async throws(ITerm2Error) -> PaneSession {
        progress(.preparing)

        try await ITerm2App.ensureRunning(progress: progress)

        progress(.connecting)
        let session = try await ITerm2Client.shared.createWindow(request)

        progress(.openingWindow)
        ITerm2App.activate()

        return session
    }

    /// Opens a new window in iTerm2 with an optional profile.
    ///
    /// - Parameters:
    ///   - profileName: The iTerm2 profile name, or nil for the default profile.
    ///   - profileProperties: Custom profile properties to override.
    /// - Returns: The created `PaneSession`.
    /// - Throws: `ITerm2Error` if the operation fails.
    @discardableResult
    static func openWindow(
        profileName: String?,
        profileProperties: [PaneProfileProperty] = []
    ) async throws(ITerm2Error) -> PaneSession {
        try await launchPane(
            PaneLaunchRequest(profileName: profileName, profileProperties: profileProperties)
        )
    }

    /// Disconnects from the iTerm2 application.
    static func disconnect() async {
        await ITerm2Client.shared.disconnect()
    }
}
