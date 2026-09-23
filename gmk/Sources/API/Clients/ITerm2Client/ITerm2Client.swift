import Foundation
import SwiftProtobuf

actor ITerm2Client {
    static let shared = ITerm2Client()

    private let queue = DispatchSerialQueue(label: "com.gmvibes.iterm2")

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private var client: APIClient?

    /// Initializes the shared iTerm2 client instance.
    ///
    /// - Returns: A new iTerm2 client actor.
    private init() {}

    /// Creates a new pane in iTerm2 with the given configuration.
    ///
    /// Attempts to create the pane with the requested profile, falling back to
    /// the default profile if the named profile is not available.
    ///
    /// - Parameter request: The pane launch request with profile and properties.
    /// - Returns: A session identifier for the created pane.
    /// - Throws: `ITerm2Error` if the creation fails.
    func createWindow(_ request: PaneLaunchRequest) async throws(ITerm2Error) -> PaneSession {
        do {
            return try await attemptCreate(request, profileName: request.profileName)
        } catch .transportFailed(let reason, let code) {
            teardown()
            do {
                return try await attemptCreate(request, profileName: request.profileName)
            } catch {
                _ = (reason, code)
                throw error
            }
        }
    }

    /// Disconnects from iTerm2 and resets the client state.
    func disconnect() {
        teardown()
    }

    /// Resets the client connection to nil and disconnects.
    private func teardown() {
        client?.disconnect()
        client = nil
    }

    /// Returns a connected API client, establishing a connection if needed.
    ///
    /// - Returns: A connected iTerm2 API client.
    /// - Throws: `ITerm2Error` if connection fails.
    private func connectIfNeeded() throws(ITerm2Error) -> APIClient {
        if let client { return client }
        let fresh = try APIClient.connect()
        client = fresh
        return fresh
    }

    /// Attempts to create a pane with profile retry and fallback logic.
    ///
    /// Tries the requested profile, falls back to the default profile if the
    /// named profile is invalid, and retries with a delay if needed.
    ///
    /// - Parameters:
    ///   - request: The pane launch request.
    ///   - profileName: The profile name to use, or nil for the default profile.
    /// - Returns: A session identifier for the created pane.
    /// - Throws: `ITerm2Error` if all creation attempts fail.
    private func attemptCreate(
        _ request: PaneLaunchRequest,
        profileName: String?
    ) async throws(ITerm2Error) -> PaneSession {
        let response = try send(request, profileName: profileName)

        switch response.status {
        case .ok:
            return PaneSession(
                windowId: response.windowID,
                tabId: response.tabID,
                sessionId: response.sessionID,
                usedDefaultProfile: profileName == nil
            )

        case .invalidProfileName:
            try await sleep(milliseconds: 500)
            let retry = try send(request, profileName: profileName)
            if retry.status == .ok {
                return PaneSession(
                    windowId: retry.windowID,
                    tabId: retry.tabID,
                    sessionId: retry.sessionID,
                    usedDefaultProfile: profileName == nil
                )
            }
            guard profileName != nil else {
                throw .launchRejected(status: "\(retry.status)")
            }
            let fallback = try send(request, profileName: nil)
            guard fallback.status == .ok else {
                throw .launchRejected(status: "\(fallback.status)")
            }
            return PaneSession(
                windowId: fallback.windowID,
                tabId: fallback.tabID,
                sessionId: fallback.sessionID,
                usedDefaultProfile: true
            )

        default:
            throw .launchRejected(status: "\(response.status)")
        }
    }

    /// Sends a tab creation request to iTerm2 and returns the response.
    ///
    /// - Parameters:
    ///   - request: The pane launch request with profile properties.
    ///   - profileName: The profile name to use, or nil for the default.
    /// - Returns: The iTerm2 create tab response.
    /// - Throws: `ITerm2Error` if the request fails.
    private func send(
        _ request: PaneLaunchRequest,
        profileName: String?
    ) throws(ITerm2Error) -> Iterm2_CreateTabResponse {
        let api = try connectIfNeeded()

        var create = Iterm2_CreateTabRequest()
        if let profileName { create.profileName = profileName }
        create.customProfileProperties = request.profileProperties.map { property in
            var p = Iterm2_ProfileProperty()
            p.key = property.key
            p.jsonValue = property.jsonValue
            return p
        }

        var message = Iterm2_ClientOriginatedMessage()
        message.createTabRequest = create

        let response = try api.send(message)
        guard case .createTabResponse(let create)? = response.submessage else {
            throw .serverError("iTerm2 answered a CreateTabRequest with something else")
        }
        return create
    }

    /// Asynchronously sleeps for the specified milliseconds.
    ///
    /// - Parameter milliseconds: The duration to sleep in milliseconds.
    /// - Throws: `ITerm2Error.cancelled` if the sleep is interrupted.
    private func sleep(milliseconds: Int) async throws(ITerm2Error) {
        do {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        } catch {
            throw .cancelled
        }
    }
}
