import Foundation

public enum ITerm2Error: Error, Sendable, Equatable {
    case appNotInstalled

    case apiServerUnavailable(socketPath: String)

    case apiDisabled

    case automationDenied

    case handshakeFailed(status: String)

    case transportFailed(reason: String, errno: Int32?)

    case responseLost(reason: String)

    case serverError(String)

    case launchRejected(status: String)

    case unsafeCommandPath(String)

    case cancelled
}
