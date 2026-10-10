import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Synchronization
import os

/// The shell's route for reducer inputs; always invoked on the main actor.
typealias WMEventSink = @MainActor @Sendable (WMEvent) -> Void

/// One thread per observed app that owns every accessibility call made against that app.
///
/// A hung app blocks only its own thread, for at most the 0.25s messaging timeout per call, so neither the
/// main actor nor the store queue ever waits on it. Observer callbacks run on this thread and hand their
/// events to the main actor; nothing here touches the Store.
final class AxAppThread: Sendable {
    /// The observed process id.
    let pid: Int32
    /// The observed process's launch date, which disambiguates a reused pid.
    let launchedAt: Date
    /// The observed app's bundle identifier, when it has one.
    let bundleId: String?
    /// True when the observed app runs with a non-regular activation policy.
    let isAccessory: Bool
    /// The seconds an accessibility call may wait on the app before it gives up.
    static let messagingTimeout: Float = 0.25
    /// The seconds a native focus read may take before it counts as unanswered.
    static let focusReadTimeout: TimeInterval = 0.5
    /// The notifications subscribed on the application element.
    private static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
    /// The notifications subscribed on every window element.
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    // Both touched only on this app's thread; confinement, not a lock, is what makes them safe.
    nonisolated(unsafe) private let app: AXUIElement
    nonisolated(unsafe) private var confined = AxAppConfined()
    /// Where observed events go.
    private let sink: WMEventSink
    /// The coordinate anchor and the stop flag, written from the main actor and read on the thread.
    private let flags: Mutex<AxAppFlags>
    /// The newest unwritten frame per window, written from the main actor and drained on the thread.
    private let pending = Mutex(AxPendingFrames())
    /// The log of frame writes, subscriptions, verdicts and snapshot skips for this thread's app.
    private static let log = Logger(subsystem: "rube.GMVibes.wm", category: "ax")
    /// The selector target jobs are delivered through.
    private let port = AxJobPort()
    // Thread is not Sendable, but performSelector(onThread:) is thread-safe and the reference never changes.
    nonisolated(unsafe) private let thread: Thread

