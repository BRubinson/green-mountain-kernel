import AppKit
import Foundation

@MainActor
enum ITerm2App {
    static let bundleIdentifier = "com.googlecode.iterm2"

    static var socketPath: String { SocketConnection.socketPath() }

    static func appURL() throws(ITerm2Error) -> URL {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        else {
            throw .appNotInstalled
        }
        return url
    }

    static func ensureRunning(
        progress: @Sendable (LaunchStage) -> Void = { _ in }
    ) async throws(ITerm2Error) {
        let path = SocketConnection.socketPath()

        if SocketConnection.isServerListening(path: path) { return }

        let url = try appURL()
        let wasRunning =
            !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty

        if !wasRunning {
            progress(.startingApp)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                )
            } catch {
                throw .transportFailed(
                    reason: "Could not launch iTerm2: \(error.localizedDescription)",
                    errno: nil
                )
            }
        }

        let budget = wasRunning ? 1.0 : 10.0
        let deadline = Date().addingTimeInterval(budget)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 200 * 1_000_000)
            } catch {
                throw .cancelled
            }
            if SocketConnection.isServerListening(path: path) { return }
        }

        throw .apiServerUnavailable(socketPath: path)
    }

    static func activate() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ) {
            app.activate()
        }
    }
}
