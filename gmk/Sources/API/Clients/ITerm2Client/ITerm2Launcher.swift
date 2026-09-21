import Foundation

struct PaneProfileProperty: Sendable, Equatable {
    let key: String
    let jsonValue: String

    init(key: String, jsonValue: String) {
        self.key = key
        self.jsonValue = jsonValue
    }

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

    static func bool(_ key: String, _ value: Bool) -> PaneProfileProperty {
        PaneProfileProperty(key: key, jsonValue: value ? "true" : "false")
    }
}

struct PaneLaunchRequest: Sendable, Equatable {
    let profileName: String?
    let profileProperties: [PaneProfileProperty]

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

    init(windowId: String, tabId: Int32, sessionId: String, usedDefaultProfile: Bool) {
        self.windowId = windowId
        self.tabId = tabId
        self.sessionId = sessionId
        self.usedDefaultProfile = usedDefaultProfile
    }
}

@MainActor
enum ITerm2Launcher {
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

    @discardableResult
    static func openWindow(
        profileName: String?,
        profileProperties: [PaneProfileProperty] = []
    ) async throws(ITerm2Error) -> PaneSession {
        try await launchPane(
            PaneLaunchRequest(profileName: profileName, profileProperties: profileProperties)
        )
    }

    static func disconnect() async {
        await ITerm2Client.shared.disconnect()
    }
}
