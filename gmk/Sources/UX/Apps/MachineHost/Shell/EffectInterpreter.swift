import AppKit
import CoreGraphics
import Foundation

/// Carries out the reducer's effects: the only place an effect touches the real world.
///
/// Frame effects are converted to accessibility coordinates here and handed to the owning app's thread
/// without waiting; store effects go to the mirror writer's next tick.
@MainActor
final class EffectInterpreter {
    /// The longest one app may hold the quit path.
    static let perAppQuitBound: TimeInterval = 0.25

    /// Where the per-app threads send observed events.
    private let sink: WMEventSink
    /// The global hotkey registrar.
    private let hotkeys: CarbonHotkeyCenter
    /// The debounced mirror writer.
    private let mirror: MirrorWriter
    /// One accessibility thread per observed app, by pid.
    private var threads: [Int32: AxAppThread] = [:]
    /// The primary display's frame height, which anchors the coordinate flip.
    private var primaryHeight: CGFloat

    /// The chords the last `registerHotkeys` could not register, with Carbon's status for each.
    private(set) var hotkeyConflicts: [HotkeyBinding: OSStatus] = [:]

    /// Creates an interpreter over the given registrar and writer.
    ///
    /// - Parameters:
    ///   - sink: Where the per-app threads send observed events.
    ///   - hotkeys: The global hotkey registrar.
    ///   - mirror: The debounced mirror writer.
    ///   - primaryHeight: The primary display's frame height.
    init(sink: @escaping WMEventSink, hotkeys: CarbonHotkeyCenter, mirror: MirrorWriter, primaryHeight: CGFloat) {
        self.sink = sink
        self.hotkeys = hotkeys
        self.mirror = mirror
        self.primaryHeight = primaryHeight
    }

    /// The pids of every app with a running accessibility thread.
    var attachedPids: Set<Int32> { Set(threads.keys) }

    /// Starts observing an app; this app's own pid and an already attached launch are ignored.
    ///
    /// - Parameters:
    ///   - pid: The process id.
    ///   - launchedAt: The canonical launch date (see `LaunchStamp.canonical`).
    /// - Returns: True when a new thread was started.
    @discardableResult
    func attach(pid: Int32, launchedAt: Date) -> Bool {
        if let existing = threads[pid] {
            guard existing.launchedAt != launchedAt else { return false }
            existing.stop()
        }
        guard let thread = AxAppThread(pid: pid, launchedAt: launchedAt, primaryHeight: primaryHeight, sink: sink)
        else { return false }
        threads[pid] = thread
        return true
    }

    /// Stops observing an app.
    ///
    /// - Parameter pid: The process id.
    func detach(pid: Int32) {
        threads.removeValue(forKey: pid)?.stop()
    }

    /// Stops observing every app.
    func detachAll() {
        threads.values.forEach { $0.stop() }
        threads = [:]
    }

    /// Updates the primary display height on every thread.
    ///
    /// - Parameter height: The primary display's frame height.
    func setPrimaryHeight(_ height: CGFloat) {
        primaryHeight = height
        threads.values.forEach { $0.setPrimaryHeight(height) }
    }

    /// Asks an app's thread to emit `windowFocused` for its focused window.
    ///
    /// - Parameter pid: The process id.
    func reportFocusedWindow(pid: Int32) {
        threads[pid]?.reportFocusedWindow()
    }

    /// Every window every observed app reports now, read in parallel on the apps' threads.
    ///
    /// An app that did not answer contributes no windows and is left out of `answered`.
    ///
    /// - Returns: The observed windows in Cocoa coordinates, and the pids that answered.
    func snapshotAll() async -> (observed: [ObservedWindow], answered: Set<Int32>) {
        let threads = Array(self.threads.values)
        return await withTaskGroup(of: (pid: Int32, windows: [ObservedWindow]?).self) { group in
            threads.forEach { thread in group.addTask { (thread.pid, await thread.snapshotWindows()) } }
            var observed: [ObservedWindow] = []
            var answered: Set<Int32> = []
            for await reply in group {
                guard let windows = reply.windows else { continue }
                answered.insert(reply.pid)
                observed.append(contentsOf: windows)
            }
            return (observed, answered)
        }
    }

    /// Carries out `effects` in order without waiting on any app.
    ///
    /// - Parameter effects: The reducer's effects.
    func interpret(_ effects: [WMEffect]) {
        effects.forEach(interpret)
    }

