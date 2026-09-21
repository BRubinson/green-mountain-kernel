import AppKit
import Foundation

enum ExternalAppError: Error, Sendable, Equatable {
    case notInstalled(bundleIdentifier: String)
    case launchFailed(reason: String)
    case readinessTimedOut
    case cancelled
}

/// A macOS application the kernel drives from the outside, addressed by bundle identifier.
struct ExternalMacApp: Sendable {
    let bundleIdentifier: String

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    @MainActor
    func url() throws(ExternalAppError) -> URL {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        else {
            throw .notInstalled(bundleIdentifier: bundleIdentifier)
        }
        return url
    }

    @MainActor
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    @MainActor
    func launchWithoutActivating() async throws(ExternalAppError) {
        let url = try url()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw .launchFailed(reason: error.localizedDescription)
        }
    }

    @MainActor
    func activate() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ) {
            app.activate()
        }
    }

    /// Polls `isReady` on `pollInterval` until it answers true or `budget` expires.
    static func waitUntilReady(
        budget: TimeInterval,
        pollInterval: TimeInterval = 0.2,
        isReady: @Sendable () -> Bool
    ) async throws(ExternalAppError) {
        let deadline = Date().addingTimeInterval(budget)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                throw .cancelled
            }
            if isReady() { return }
        }
        throw .readinessTimedOut
    }
}
