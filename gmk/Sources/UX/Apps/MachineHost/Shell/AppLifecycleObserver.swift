import AppKit
import Foundation

/// Turns app, screen, wake and left-mouse notifications into reducer events while managing windows.
///
/// It also attaches and detaches the per-app accessibility threads, and every two seconds sends a full
/// `reconcile` snapshot, because window-destroyed notifications are not reliable.
@MainActor
final class AppLifecycleObserver {
    /// The period of the reconcile snapshot.
    static let refreshInterval: TimeInterval = 2
    /// The consecutive ticks the button must read up before a release the monitor missed is sent.
    static let missedReleaseTicks = 2

    /// Where events go.
    private let sink: WMEventSink
    /// Owns the per-app threads this observer attaches and detaches.
    private let interpreter: EffectInterpreter
    /// Called with every display enumeration, before `displaysChanged` is sent, so the caller can record it.
    private let displaysRead: @MainActor ([DisplayReading]) -> Void
    /// Whether the reducer believes the left button is held.
    private let mouseHeld: @MainActor () -> Bool
    /// The notification-center tokens while started.
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    /// The reconcile timer while started.
    private var timer: Timer?
    /// The global left-mouse-down and left-mouse-up monitors while started.
    private var mouseMonitors: [Any] = []
    /// The consecutive ticks that read the button up while the reducer believed it held.
    private var upTicksWhileHeld = 0
    /// True while a reconcile snapshot is being read.
    private var reconciling = false

    /// Creates an observer that feeds `sink` and attaches threads through `interpreter`.
    ///
    /// - Parameters:
    ///   - sink: Where events go.
    ///   - interpreter: Owns the per-app accessibility threads.
    ///   - mouseHeld: Answers whether the reducer believes the left button is held.
    ///   - displaysRead: Receives every display enumeration, e.g. to sync the `display` rows.
    init(
        sink: @escaping WMEventSink,
        interpreter: EffectInterpreter,
        mouseHeld: @escaping @MainActor () -> Bool,
        displaysRead: @escaping @MainActor ([DisplayReading]) -> Void
    ) {
        self.sink = sink
        self.interpreter = interpreter
        self.mouseHeld = mouseHeld
        self.displaysRead = displaysRead
    }

    /// True while the left mouse button is down, read from the combined session state.
    private static var buttonDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    /// Sends `displaysChanged`, attaches every regular app, then subscribes and starts the reconcile timer.
    ///
    /// Call before sending `.enable`: the reducer lays out against the displays this sends first.
    func start() {
        guard tokens.isEmpty else { return }
        emitDisplays()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(NotifiedApp(app))
        }
        subscribe()
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink(.mousePressed(at: NSEvent.mouseLocation)) }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.sink(.mouseReleased(at: NSEvent.mouseLocation)) }
        }
        mouseMonitors = [down, up].compactMap(\.self)
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    /// Removes every subscription, stops the timer and detaches every app thread.
    func stop() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens = []
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        upTicksWhileHeld = 0
        timer?.invalidate()
        timer = nil
        interpreter.detachAll()
    }

    /// Enumerates the displays, hands them to `displaysRead`, then sends `displaysChanged`.
    func emitDisplays() {
        let readings = DisplayIdentity.current()
        interpreter.setPrimaryHeight(DisplayIdentity.primaryHeight())
        displaysRead(readings)
        sink(.displaysChanged(readings.map(\.geom)))
    }

    /// Reads every app's windows and sends one `reconcile`; skipped while a previous read is outstanding.
    ///
    /// Skipped entirely while the left button is down. When the reducer believes the button held but it has
    /// read up for `missedReleaseTicks` ticks in a row, a `mouseReleased` with no drop point is sent first,
    /// which ends a hold whose release the monitor never saw.
    func reconcile() {
        guard !Self.buttonDown else {
            upTicksWhileHeld = 0
            return
        }
        upTicksWhileHeld = mouseHeld() ? upTicksWhileHeld + 1 : 0
        if upTicksWhileHeld >= Self.missedReleaseTicks {
            upTicksWhileHeld = 0
            sink(.mouseReleased(at: nil))
        }
        guard !reconciling else { return }
        reconciling = true
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await interpreter.snapshotAll()
            reconciling = false
            guard !tokens.isEmpty else { return }
            sink(.reconcile(observed: snapshot.observed, answered: snapshot.answered))
        }
    }

    /// Subscribes to the workspace and screen notifications.
    private func subscribe() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { observer, app in
            guard let app else { return }
            observer.attach(app)
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { observer, app in
            guard let app else { return }
            observer.interpreter.detach(pid: app.pid)
            observer.sink(.appTerminated(pid: app.pid))
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { observer, app in
            // A click-activation's focused window can be stale; the focused-window notification reports it.
            guard let app, !Self.buttonDown else { return }
            observer.interpreter.reportFocusedWindow(pid: app.pid)
        }
        observe(workspace, NSWorkspace.didWakeNotification) { observer, _ in observer.sink(.wake) }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { observer, _ in
            observer.emitDisplays()
        }
    }

    /// Adds one main-queue subscription whose handler receives this observer and the notification's app.
    ///
    /// The app is read from the notification itself, which stays valid after the process exits.
    ///
    /// - Parameters:
    ///   - center: The notification center.
    ///   - name: The notification name.
    ///   - handler: Called on the main actor with this observer and the app the notification names, if any.
    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (AppLifecycleObserver, NotifiedApp?) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                .map(NotifiedApp.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, app)
            }
        }
        tokens.append((center, token))
    }

    /// Attaches a thread for `app` and sends `appLaunched`.
    ///
    /// This app itself and apps without a launch date are skipped.
    ///
    /// - Parameter app: A running application.
    private func attach(_ app: NotifiedApp) {
        guard app.pid != ProcessInfo.processInfo.processIdentifier, let launchDate = app.launchDate else { return }
        let launchedAt = LaunchStamp.canonical(launchDate)
        guard interpreter.attach(pid: app.pid, launchedAt: launchedAt) else { return }
        sink(.appLaunched(pid: app.pid, launchedAt: launchedAt))
    }
}

/// The identity of an app, copied out of its `NSRunningApplication` as values before any actor hop.
struct NotifiedApp: Sendable {
    /// The process id.
    let pid: Int32
    /// The launch date, when the system recorded one.
    let launchDate: Date?
    /// The bundle identifier, when the app has one.
    let bundleIdentifier: String?

    /// Copies the identity of `app`.
    ///
    /// - Parameter app: A running or just-terminated application.
    init(_ app: NSRunningApplication) {
        pid = app.processIdentifier
        launchDate = app.launchDate
        bundleIdentifier = app.bundleIdentifier
    }
}
