import AppKit
import Foundation

@MainActor
enum ITerm2App {
    static let bundleIdentifier = "com.googlecode.iterm2"

    private static let app = ExternalMacApp(bundleIdentifier: bundleIdentifier)

    static var socketPath: String { SocketConnection.socketPath() }

    /// Fetches the URL of the installed iTerm2 application.
    ///
    /// - Returns: The file URL to the iTerm2 app bundle.
    /// - Throws: `ITerm2Error` if the app is not installed or inaccessible.
    static func appURL() throws(ITerm2Error) -> URL {
        do {
            return try app.url()
        } catch {
            throw mapped(error)
        }
    }

    /// Ensures iTerm2 is running and its API server is listening.
    ///
    /// Launches the app if needed and waits for the socket to become available.
    ///
    /// - Parameter progress: A callback to report launch stages.
    /// - Throws: `ITerm2Error` on launch failures or timeout.
    static func ensureRunning(
        progress: @Sendable (LaunchStage) -> Void = { _ in }
    ) async throws(ITerm2Error) {
        let path = SocketConnection.socketPath()

        if SocketConnection.isServerListening(path: path) { return }

        _ = try appURL()
        let wasRunning = app.isRunning

        if !wasRunning {
            progress(.startingApp)
            do {
                try await app.launchWithoutActivating()
            } catch {
                throw mapped(error)
            }
        }

        do {
            try await ExternalMacApp.waitUntilReady(budget: wasRunning ? 1.0 : 10.0) {
                SocketConnection.isServerListening(path: path)
            }
        } catch {
            throw mapped(error)
        }
    }

    /// Brings iTerm2 to the foreground.
    static func activate() {
        app.activate()
    }

    /// Maps an external app error to an iTerm2 error.
    ///
    /// - Parameter error: The external app error to map.
    /// - Returns: The corresponding iTerm2 error.
    private static func mapped(_ error: ExternalAppError) -> ITerm2Error {
        switch error {
        case .notInstalled:
            .appNotInstalled
        case .launchFailed(let reason):
            .transportFailed(reason: "Could not launch iTerm2: \(reason)", errno: nil)
        case .readinessTimedOut:
            .apiServerUnavailable(socketPath: SocketConnection.socketPath())
        case .cancelled:
            .cancelled
        }
    }
}
