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
    /// The seconds an accessibility call may wait on the app before it gives up.
    static let messagingTimeout: Float = 0.25

    // Both touched only on this app's thread; confinement, not a lock, is what makes them safe.
    nonisolated(unsafe) private let app: AXUIElement
    nonisolated(unsafe) private var confined = AxAppConfined()
    /// Where observed events go.
    private let sink: WMEventSink
    /// The coordinate anchor and the stop flag, written from the main actor and read on the thread.
    private let flags: Mutex<AxAppFlags>
    /// The newest unwritten frame per window, written from the main actor and drained on the thread.
    private let pending = Mutex(AxPendingFrames())
    /// The debug log of every frame this thread writes.
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
    ///   - primaryHeight: The primary display's frame height, for the coordinate flip.
    ///   - sink: Where observed events go.
    init?(pid: Int32, launchedAt: Date, primaryHeight: CGFloat, sink: @escaping WMEventSink) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        self.pid = pid
        self.launchedAt = launchedAt
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

    /// Raises a window and gives it keyboard focus within its app.
    ///
    /// - Parameter cgWindowId: The window to focus.
    func focus(cgWindowId: UInt32) {
        perform { thread in
            guard let element = thread.element(for: cgWindowId) else { return }
            AxWindow.raise(element)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
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
    /// Answers nil, never an empty list, when the thread is stopped, the app errs or times out on any read,
    /// or the whole read takes over one second; an empty list means the app answered with no windows.
    ///
    /// - Returns: The observed windows in Cocoa coordinates, or nil when the app did not answer.
    func snapshotWindows() async -> [ObservedWindow]? {
        await withCheckedContinuation { continuation in
            let reply = AxOneShot(continuation)
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
    private func attach() {
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let observer = created else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        confined.observer = observer
        AxWindow.windows(of: app)?.forEach { track($0) }
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
                    title: observed.title
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
        default:
            return
        }
    }

    /// Records a window element and subscribes to its per-window notifications, once.
    ///
    /// - Parameter element: A window element.
    /// - Returns: The window id, or nil when the app did not answer.
    @discardableResult
    private func track(_ element: AXUIElement) -> UInt32? {
        guard let id = AxWindow.windowId(element) else { return nil }
        let known = confined.windows[id] != nil
        confined.windows[id] = element
        confined.ids[element] = id
        guard !known, let observer = confined.observer else { return id }
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        return id
    }

    /// Drops a window element from the maps.
    ///
    /// - Parameter element: A window element, possibly already destroyed.
    /// - Returns: The window id it carried, or nil when it was not tracked.
    private func forget(_ element: AXUIElement) -> UInt32? {
        guard let id = confined.ids.removeValue(forKey: element) else { return nil }
        confined.windows[id] = nil
        return id
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

    /// Every window the app reports now; forgets tracked windows it does not report.
    ///
    /// A window whose id or frame cannot be read makes the whole snapshot unanswered rather than partial.
    ///
    /// - Returns: The observed windows in Cocoa coordinates, or nil when the app did not answer.
    private func snapshot() -> [ObservedWindow]? {
        guard let elements = AxWindow.windows(of: app) else { return nil }
        var observed: [ObservedWindow] = []
        for element in elements {
            guard let id = track(element), let window = observe(element, id: id) else { return nil }
            observed.append(window)
        }
        let live = Set(observed.map(\.key.cgWindowId))
        for (id, element) in confined.windows where !live.contains(id) {
            confined.windows[id] = nil
            confined.ids[element] = nil
        }
        return observed
    }

    /// Reads one window's frame, classification and title.
    ///
    /// - Parameters:
    ///   - element: The window element.
    ///   - id: Its window id.
    /// - Returns: The observation, or nil when the frame could not be read.
    private func observe(_ element: AXUIElement, id: UInt32) -> ObservedWindow? {
        guard let frame = cocoaFrame(element) else { return nil }
        let classification = WindowClassifier.classify(
            role: AxWindow.role(element),
            subrole: AxWindow.subrole(element),
            isMinimized: AxWindow.isMinimized(element),
            isFullscreen: AxWindow.isFullscreen(element)
        )
        return ObservedWindow(
            key: key(id),
            frame: frame,
            classification: classification,
            title: AxWindow.title(element)
        )
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
private final class AxOneShot: Sendable {
    /// The continuation until it is resumed.
    private let continuation: Mutex<CheckedContinuation<[ObservedWindow]?, Never>?>

    /// Wraps `continuation`.
    ///
    /// - Parameter continuation: The continuation to resume once.
    init(_ continuation: CheckedContinuation<[ObservedWindow]?, Never>) {
        self.continuation = Mutex(continuation)
    }

    /// Resumes with `windows` if nothing resumed first.
    ///
    /// - Parameter windows: The answer, or nil for no answer.
    func resume(_ windows: [ObservedWindow]?) {
        continuation.withLock { current in
            current?.resume(returning: windows)
            current = nil
        }
    }
}
