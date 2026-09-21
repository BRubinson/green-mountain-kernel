import AppKit
import Foundation

@MainActor
enum ITerm2App {
    static let bundleIdentifier = "com.googlecode.iterm2"

    private static let app = ExternalMacApp(bundleIdentifier: bundleIdentifier)

    static var socketPath: String { SocketConnection.socketPath() }

    static func appURL() throws(ITerm2Error) -> URL {
        do {
            return try app.url()
        } catch {
            throw mapped(error)
        }
    }

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

    static func activate() {
        app.activate()
    }

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
