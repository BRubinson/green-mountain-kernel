import Foundation

public struct PaneProfileProperty: Sendable, Equatable {
    public let key: String
    public let jsonValue: String

    public init(key: String, jsonValue: String) {
        self.key = key
        self.jsonValue = jsonValue
    }

    public static func string(_ key: String, _ value: String) -> PaneProfileProperty {
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

    public static func bool(_ key: String, _ value: Bool) -> PaneProfileProperty {
        PaneProfileProperty(key: key, jsonValue: value ? "true" : "false")
    }
}

public struct PaneLaunchRequest: Sendable, Equatable {
    public let profileName: String?
    public let profileProperties: [PaneProfileProperty]

    public init(profileName: String?, profileProperties: [PaneProfileProperty]) {
        self.profileName = profileName
        self.profileProperties = profileProperties
    }
}

public struct PaneSession: Sendable, Equatable {
    public let windowId: String
    public let tabId: Int32
    public let sessionId: String

    public let usedDefaultProfile: Bool

    public init(windowId: String, tabId: Int32, sessionId: String, usedDefaultProfile: Bool) {
        self.windowId = windowId
        self.tabId = tabId
        self.sessionId = sessionId
        self.usedDefaultProfile = usedDefaultProfile
    }
}

public enum LaunchStage: Sendable {
    case preparing
    case startingApp
    case connecting
    case openingWindow
}

@MainActor
public enum ITerm2Launcher {
    @discardableResult
    public static func launchPane(
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
    public static func openWindow(
        profileName: String?,
        profileProperties: [PaneProfileProperty] = []
    ) async throws(ITerm2Error) -> PaneSession {
        try await launchPane(
            PaneLaunchRequest(profileName: profileName, profileProperties: profileProperties)
        )
    }

    public static func disconnect() async {
        await ITerm2Client.shared.disconnect()
    }
}