    /// Carries out the window and hotkey effects of the quit path, waiting on the writes within bounds.
    ///
    /// Store effects are skipped: nothing on the termination path writes. Every app's frames go to its own
    /// thread at once, so the wait costs the slowest app, bounded by `perAppQuitBound` per window of the
    /// largest batch and never past `deadline`.
    ///
    /// - Parameters:
    ///   - effects: The reducer's effects, usually from `.disable`.
    ///   - deadline: The most seconds the whole call may take.
    func interpretSynchronously(_ effects: [WMEffect], deadline: TimeInterval) {
        for case .unregisterAllHotkeys in effects { hotkeys.unregisterAll() }
        let batches = frameBatches(effects)
        guard let largest = batches.map(\.writes.count).max() else { return }
        let group = DispatchGroup()
        batches.forEach { $0.thread.setFrames($0.writes, leaving: group) }
        let bound = min(deadline, Self.perAppQuitBound * Double(largest))
        _ = group.wait(timeout: .now() + bound)
    }

    /// Carries out `effects` and returns once every app has finished its frame writes, with no deadline.
    ///
    /// For paths where nothing is terminating, so no window is left where a deadline cut it off.
    ///
    /// - Parameter effects: The reducer's effects, usually from `.disable`.
    func interpretFully(_ effects: [WMEffect]) async {
        let batches = frameBatches(effects)
        for effect in effects where Self.frameTarget(effect) == nil { interpret(effect) }
        await withTaskGroup(of: Void.self) { group in
            batches.forEach { batch in group.addTask { await batch.thread.setFrames(batch.writes) } }
        }
    }

    /// Carries out one effect without waiting.
    ///
    /// - Parameter effect: The effect.
    private func interpret(_ effect: WMEffect) {
        switch effect {
        case let .setFrame(key, rect), let .park(key, rect), let .unpark(key, rect):
            let axRect = AxCoordinates.cocoaToAx(rect, primaryHeight: primaryHeight)
            thread(for: key)?.setFrame(cgWindowId: key.cgWindowId, axRect: axRect)
        case .focus(let key):
            thread(for: key)?.focus(cgWindowId: key.cgWindowId)
            NSRunningApplication(processIdentifier: key.pid)?.activate()
        case .registerHotkeys(let bindings):
            hotkeyConflicts = hotkeys.register(bindings)
        case .unregisterAllHotkeys:
            hotkeys.unregisterAll()
            hotkeyConflicts = [:]
        case .mirrorDirty(_, _, let urgent):
            mirror.markDirty(urgent: urgent)
        case let .persistActiveWorkspace(displayKey, workspaceCode):
            mirror.enqueueActive(displayKey: displayKey, workspaceCode: workspaceCode)
        }
    }

    /// The frame writes of `effects`, grouped by owning app in effect order.
    ///
    /// Writes to windows of an unobserved process or a reused pid are dropped.
    ///
    /// - Parameter effects: The reducer's effects.
    /// - Returns: One batch per app with at least one write.
    private func frameBatches(_ effects: [WMEffect]) -> [(thread: AxAppThread, writes: [AxFrameWrite])] {
        var batches: [(thread: AxAppThread, writes: [AxFrameWrite])] = []
        var index: [Int32: Int] = [:]
        for effect in effects {
            guard let (key, rect) = Self.frameTarget(effect), let thread = thread(for: key) else { continue }
            let write = AxFrameWrite(
                cgWindowId: key.cgWindowId,
                axRect: AxCoordinates.cocoaToAx(rect, primaryHeight: primaryHeight)
            )
            if let slot = index[key.pid] {
                batches[slot].writes.append(write)
            } else {
                index[key.pid] = batches.count
                batches.append((thread, [write]))
            }
        }
        return batches
    }

    /// The window and Cocoa frame a frame-writing effect targets.
    ///
    /// - Parameter effect: An effect.
    /// - Returns: The target, or nil when `effect` writes no frame.
    private static func frameTarget(_ effect: WMEffect) -> (WindowKey, CGRect)? {
        switch effect {
        case let .setFrame(key, rect), let .park(key, rect), let .unpark(key, rect):
            return (key, rect)
        default:
            return nil
        }
    }

    /// The thread observing the process that owns `key`, when it is the same launch.
    ///
    /// - Parameter key: A window key.
    /// - Returns: The thread, or nil when the process is not observed or its pid was reused.
    private func thread(for key: WindowKey) -> AxAppThread? {
        guard let thread = threads[key.pid], thread.launchedAt == key.launchedAt else { return nil }
        return thread
    }
}