    /// Starts a thread for `pid` and subscribes to its window notifications there.
    ///
    /// - Parameters:
    ///   - pid: The process to observe; this app's own pid yields nil.
    ///   - launchedAt: The process's launch date.
    ///   - bundleId: The app's bundle identifier, when it has one.
    ///   - isAccessory: True when the app runs with a non-regular activation policy.
    ///   - primaryHeight: The primary display's frame height, for the coordinate flip.
    ///   - sink: Where observed events go.
    init?(
        pid: Int32,
        launchedAt: Date,
        bundleId: String?,
        isAccessory: Bool,
        primaryHeight: CGFloat,
        sink: @escaping WMEventSink
    ) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        self.pid = pid
        self.launchedAt = launchedAt
        self.bundleId = bundleId
        self.isAccessory = isAccessory
        self.sink = sink
        self.app = AXUIElementCreateApplication(pid)
        self.flags = Mutex(AxAppFlags(primaryHeight: primaryHeight))
        self.thread = Thread { AxAppThread.runUntilCancelled() }
        thread.name = "gm_machine_host.ax.\(pid)"
        thread.start()
        perform { $0.attach() }
    }

    /// Updates the primary display height that anchors the flip into Cocoa coordinates.
    ///
    /// - Parameter height: The primary display's frame height.
    func setPrimaryHeight(_ height: CGFloat) {
        flags.withLock { $0.primaryHeight = height }
    }

    /// Moves and sizes a window, asynchronously on this app's thread; only the newest request is written.
    ///
    /// A request replaces any unwritten one for the same window, and one job writes every pending frame.
    ///
    /// - Parameters:
    ///   - cgWindowId: The window to move.
    ///   - axRect: The target frame in accessibility coordinates.
    func setFrame(cgWindowId: UInt32, axRect: CGRect) {
        let schedule = pending.withLock { pending in
            pending.frames[cgWindowId] = axRect
            defer { pending.scheduled = true }
            return !pending.scheduled
        }
        if schedule { perform { $0.applyPendingFrames() } }
    }

    /// Moves and sizes a window and waits for the write, for the quit path only.
    ///
    /// - Parameters:
    ///   - cgWindowId: The window to move.
    ///   - axRect: The target frame in accessibility coordinates.
    ///   - timeout: The longest the caller blocks.
    /// - Returns: True when the write finished within `timeout`.
    func setFrameAndWait(cgWindowId: UInt32, axRect: CGRect, timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        enqueue {
            $0.applyFrame(cgWindowId: cgWindowId, axRect: axRect)
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success
    }

    /// Raises a window, gives it keyboard focus within its app, then activates the app.
    ///
    /// Activation follows the raise on the same thread, so the app comes forward with this window on top.
    /// The job is queued before this returns, so it keeps its place among the jobs around it.
    ///
    /// - Parameters:
    ///   - cgWindowId: The window to focus.
    ///   - timeout: The longest the returned task waits for the job before answering `.timedOut`.
    /// - Returns: A task answering how the focus job ended, whichever of the job or the timeout comes first.
    func focus(cgWindowId: UInt32, landingWithin timeout: TimeInterval) -> Task<FocusLanding, Never> {
        let (stream, landing) = AsyncStream.makeStream(of: FocusLanding.self, bufferingPolicy: .bufferingOldest(1))
        enqueue { thread in
            defer { landing.finish() }
            guard !thread.flags.withLock(\.stopped), let element = thread.element(for: cgWindowId) else {
                landing.yield(.dropped)
                return
            }
            AxWindow.raise(element)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: thread.pid)?.activate(options: .activateIgnoringOtherApps)
            landing.yield(.landed)
        }
        let pid = self.pid
        DispatchQueue.global()
            .asyncAfter(deadline: .now() + timeout) {
                defer { landing.finish() }
                guard case .enqueued = landing.yield(.timedOut) else { return }
                Self.log.notice("focus timed out pid=\(pid, privacy: .public) wid=\(cgWindowId, privacy: .public)")
            }
        return Task {
            for await outcome in stream { return outcome }
            return .timedOut
        }
    }

    /// Orders a window to the front of its app without activating the app or changing its main window.
    ///
    /// - Parameter cgWindowId: The window to raise.
    func raise(cgWindowId: UInt32) {
        perform { thread in
            guard let element = thread.element(for: cgWindowId) else { return }
            AxWindow.raiseOnly(element)
        }
    }

    /// Reads the app's focused window, bounded by `focusReadTimeout`.
    ///
    /// - Returns: The focused window, `.unmanaged` when the app reports none or one with no id, or
    ///   `.unanswered` when the thread is stopped or the read timed out.
    func focusedWindowRead() async -> NativeFocusRead {
        await withCheckedContinuation { continuation in
            let reply = AxOneShot<NativeFocusRead>(continuation)
            enqueue { thread in
                guard !thread.flags.withLock(\.stopped) else { return reply.resume(.unanswered) }
                guard let element = AxWindow.focusedWindow(of: thread.app), let id = thread.track(element) else {
                    return reply.resume(.unmanaged)
                }
                reply.resume(.window(thread.key(id)))
            }
            DispatchQueue.global()
                .asyncAfter(deadline: .now() + Self.focusReadTimeout) {
                    reply.resume(.unanswered)
                }
        }
    }

    /// Writes `writes` in order on this app's thread and leaves `group` when the last one finishes.
    ///
    /// The group is entered here; a job delivered to a thread that already stopped still runs.
    ///
    /// - Parameters:
    ///   - writes: The frames to write.
    ///   - group: The group the caller waits on.
    func setFrames(_ writes: [AxFrameWrite], leaving group: DispatchGroup) {
        group.enter()
        enqueue { thread in
            writes.forEach { thread.applyFrame(cgWindowId: $0.cgWindowId, axRect: $0.axRect) }
            group.leave()
        }
    }

    /// Writes `writes` in order on this app's thread and returns when the last one finishes.
    ///
    /// Each write is bounded only by the per-call messaging timeout.
    ///
    /// - Parameter writes: The frames to write.
    func setFrames(_ writes: [AxFrameWrite]) async {
        await withCheckedContinuation { continuation in
            enqueue { thread in
                writes.forEach { thread.applyFrame(cgWindowId: $0.cgWindowId, axRect: $0.axRect) }
                continuation.resume()
            }
        }
    }

    /// Reads the app's focused window and emits `windowFocused` for it.
    func reportFocusedWindow() {
        perform { thread in
            guard let element = AxWindow.focusedWindow(of: thread.app), let id = thread.track(element) else { return }
            thread.emit(.windowFocused(thread.key(id)))
        }
    }

    /// Every window the app reports now, re-read on this app's thread.
    ///
    /// Answers nil when the thread is stopped, the app errs or times out on the window list, or the whole
    /// read takes over one second. A window whose frame does not read is listed as unreadable, not dropped.
    ///
    /// - Returns: The observed windows in Cocoa coordinates and the unreadable ids, or nil when the app did
    ///   not answer.
    func snapshotWindows() async -> AxSnapshot? {
        await withCheckedContinuation { continuation in
            let reply = AxOneShot<AxSnapshot?>(continuation)
            enqueue { reply.resume($0.flags.withLock(\.stopped) ? nil : $0.snapshot()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { reply.resume(nil) }
        }
    }

    /// Removes every notification and ends the thread; later jobs are dropped.
    func stop() {
        flags.withLock { $0.stopped = true }
        enqueue { $0.detach() }
    }

    // MARK: - On the app's thread

    /// Sets the timeout, installs the observer on this thread's run loop and tracks the existing windows.
    ///
    /// An observer that cannot be created, or a notification that fails transiently, is retried at the start
    /// of every snapshot; a notification the app refuses outright is never asked for again.
    private func attach() {
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard createObserver() else { return }
        subscribeApp()
        AxWindow.windows(of: app)?.forEach { track($0) }
    }

    /// Creates the app's observer and adds its run-loop source to this thread.
    ///
    /// - Returns: True when the observer was created.
    private func createObserver() -> Bool {
        var created: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &created)
        guard result == .success, let observer = created else {
            Self.log.notice(
                "observer failed pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) err=\(result.rawValue, privacy: .public)"
            )
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        confined.observer = observer
        return true
    }

    /// Adds every application-level notification neither held nor refused.
    ///
    /// - Returns: The notification names added by this call.
    @discardableResult
    private func subscribeApp() -> [String] {
        guard let observer = confined.observer else { return [] }
        var added: [String] = []
        for name in Self.appNotifications
        where !confined.appSubscribed.contains(name) && !confined.appRefused.contains(name) {
            switch subscribe(observer, app, name, wid: nil) {
            case .held: added.append(name)
            case .refused: confined.appRefused.insert(name)
            case .failed: continue
            }
        }
        confined.appSubscribed.formUnion(added)
        return added
    }

    /// Adds one notification on `element`, logging a refusal at notice and a transient failure at debug.
    ///
    /// - Parameters:
    ///   - observer: The app's observer.
    ///   - element: The application or window element.
    ///   - name: The notification name.
    ///   - wid: The window id when `element` is a window, nil for the application.
    /// - Returns: Whether the notification is held, refused for good, or worth asking for again.
    private func subscribe(
        _ observer: AXObserver,
        _ element: AXUIElement,
        _ name: String,
        wid: UInt32?
    )
        -> AxSubscribeOutcome
    {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
        let outcome = AxSubscribeOutcome(result)
        let window = wid.map(String.init) ?? "-"
        switch outcome {
        case .held:
            break
        case .refused:
            Self.log.notice(
                "subscribe refused pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) wid=\(window, privacy: .public) note=\(name, privacy: .public) err=\(result.rawValue, privacy: .public)"
            )
        case .failed:
            Self.log.debug(
                "subscribe failed pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) wid=\(window, privacy: .public) note=\(name, privacy: .public) err=\(result.rawValue, privacy: .public)"
            )
        }
        return outcome
    }

    /// Re-creates a missing observer and re-adds every application-level notification not yet held.
    private func retrySubscriptions() {
        let hadObserver = confined.observer != nil
        guard hadObserver || createObserver() else { return }
        let added = subscribeApp()
        guard !hadObserver || !added.isEmpty else { return }
        Self.log.notice(
            "subscribe recovered pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) observer=\(!hadObserver, privacy: .public) notes=\(added.joined(separator: ","), privacy: .public)"
        )
    }

    /// Removes the observer from this thread's run loop and cancels the thread.
    private func detach() {
        if let observer = confined.observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        confined = AxAppConfined()
        Thread.current.cancel()
    }

    /// Dispatches one observer notification.
    ///
    /// - Parameters:
    ///   - notification: The accessibility notification name.
    ///   - element: The element it concerns.
    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            guard let id = track(element), let observed = observe(element, id: id) else { return }
            emit(
                .windowCreated(
                    observed.key,
                    frame: observed.frame,
                    classification: observed.classification,
                    title: observed.title,
                    isMinimized: observed.isMinimized
                )
            )
        case kAXFocusedWindowChangedNotification:
            guard let id = track(element) else { return }
            emit(.windowFocused(key(id)))
        case kAXUIElementDestroyedNotification:
            guard let id = forget(element) else { return }
            emit(.windowDestroyed(key(id)))
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = confined.ids[element], let frame = cocoaFrame(element) else { return }
            let window = key(id)
            emit(
                notification == kAXWindowMovedNotification
                    ? .windowMoved(window, frame) : .windowResized(window, frame)
            )
        case kAXWindowMiniaturizedNotification:
            guard let id = confined.ids[element] else { return }
            emit(.windowMinimized(key(id)))
        case kAXWindowDeminiaturizedNotification:
            guard let id = confined.ids[element], let observed = observe(element, id: id) else { return }
            emit(.windowDeminimized(observed.key, frame: observed.frame, classification: observed.classification))
        default:
            return
        }
    }

    /// Records a window element and adds each per-window notification neither held nor refused.
    ///
    /// - Parameter element: A window element.
    /// - Returns: The window id, or nil when the app did not answer.
    @discardableResult
    private func track(_ element: AXUIElement) -> UInt32? {
        guard let id = AxWindow.windowId(element) else { return nil }
        if confined.windows[id] == nil { AXUIElementSetMessagingTimeout(element, Self.messagingTimeout) }
        confined.windows[id] = element
        confined.ids[element] = id
        guard let observer = confined.observer else { return id }
        var held = confined.windowSubscribed[id, default: []]
        var refused = confined.windowRefused[id, default: []]
        guard held.count + refused.count < Self.windowNotifications.count else { return id }
        for name in Self.windowNotifications where !held.contains(name) && !refused.contains(name) {
            switch subscribe(observer, element, name, wid: id) {
            case .held: held.insert(name)
            case .refused: refused.insert(name)
            case .failed: continue
            }
        }
        confined.windowSubscribed[id] = held
        confined.windowRefused[id] = refused
        return id
    }

    /// Drops a window element from the maps.
    ///
    /// - Parameter element: A window element, possibly already destroyed.
    /// - Returns: The window id it carried, or nil when it was not tracked.
    private func forget(_ element: AXUIElement) -> UInt32? {
        guard let id = confined.ids.removeValue(forKey: element) else { return nil }
        forget(id: id)
        return id
    }

    /// Drops every record of the window `id` except its element-to-id entry.
    ///
    /// - Parameter id: The window id.
    private func forget(id: UInt32) {
        confined.windows[id] = nil
        confined.windowSubscribed[id] = nil
        confined.windowRefused[id] = nil
        confined.verdicts[id] = nil
    }

    /// The tracked element for `cgWindowId`, re-enumerating the app's windows once when it is unknown.
    ///
    /// - Parameter cgWindowId: The window id.
    /// - Returns: The element, or nil when the app does not report the window.
    private func element(for cgWindowId: UInt32) -> AXUIElement? {
        if let element = confined.windows[cgWindowId] { return element }
        AxWindow.windows(of: app)?.forEach { track($0) }
        return confined.windows[cgWindowId]
    }

    /// Writes a frame to a window.
    ///
    /// - Parameters:
    ///   - cgWindowId: The window to move.
    ///   - axRect: The target frame in accessibility coordinates.
    private func applyFrame(cgWindowId: UInt32, axRect: CGRect) {
        guard let element = element(for: cgWindowId) else { return }
        Self.log.debug("setFrame pid=\(self.pid) wid=\(cgWindowId) ax=\(String(describing: axRect), privacy: .public)")
        AxWindow.setFrame(element, axRect, app: app)
    }

    /// Writes every pending frame, the newest per window, with enhanced user interface off once for all.
    private func applyPendingFrames() {
        let frames = pending.withLock { pending in
            defer { pending = AxPendingFrames() }
            return pending.frames
        }
        let writes = frames.compactMap { id, rect in element(for: id).map { (id, $0, rect) } }
        guard !writes.isEmpty else { return }
        AxWindow.withEnhancedUserInterfaceOff(app) {
            for (id, element, rect) in writes {
                Self.log.debug("setFrame pid=\(self.pid) wid=\(id) ax=\(String(describing: rect), privacy: .public)")
                AxWindow.writeFrame(element, rect)
            }
        }
    }

    /// Every window the app reports now, after retrying any missing subscription.
    ///
    /// A window with no id is skipped; one whose frame does not read is listed as unreadable. Tracked windows
    /// that neither read nor are listed unreadable are forgotten.
    ///
    /// - Returns: The observed windows in Cocoa coordinates and the unreadable ids, or nil when the app did
    ///   not answer the window list.
    private func snapshot() -> AxSnapshot? {
        retrySubscriptions()
        guard let elements = AxWindow.windows(of: app) else { return nil }
        var observed: [ObservedWindow] = []
        var unreadable: [UInt32] = []
        var withoutId = 0
        for element in elements {
            guard let id = track(element) else {
                withoutId += 1
                continue
            }
            guard let window = observe(element, id: id) else {
                unreadable.append(id)
                continue
            }
            observed.append(window)
        }
        if withoutId > 0 || !unreadable.isEmpty {
            let ids = unreadable.map(String.init).joined(separator: ",")
            Self.log.notice(
                "snapshot skipped pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) noId=\(withoutId, privacy: .public) unreadable=\(unreadable.count, privacy: .public) ids=\(ids, privacy: .public)"
            )
        }
        let live = Set(observed.map(\.key.cgWindowId)).union(unreadable)
        for (id, element) in confined.windows where !live.contains(id) {
            forget(id: id)
            confined.ids[element] = nil
        }
        return AxSnapshot(observed: observed, unreadable: unreadable)
    }

    /// Reads one window's frame, classification, title and minimized state.
    ///
    /// - Parameters:
    ///   - element: The window element.
    ///   - id: Its window id.
    /// - Returns: The observation, or nil when the frame could not be read.
    private func observe(_ element: AXUIElement, id: UInt32) -> ObservedWindow? {
        guard let frame = cocoaFrame(element) else { return nil }
        return ObservedWindow(
            key: key(id),
            frame: frame,
            classification: classify(element, id: id),
            title: AxWindow.title(element),
            isMinimized: AxWindow.isMinimized(element)
        )
    }

    /// The window's class: a cached `.tiled` verdict, else a fresh classification of its facts.
    ///
    /// Every verdict is remembered, but only `.tiled` is reused, so a float or popup is re-tested on every
    /// read. A verdict that first appears or changes is logged.
    ///
    /// - Parameters:
    ///   - element: The window element.
    ///   - id: Its window id.
    /// - Returns: The window's class.
    private func classify(_ element: AXUIElement, id: UInt32) -> WindowClass {
        let previous = confined.verdicts[id]
        if previous == .tiled { return .tiled }
        let facts = AxWindow.facts(element, app: app, cgWindowId: id, bundleId: bundleId, isAccessoryApp: isAccessory)
        let verdict = WindowClassifier.classify(facts)
        confined.verdicts[id] = verdict
        if verdict != previous {
            let button = "\(facts.hasFullscreenButton)/\(facts.fullscreenButtonEnabled)"
            Self.log.notice(
                "classify pid=\(self.pid, privacy: .public) bundle=\(self.bundleId ?? "-", privacy: .public) wid=\(id, privacy: .public) role=\(facts.role ?? "-", privacy: .public) subrole=\(facts.subrole ?? "-", privacy: .public) fs=\(button, privacy: .public) -> \(String(describing: verdict), privacy: .public)"
            )
        }
        return verdict
    }

    /// A window's frame in Cocoa coordinates.
    ///
    /// - Parameter element: The window element.
    /// - Returns: The frame, or nil when the app did not answer.
    private func cocoaFrame(_ element: AXUIElement) -> CGRect? {
        guard let axFrame = AxWindow.frame(element) else { return nil }
        return AxCoordinates.axToCocoa(axFrame, primaryHeight: flags.withLock(\.primaryHeight))
    }

    /// The reducer key for one of this app's windows.
    ///
    /// - Parameter cgWindowId: The window id.
    /// - Returns: The key.
    private func key(_ cgWindowId: UInt32) -> WindowKey {
        WindowKey(pid: pid, launchedAt: launchedAt, cgWindowId: cgWindowId)
    }

    /// Hands an event to the sink on the main actor, in the order this thread emitted it.
    ///
    /// - Parameter event: The event.
    private func emit(_ event: WMEvent) {
        let sink = self.sink
        DispatchQueue.main.async { MainActor.assumeIsolated { sink(event) } }
    }

    // MARK: - Delivery

    /// Runs `job` on this app's thread unless the thread has been stopped.
    ///
    /// - Parameter job: The work, handed this thread object.
    private func perform(_ job: @escaping @Sendable (AxAppThread) -> Void) {
        enqueue { thread in
            guard !thread.flags.withLock(\.stopped) else { return }
            job(thread)
        }
    }

    /// Runs `job` on this app's thread, stopped or not, as long as the thread still runs.
    ///
    /// - Parameter job: The work, handed this thread object.
    private func enqueue(_ job: @escaping @Sendable (AxAppThread) -> Void) {
        let box = AxJob { [self] in job(self) }
        port.perform(#selector(AxJobPort.run(_:)), on: thread, with: box, waitUntilDone: false)
    }

    /// The thread body: serves delivered jobs and observer callbacks until cancelled.
    private static func runUntilCancelled() {
        RunLoop.current.add(NSMachPort(), forMode: .default)
        while !Thread.current.isCancelled {
            _ = RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }
}

/// The observer callback: routes a notification to the `AxAppThread` passed as its refcon.
private let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<AxAppThread>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

/// The accessibility state of an `AxAppThread`, confined to that app's thread.
private struct AxAppConfined {
    /// Tracked window elements by window id.
    var windows: [UInt32: AXUIElement] = [:]
    /// Window ids by element, for notifications about elements that cannot be queried.
    var ids: [AXUIElement: UInt32] = [:]
    /// The app's observer while attached.
    var observer: AXObserver?
    /// The application-level notifications the observer holds.
    var appSubscribed: Set<String> = []
    /// The application-level notifications the app refused for good.
    var appRefused: Set<String> = []
    /// The per-window notifications the observer holds, by window id.
    var windowSubscribed: [UInt32: Set<String>] = [:]
    /// The per-window notifications the window refused for good, by window id.
    var windowRefused: [UInt32: Set<String>] = [:]
    /// The last classifier verdict per window id.
    var verdicts: [UInt32: WindowClass] = [:]
}

/// How one notification subscription attempt ended.
private enum AxSubscribeOutcome {
    /// The observer holds the notification, newly or already.
    case held
    /// The element can never deliver it; it is not asked for again.
    case refused
    /// A transient failure; it is asked for again on the next snapshot.
    case failed

    /// Sorts an `AXObserverAddNotification` result.
    ///
    /// - Parameter result: The accessibility error the call returned.
    init(_ result: AXError) {
        switch result {
        case .success, .notificationAlreadyRegistered: self = .held
        case .cannotComplete, .apiDisabled, .failure: self = .failed
        default: self = .refused
        }
    }
}

/// How a focus job handed to an `AxAppThread` ended.
enum FocusLanding: Sendable {
    /// The window was raised, focused and its app activated.
    case landed
    /// The thread was stopped or the app does not report the window.
    case dropped
    /// The job had not finished when the caller's timeout passed.
    case timedOut
}

/// One snapshot of an app's windows: those that read, and the ids of those whose frame did not.
struct AxSnapshot: Sendable {
    /// The windows whose frame read, in Cocoa coordinates.
    let observed: [ObservedWindow]
    /// The ids of windows whose id read but whose frame did not.
    let unreadable: [UInt32]
}

/// The part of an `AxAppThread` the main actor writes and the app's thread reads.
private struct AxAppFlags {
    /// The primary display's frame height, for the coordinate flip.
    var primaryHeight: CGFloat
    /// True once `stop()` has been called.
    var stopped = false
}

/// The frames `AxAppThread.setFrame` requested that no job has written yet.
private struct AxPendingFrames {
    /// The newest requested frame per window id, in accessibility coordinates.
    var frames: [UInt32: CGRect] = [:]
    /// True while a job that will write `frames` is queued.
    var scheduled = false
}

/// One unit of work delivered to an `AxAppThread`.
private final class AxJob: NSObject, Sendable {
    /// The work.
    let body: @Sendable () -> Void

    /// Wraps `body` for delivery.
    ///
    /// - Parameter body: The work.
    init(_ body: @escaping @Sendable () -> Void) {
        self.body = body
    }
}

/// The selector target that runs delivered jobs on the receiving thread.
private final class AxJobPort: NSObject, Sendable {
    /// Runs one job.
    ///
    /// - Parameter job: The job.
    @objc func run(_ job: AxJob) {
        job.body()
    }
}

/// One frame write handed to an `AxAppThread`, in accessibility coordinates.
struct AxFrameWrite: Sendable {
    /// The window to move.
    let cgWindowId: UInt32
    /// The target frame in accessibility coordinates.
    let axRect: CGRect
}

/// Resumes a continuation exactly once, from whichever of the job or the timeout answers first.
private final class AxOneShot<Value: Sendable>: Sendable {
    /// The continuation until it is resumed.
    private let continuation: Mutex<CheckedContinuation<Value, Never>?>

    /// Wraps `continuation`.
    ///
    /// - Parameter continuation: The continuation to resume once.
    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = Mutex(continuation)
    }

    /// Resumes with `value` if nothing resumed first.
    ///
    /// - Parameter value: The answer.
    func resume(_ value: Value) {
        continuation.withLock { current in
            current?.resume(returning: value)
            current = nil
        }
    }
}
