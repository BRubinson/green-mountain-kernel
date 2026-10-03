import AppKit
import CoreGraphics
import Foundation
import Observation
import os

/// The app-lifetime owner of the machine host: enable and disable, launch recovery and the quit restore.
///
/// Every store call goes through `GMCCDaemonService`; the reducer runs on the main actor and the interpreter
/// carries out its effects. A second app copy never reaches `boot()`. With the flag off nothing observes an
/// app, registers a hotkey or holds the machine lock.
@MainActor
@Observable
final class MachineHostService {
    /// Where the window manager stands.
    enum Status: Equatable, Sendable {
        /// Window management is off: no observers, no hotkeys, no lock.
        case off
        /// Taking the machine-wide lock and syncing the connected displays.
        case acquiringLock
        /// Another root's app manages this machine's windows; the lock is retried until it frees.
        case managedBy(root: String)
        /// Another window manager is running; management starts once it quits.
        case otherManagerRunning
        /// Waiting for the Accessibility grant; no lock is held.
        case notTrusted
        /// Managing windows; `conflicts` are chords another app already holds.
        case running(conflicts: [HotkeyBinding])
        /// Returning every window to view.
        case stopping
        /// A store or identity read failed; the message says which.
        case failed(String)
    }

    /// The seconds the quit path allows for returning windows to view.
    static let restoreDeadline: TimeInterval = 1.5
    /// The seconds between attempts to take a lock another root holds.
    static let lockRetryInterval: TimeInterval = 5
    /// The quiet a new display set must hold before it is synced and mints a workstation.
    static let displaySettleDelay: Duration = .milliseconds(750)
    /// The bundle id of the window manager that must not run beside this one.
    static let otherManagerBundleId = "bobko.aerospace"
    /// The debug log of every reducer event and the effects it produced.
    private static let sinkLog = Logger(subsystem: "rube.GMVibes.wm", category: "sink")
    /// The debug log of every live reorder a mouse drag made.
    private static let dragLog = Logger(subsystem: "rube.GMVibes.wm", category: "drag")

    /// Where the window manager stands.
    private(set) var status: Status = .off
    /// The machine's rows as last read.
    private(set) var snapshot: MachineHostSnapshotRow?
    /// The last failed configuration edit, shown in the scene.
    private(set) var lastError: String?
    /// Bumped whenever the mirror writer changes the store, so an open scene re-reads.
    private(set) var revision = 0
    /// Whether this app holds the Accessibility grant.
    let trust = AccessibilityTrust()

    @ObservationIgnored private let service = GMCCDaemonService.shared
    @ObservationIgnored private let lock = MachineHostLock()
    @ObservationIgnored private var state = WMState()
    @ObservationIgnored private var hotkeys: CarbonHotkeyCenter?
    @ObservationIgnored private var mirror: MirrorWriter?
    @ObservationIgnored private var interpreter: EffectInterpreter?
    @ObservationIgnored private var observer: AppLifecycleObserver?
    @ObservationIgnored private var trustWait: Task<Void, Never>?
    @ObservationIgnored private var lockRetry: Task<Void, Never>?
    @ObservationIgnored private var displaySettle: Task<Void, Never>?
    @ObservationIgnored private var screenToken: NSObjectProtocol?
    @ObservationIgnored private var connectedSetKey: String?
    @ObservationIgnored private var awaitingDisplay = false
    @ObservationIgnored private var terminationToken: NSObjectProtocol?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var booted = false

    /// Creates an idle service; nothing is read until `boot()`.
    init() {}

    /// True when the machine's window-management flag is set.
    var isFlagOn: Bool { snapshot?.machine.windowManagementEnabled ?? false }

    /// The root this app serves, as written into the machine-wide lock.
    var rootPath: String { Paths.root.path }

    // MARK: - Lifecycle

    /// Records the machine and its displays, then enables if flagged.
    ///
    /// Called once, after the kernel is hosted; later calls do nothing. Nothing here touches another app.
    func boot() async {
        guard !booted else { return }
        booted = true
        guard let hardwareUuid = MachineIdentity.hardwareUuid() else {
            status = .failed("The hardware UUID could not be read.")
            return
        }
        do {
            let machine = try await service.machineHostEnsureMachine(
                hardwareUuid: hardwareUuid,
                name: MachineIdentity.computerName(),
                code: MachineIdentity.code(for: hardwareUuid)
            )
            let readings = DisplayIdentity.current()
            _ = try await service.machineHostSyncDisplays(machineUuid: machine.uuid, displays: readings.map(\.input))
            let loaded = try await service.machineHostLoad(machineUuid: machine.uuid)
            snapshot = loaded
            buildEngine(machineUuid: loaded.machine.uuid)
            watchScreenParameters()
            if loaded.machine.windowManagementEnabled { await enable() }
        } catch {
            status = .failed(Self.message(error))
        }
    }

    /// Sets the window-management flag, then starts managing or returns every window to view.
    ///
    /// - Parameter enabled: The new value of the flag.
    func setEnabled(_ enabled: Bool) async {
        guard let machine = snapshot?.machine else { return }
        do {
            _ = try await service.machineHostSetEnabled(
                machineUuid: machine.uuid,
                enabled: enabled,
                expectedVersion: machine.version
            )
            await reload()
        } catch {
            lastError = Self.message(error)
            return
        }
        if enabled { await enable() } else { await stopRestoring() }
    }

    /// Starts managing once no other manager runs and the Accessibility grant is held.
    ///
    /// Refusals leave a status and a wait behind: a trust poll, or a lock retry every `lockRetryInterval`
    /// plus a retry when the blocking app terminates. The lock is taken only in `start()`.
    func enable() async {
        guard interpreter != nil, !state.enabled, !starting, status != .stopping else { return }
        starting = true
        defer { starting = false }
        if Self.otherManagerIsRunning {
            status = .otherManagerRunning
            waitForBlockerToQuit()
            return
        }
        trust.refresh()
        guard trust.isTrusted else {
            status = .notTrusted
            waitForTrust()
            return
        }
        await start()
    }

    /// Returns every parked window to view and releases hotkeys, observers and the lock.
    ///
    /// Idempotent and synchronous; it performs no store write, so it is safe on the termination path.
    ///
    /// - Parameter deadline: The most seconds the window moves may take.
    func stopRestoringSynchronously(deadline: TimeInterval) {
        stopWaiting()
        if state.enabled {
            status = .stopping
            let effects = WMReducer.reduce(&state, .disable)
            interpreter?.interpretSynchronously(effects, deadline: deadline)
        }
        observer?.stop()
        mirror?.cancel()
        hotkeys?.unregisterAll()
        lock.release()
        status = .off
    }

    /// Re-reads the machine's rows.
    func reload() async {
        guard let machine = snapshot?.machine else { return }
        do {
            snapshot = try await service.machineHostLoad(machineUuid: machine.uuid)
        } catch {
            lastError = Self.message(error)
        }
    }

    /// Returns every parked window to view with no deadline, then releases observers, hotkeys and the lock.
    ///
    /// The mirror keeps running so the cleared pre-park frames reach the store.
    private func stopRestoring() async {
        stopWaiting()
        if state.enabled, let interpreter {
            status = .stopping
            await interpreter.interpretFully(WMReducer.reduce(&state, .disable))
        }
        observer?.stop()
        hotkeys?.unregisterAll()
        lock.release()
        status = .off
    }

    // MARK: - Configuration edits

    /// The chords another app already holds, so they never reach this manager.
    var conflictedChords: [HotkeyBinding] {
        guard case .running(let conflicts) = status else { return [] }
        return conflicts
    }

    /// Places a workspace code on a display of a workstation.
    ///
    /// The configuration is re-applied afterwards while managing.
    ///
    /// - Parameters:
    ///   - code: The workspace code to move.
    ///   - displayUuid: The member display it moves to.
    ///   - workstationUuid: The workstation whose placement changes; nil means the active one.
    func assign(code: String, to displayUuid: String, in workstationUuid: String? = nil) async {
        guard let workstation = workstationUuid ?? snapshot?.activeWorkstationUuid else { return }
        await edit(showsActive: true) {
            _ = try await $0.machineHostAssignWorkspace(
                workstationUuid: workstation,
                code: code,
                displayUuid: displayUuid
            )
        }
    }

    /// Makes a workspace code the visible one on its display.
    ///
    /// The configuration is re-applied afterwards while managing.
    ///
    /// - Parameters:
    ///   - code: The workspace code to show; it must already sit on `displayUuid`.
    ///   - displayUuid: The display it becomes visible on.
    ///   - workstationUuid: The workstation whose active code changes; nil means the active one.
    func setActive(code: String, on displayUuid: String, in workstationUuid: String? = nil) async {
        guard let workstation = workstationUuid ?? snapshot?.activeWorkstationUuid else { return }
        await edit(showsActive: true) {
            _ = try await $0.machineHostSetActiveWorkspace(
                workstationUuid: workstation,
                displayUuid: displayUuid,
                code: code
            )
        }
    }

    /// Why moving a code to a display would be refused, so the screen can disable the move.
    ///
    /// - Parameters:
    ///   - code: The workspace code to move.
    ///   - displayUuid: The display it would move to.
    ///   - workstationUuid: The workstation whose placement would change; nil means the active one.
    /// - Returns: The refusal, or nil when the move is allowed.
    func assignRefusal(code: String, to displayUuid: String, in workstationUuid: String? = nil) -> MachineHostError? {
        guard let snapshot, let workstation = workstationUuid ?? snapshot.activeWorkstationUuid else { return nil }
        let rows = snapshot.workstationWorkspaces.filter { $0.workstationUuid == workstation }
        let placement = Dictionary(rows.map { ($0.workspaceCode, $0.displayUuid) }) { first, _ in first }
        let members = Set(
            snapshot.workstationDisplays.filter { $0.workstationUuid == workstation }.map(\.displayUuid)
        )
        guard let from = placement[code] else { return .unknownWorkspaceCode(code) }
        return MachineHostPlacement.placementRefusal(
            code: code,
            from: from,
            to: displayUuid,
            placement: placement,
            members: members
        )
    }

    /// Renames a workstation.
    ///
    /// - Parameters:
    ///   - workstation: The workstation as last read; its version guards the write.
    ///   - name: The new name.
    func rename(workstation: WorkstationRow, name: String) async {
        await edit {
            _ = try await $0.machineHostRenameWorkstation(
                uuid: workstation.uuid,
                name: name,
                expectedVersion: workstation.version
            )
        }
    }

    /// Forgets a workstation that is not the active one; its set mints afresh if it is seen again.
    ///
    /// - Parameter workstation: The workstation as last read; its version guards the write.
    func forget(workstation: WorkstationRow) async {
        guard workstation.uuid != snapshot?.activeWorkstationUuid else {
            lastError = "The active workstation cannot be forgotten."
            return
        }
        await edit {
            _ = try await $0.machineHostForgetWorkstation(uuid: workstation.uuid, expectedVersion: workstation.version)
        }
    }

    /// Runs one configuration write, re-reads, then sends `.configure` while managing.
    ///
    /// - Parameters:
    ///   - showsActive: True when the write changed which code is visible, so the stored map must be shown.
    ///   - write: The store write.
    private func edit(showsActive: Bool = false, _ write: (GMCCDaemonService) async throws -> Void) async {
        do {
            try await write(service)
            lastError = nil
        } catch {
            lastError = Self.message(error)
        }
        await reload()
        reconfigure(showsActive: showsActive)
    }

    /// Sends `.configure` built from the connected set's workstation rows while managing.
    ///
    /// The stored active map is sent only when `showsActive`; otherwise it is empty, so a rename or a
    /// placement re-read never reverts the codes the user is looking at. Nothing is sent while the connected
    /// set has no recorded workstation.
    ///
    /// - Parameter showsActive: True to show the stored active codes.
    private func reconfigure(showsActive: Bool = false) {
        guard state.enabled, let snapshot, let interpreter,
            let layout = Self.layout(snapshot, workstationUuid: connectedWorkstationUuid(snapshot))
        else { return }
        handle(.configure(strips: strips(placement: layout.placement), active: showsActive ? layout.active : [:]))
        status = .running(conflicts: Array(interpreter.hotkeyConflicts.keys))
    }
}

// MARK: - Waiting

extension MachineHostService {
    /// True when the other window manager has a live process.
    private static var otherManagerIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: otherManagerBundleId)
            .contains { !$0.isTerminated }
    }

    /// The bundle id every root's copy of this app starts with: this bundle's id less `.test` or `.beta`.
    private static var kernelBundlePrefix: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        for suffix in [".test", ".beta"] where id.hasSuffix(suffix) { return String(id.dropLast(suffix.count)) }
        return id
    }

    /// Re-polls the grant every second and retries `enable()` once it is given.
    private func waitForTrust() {
        trustWait?.cancel()
        trustWait = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                trust.refresh()
                guard trust.isTrusted else { continue }
                trustWait = nil
                Task { await self.enable() }
                return
            }
        }
    }

    /// Retries `enable()` every `lockRetryInterval` and whenever an app that may be the blocker quits.
    private func waitForBlockerToQuit() {
        watchTerminations()
        guard lockRetry == nil else { return }
        lockRetry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.lockRetryInterval))
                guard let self, !Task.isCancelled, isFlagOn else { return }
                Task { await self.enable() }
            }
        }
    }

    /// Subscribes to app terminations while a blocker is waited on.
    private func watchTerminations() {
        guard terminationToken == nil else { return }
        terminationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { self?.blockerMayHaveQuit(bundleId: bundleId) }
        }
    }

    /// Retries `enable()` when the terminated app is what the current status waits on.
    ///
    /// - Parameter bundleId: The terminated app's bundle id, when it has one.
    private func blockerMayHaveQuit(bundleId: String?) {
        guard let bundleId, isFlagOn else { return }
        let prefix = Self.kernelBundlePrefix
        switch status {
        case .managedBy where !prefix.isEmpty && bundleId.hasPrefix(prefix),
            .otherManagerRunning where bundleId == Self.otherManagerBundleId:
            Task { await enable() }
        default:
            return
        }
    }

    /// Cancels the trust poll, the lock retry, the termination subscription and the wait for a display.
    private func stopWaiting() {
        trustWait?.cancel()
        trustWait = nil
        lockRetry?.cancel()
        lockRetry = nil
        if let terminationToken { NSWorkspace.shared.notificationCenter.removeObserver(terminationToken) }
        terminationToken = nil
        awaitingDisplay = false
    }
}

// MARK: - Engine

extension MachineHostService {
    /// Creates the hotkey center, mirror writer, interpreter and observer; none of them runs yet.
    ///
    /// - Parameter machineUuid: The machine every mirror row belongs to.
    private func buildEngine(machineUuid: String) {
        let sink: WMEventSink = { [weak self] event in self?.handle(event) }
        let hotkeys = CarbonHotkeyCenter(sink: sink)
        let mirror = MirrorWriter(
            machineUuid: machineUuid,
            image: { [weak self] in self?.mirrorImage() ?? MirrorImage() },
            flush: { [weak self] batch in
                let written = try await GMCCDaemonService.shared.machineHostMirrorFlush(batch)
                await self?.storeChanged()
                return written
            },
            setActive: { [weak self] displayKey, code in
                guard let target = await self?.activeTarget(displayKey: displayKey, workspaceCode: code) else { return }
                _ = try await GMCCDaemonService.shared.machineHostSetActiveWorkspace(
                    workstationUuid: target.workstation,
                    displayUuid: target.display,
                    code: code
                )
                await self?.storeChanged()
            }
        )
        let interpreter = EffectInterpreter(
            sink: sink,
            hotkeys: hotkeys,
            mirror: mirror,
            primaryHeight: DisplayIdentity.primaryHeight()
        )
        self.hotkeys = hotkeys
        self.mirror = mirror
        self.interpreter = interpreter
        observer = AppLifecycleObserver(
            sink: sink,
            interpreter: interpreter,
            mouseHeld: { [weak self] in self?.state.mouseHeld ?? false },
            displaysRead: { [weak self] readings in self?.displaysRead(readings) }
        )
    }

    /// Folds one event into the state and carries out its effects.
    ///
    /// - Parameter event: The reducer input.
    private func handle(_ event: WMEvent) {
        let before = dragStripOrder()
        let effects = WMReducer.reduce(&state, event)
        logReorder(from: before)
        let held = state.mouseHeld
        let drag = state.mouseDrag.map { String($0.window.cgWindowId) } ?? "-"
        Self.sinkLog.debug(
            "\(WMTrace.event(event), privacy: .public) held=\(held) drag=\(drag, privacy: .public) -> \(WMTrace.effects(effects), privacy: .public)"
        )
        interpreter?.interpret(effects)
    }

    /// The dragged window and the order of the strip holding it.
    ///
    /// - Returns: The window and its strip's windows left to right, or nil when no drag is under way.
    private func dragStripOrder() -> (window: WindowKey, order: [WindowKey])? {
        guard let drag = state.mouseDrag, let code = state.stripCode(containing: drag.window),
            let strip = state.workspaces[code]
        else { return nil }
        return (drag.window, strip.columns.map(\.window))
    }

    /// Logs the dragged window's move and the neighbours it displaced when its strip's order changed.
    ///
    /// - Parameter before: The dragged window and its strip's order before the event.
    private func logReorder(from before: (window: WindowKey, order: [WindowKey])?) {
        guard let before, let code = state.stripCode(containing: before.window),
            let after = state.workspaces[code]?.columns.map(\.window), after.count == before.order.count,
            after != before.order, let from = before.order.firstIndex(of: before.window),
            let to = after.firstIndex(of: before.window)
        else { return }
        let neighbours = zip(before.order, after).filter { $0 != $1 && $1 != before.window }
            .map { String($0.1.cgWindowId) }
            .joined(separator: ",")
        Self.dragLog.debug(
            "reorder wid=\(before.window.cgWindowId) \(from)->\(to) neighbours=\(neighbours, privacy: .public)"
        )
    }

    /// Records that the mirror writer changed the store.
    private func storeChanged() {
        revision &+= 1
    }

    /// Takes the lock, reconciles the mirror, recovers parked windows, seeds strips, starts managing.
    ///
    /// Every step after an await re-checks the status, so a disable that lands meanwhile wins.
    private func start() async {
        status = .acquiringLock
        if case .failure(let held) = lock.tryAcquire(root: rootPath) {
            status = .managedBy(root: held.root)
            waitForBlockerToQuit()
            return
        }
        stopWaiting()
        do {
            try await prepareRows()
        } catch {
            status = .failed(Self.message(error))
            lock.release()
            return
        }
        guard status == .acquiringLock, let snapshot, let observer, let interpreter else { return }
        guard snapshot.activeWorkstationUuid != nil else {
            awaitingDisplay = true
            status = .failed("No display is connected; management starts once one is.")
            lock.release()
            return
        }
        observer.start()
        let before = await interpreter.snapshotAll()
        guard status == .acquiringLock else { return }
        let moves = Self.recoveryMoves(observed: before.observed, snapshot: snapshot)
        if !moves.isEmpty { await interpreter.interpretFully(moves.map { WMEffect.setFrame($0.0, $0.1) }) }
        guard status == .acquiringLock else { return }
        let seed = seedState(snapshot, observed: before, recovered: moves)
        apply(snapshot, interpreter: interpreter, seed: seed)
        let after = await interpreter.snapshotAll()
        guard state.enabled else { return }
        handle(.reconcile(observed: after.observed, answered: after.answered))
        if let front = NSWorkspace.shared.frontmostApplication {
            interpreter.reportFocusedWindow(pid: front.processIdentifier)
        }
    }

    /// Retires dead processes' mirror rows, records the connected displays, re-reads, re-seeds the writer.
    ///
    /// The display sync runs at once, so the connected set has its workstation before `.enable`.
    ///
    /// - Throws: `DaemonError` when a store call fails.
    private func prepareRows() async throws {
        guard let machine = snapshot?.machine else { throw DaemonError.notFound }
        let live = Self.liveApps()
            .map {
                AppProcessIdentity(pid: Int64($0.pid), launchedAt: LaunchStamp.string($0.launchedAt))
            }
        _ = try await service.machineHostReconcileMirror(machineUuid: machine.uuid, live: live)
        _ = try await service.machineHostSyncDisplays(
            machineUuid: machine.uuid,
            displays: DisplayIdentity.current().map(\.input)
        )
        let loaded = try await service.machineHostLoad(machineUuid: machine.uuid)
        snapshot = loaded
        mirror?.seed(processes: loaded.appProcesses, windows: loaded.managedWindows)
    }

    /// Sends `.enable` built from the rows and records the hotkey conflicts.
    ///
    /// - Parameters:
    ///   - snapshot: The machine's rows.
    ///   - interpreter: The interpreter that carries out the effects.
    ///   - seed: Columns per workspace code for strips the reducer holds none of.
    private func apply(
        _ snapshot: MachineHostSnapshotRow,
        interpreter: EffectInterpreter,
        seed: [String: [StripColumn]]
    ) {
        let workstation = snapshot.workstations.first { $0.uuid == snapshot.activeWorkstationUuid }
        let layout = Self.layout(snapshot, workstationUuid: workstation?.uuid)
        connectedSetKey = workstation?.displaySetKey
        let event = WMEvent.enable(
            strips: strips(placement: layout?.placement ?? [:], seed: seed),
            active: layout?.active ?? [:]
        )
        interpreter.interpret(WMReducer.reduce(&state, event))
        status = .running(conflicts: Array(interpreter.hotkeyConflicts.keys))
    }

    /// Re-lays out the windows for a new display enumeration at once, then records it, while managing.
    ///
    /// Called by the lifecycle observer just before it sends its own `displaysChanged`, so the reducer
    /// already holds the target strips when that event lands. Before `.enable` it does nothing: the start
    /// path has just synced.
    ///
    /// - Parameter readings: Every connected display.
    private func displaysRead(_ readings: [DisplayReading]) {
        guard state.enabled else { return }
        layOut(readings)
        recordDisplays(readings)
    }

    /// Sends `displaysChanged` and `.configure` for the connected set's target layout in one turn.
    ///
    /// A known set takes its recorded placement and active codes; a new set takes its seed. The same set
    /// as before sends nothing, so a resolution or arrangement change never reverts what is shown.
    ///
    /// - Parameter readings: Every connected display.
    private func layOut(_ readings: [DisplayReading]) {
        guard let snapshot, let target = Self.targetLayout(readings, snapshot: snapshot),
            target.displaySetKey != connectedSetKey
        else { return }
        connectedSetKey = target.displaySetKey
        handle(.displaysChanged(readings.map(\.geom)))
        handle(.configure(strips: strips(placement: target.placement), active: target.active))
    }

    /// Records a display enumeration: at once for a known set, after `displaySettleDelay` for a new one.
    ///
    /// Only a new set waits, so a burst of partial sets during a dock or undock mints no workstation for a
    /// set that never settled. An empty set records nothing.
    ///
    /// - Parameter readings: Every connected display.
    private func recordDisplays(_ readings: [DisplayReading]) {
        guard let snapshot, let target = Self.targetLayout(readings, snapshot: snapshot) else { return }
        let machineUuid = snapshot.machine.uuid
        displaySettle?.cancel()
        displaySettle = nil
        guard target.isNew else {
            Task { [weak self] in await self?.syncDisplays(machineUuid: machineUuid, readings: readings) }
            return
        }
        displaySettle = Task { [weak self] in
            try? await Task.sleep(for: Self.displaySettleDelay)
            guard !Task.isCancelled else { return }
            await self?.mintWorkstation(machineUuid: machineUuid, readings: readings)
        }
    }

    /// Syncs a display set whose workstation is recorded, then re-reads.
    ///
    /// A start that found no display is retried afterwards.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine the displays belong to.
    ///   - readings: Every connected display.
    private func syncDisplays(machineUuid: String, readings: [DisplayReading]) async {
        do {
            _ = try await service.machineHostSyncDisplays(machineUuid: machineUuid, displays: readings.map(\.input))
        } catch {
            lastError = Self.message(error)
            return
        }
        await reload()
        await resumeIfAwaitingDisplay()
    }

    /// Syncs a settled new display set, which mints its workstation, then stores what the reducer shows.
    ///
    /// The seed the store mints equals the one already laid out, but the user may have switched codes since,
    /// so the reducer's visible codes are written into the new workstation rather than read back from it.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine the displays belong to.
    ///   - readings: Every connected display.
    private func mintWorkstation(machineUuid: String, readings: [DisplayReading]) async {
        displaySettle = nil
        await syncDisplays(machineUuid: machineUuid, readings: readings)
        guard state.enabled else { return }
        for (displayKey, code) in state.activeByDisplay {
            guard let target = activeTarget(displayKey: displayKey, workspaceCode: code) else { continue }
            do {
                _ = try await service.machineHostSetActiveWorkspace(
                    workstationUuid: target.workstation,
                    displayUuid: target.display,
                    code: code
                )
            } catch {
                lastError = Self.message(error)
            }
        }
        storeChanged()
    }

    /// Starts managing when a start found no display and the connected set now has a workstation.
    private func resumeIfAwaitingDisplay() async {
        guard !state.enabled, awaitingDisplay, isFlagOn, snapshot?.activeWorkstationUuid != nil else { return }
        awaitingDisplay = false
        await enable()
    }

    /// Records every display change from boot on while windows are not managed.
    ///
    /// While managing, the lifecycle observer's enumeration drives `displaysRead` instead.
    private func watchScreenParameters() {
        guard screenToken == nil else { return }
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.enabled else { return }
                self.recordDisplays(DisplayIdentity.current())
            }
        }
    }

    /// The workstation the reducer is laid out for: the connected set's, once it is recorded.
    ///
    /// - Parameter snapshot: The machine's rows.
    /// - Returns: The workstation uuid, or nil while the connected set's workstation is not yet minted.
    private func connectedWorkstationUuid(_ snapshot: MachineHostSnapshotRow) -> String? {
        guard let connectedSetKey else { return snapshot.activeWorkstationUuid }
        return snapshot.workstations.first { $0.displaySetKey == connectedSetKey }?.uuid
    }

    /// The connected workstation and display behind a display key, when the code sits on that display.
    ///
    /// - Parameters:
    ///   - displayKey: The display's stable key.
    ///   - workspaceCode: The workspace code the reducer made visible there.
    /// - Returns: The workstation and display uuids, or nil while the connected set's workstation is not yet
    ///   minted, or when the code is placed elsewhere.
    private func activeTarget(displayKey: String, workspaceCode: String) -> (workstation: String, display: String)? {
        guard let snapshot, let workstation = connectedWorkstationUuid(snapshot),
            let display = snapshot.displays.first(where: { $0.stableKey == displayKey }),
            snapshot.workstationWorkspaces.contains(where: {
                $0.workstationUuid == workstation && $0.workspaceCode == workspaceCode
                    && $0.displayUuid == display.uuid
            })
        else { return nil }
        return (workstation, display.uuid)
    }
}

// MARK: - Launch recovery and strip seeding

extension MachineHostService {
    /// A running regular app other than this one, with its canonical launch date.
    private struct LiveApp {
        /// The process id.
        let pid: Int32
        /// The canonical launch date.
        let launchedAt: Date
        /// The bundle identifier, when the app has one.
        let bundleId: String?
        /// The human-readable name.
        let name: String
    }

    /// Every running regular app other than this one that reports a launch date.
    ///
    /// - Returns: The live apps.
    private static func liveApps() -> [LiveApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.processIdentifier != own, let date = app.launchDate
            else { return nil }
            return LiveApp(
                pid: app.processIdentifier,
                launchedAt: LaunchStamp.canonical(date),
                bundleId: app.bundleIdentifier,
                name: app.localizedName ?? app.executableURL?.lastPathComponent ?? "pid \(app.processIdentifier)"
            )
        }
    }

    /// The moves that return windows a previous run of this root left parked.
    ///
    /// A window whose mirror row carries a pre-park frame returns to it. A parked-looking window with no such
    /// row is centred only when this root was managing at its last exit (some live row has a pre-park frame);
    /// otherwise its hiding belongs to someone else and nothing moves.
    ///
    /// - Parameters:
    ///   - observed: Every window the answering apps report.
    ///   - snapshot: The machine's rows after the mirror reconcile.
    /// - Returns: One `(window, frame)` move per window to return.
    private static func recoveryMoves(
        observed: [ObservedWindow],
        snapshot: MachineHostSnapshotRow
    ) -> [(WindowKey, CGRect)] {
        let mirror = mirrorSnapshots(snapshot)
        guard mirror.contains(where: { $0.prePark != nil }) else { return [] }
        return CrashRecovery.plan(observed: observed, displays: DisplayIdentity.current().map(\.geom), mirror: mirror)
    }

    /// The live mirrored windows of live processes, with their pre-park frames.
    ///
    /// - Parameter snapshot: The machine's rows.
    /// - Returns: One snapshot per live window row whose process row parses.
    private static func mirrorSnapshots(_ snapshot: MachineHostSnapshotRow) -> [MirrorWindowSnapshot] {
        let processes = processKeys(snapshot)
        return snapshot.managedWindows.compactMap { row in
            guard row.deletedOn == nil, let process = processes[row.appProcessUuid] else { return nil }
            var prePark: CGRect?
            if let x = row.preParkX, let y = row.preParkY, let width = row.preParkWidth, let height = row.preParkHeight
            {
                prePark = CGRect(x: x, y: y, width: width, height: height)
            }
            return MirrorWindowSnapshot(
                pid: process.pid,
                launchedAt: process.launchedAt,
                cgWindowId: UInt32(row.cgWindowId),
                prePark: prePark
            )
        }
    }

    /// The process key of every live `app_process` row, by row uuid.
    ///
    /// - Parameter snapshot: The machine's rows.
    /// - Returns: The keys of rows whose launch stamp parses.
    private static func processKeys(_ snapshot: MachineHostSnapshotRow) -> [String: ProcessKey] {
        var keys: [String: ProcessKey] = [:]
        for row in snapshot.appProcesses where row.deletedOn == nil {
            guard let launchedAt = LaunchStamp.date(row.launchedAt) else { continue }
            keys[row.uuid] = ProcessKey(pid: Int32(row.pid), launchedAt: launchedAt)
        }
        return keys
    }

    /// Hands the reducer the observed frames and titles and the surviving mirror columns before `.enable`.
    ///
    /// - Parameters:
    ///   - snapshot: The machine's rows after the mirror reconcile.
    ///   - observed: The launch snapshot and the pids that answered it.
    ///   - recovered: The recovery moves, whose frames replace the observed ones.
    /// - Returns: Columns per workspace code, in `column_index` order.
    private func seedState(
        _ snapshot: MachineHostSnapshotRow,
        observed: (observed: [ObservedWindow], answered: Set<Int32>),
        recovered: [(WindowKey, CGRect)]
    ) -> [String: [StripColumn]] {
        let moved = Dictionary(recovered, uniquingKeysWith: { first, _ in first })
        for window in observed.observed {
            state.frames[window.key] = moved[window.key] ?? window.frame
            if let title = window.title { state.titles[window.key] = title }
        }
        let live = Set(Self.liveApps().map { ProcessKey(pid: $0.pid, launchedAt: $0.launchedAt) })
        let seen = Set(observed.observed.map(\.key))
        let held = state.allWindows
        let processes = Self.processKeys(snapshot)
        var rows: [String: [(index: Int64, column: StripColumn)]] = [:]
        for row in snapshot.managedWindows where row.deletedOn == nil && !row.isFloating {
            guard let code = row.workspaceCode, let index = row.columnIndex,
                let process = processes[row.appProcessUuid], live.contains(process)
            else { continue }
            let key = WindowKey(pid: process.pid, launchedAt: process.launchedAt, cgWindowId: UInt32(row.cgWindowId))
            guard !held.contains(key), !observed.answered.contains(key.pid) || seen.contains(key) else { continue }
            let column = StripColumn(window: key, weight: row.columnWeight > 0 ? row.columnWeight : 1)
            rows[code, default: []].append((index, column))
        }
        return rows.mapValues { $0.sorted { $0.index < $1.index }.map(\.column) }
    }
}

// MARK: - Rows to reducer inputs

extension MachineHostService {
    /// The display stable key of every display row, by uuid.
    ///
    /// - Parameter snapshot: The machine's rows.
    /// - Returns: The keys.
    private static func displayKeys(_ snapshot: MachineHostSnapshotRow) -> [String: String] {
        Dictionary(snapshot.displays.map { ($0.uuid, $0.stableKey) }) { first, _ in first }
    }

    /// One workstation's placement and visible codes, keyed by display stable key.
    ///
    /// - Parameters:
    ///   - snapshot: The machine's rows.
    ///   - workstationUuid: The workstation, or nil.
    /// - Returns: The layout, or nil when `workstationUuid` is nil.
    private static func layout(
        _ snapshot: MachineHostSnapshotRow,
        workstationUuid: String?
    ) -> MachineHostPlacement.StoredLayout? {
        guard let workstationUuid else { return nil }
        let displayKeys = displayKeys(snapshot)
        var placement: [String: String] = [:]
        var active: [String: String] = [:]
        for row in snapshot.workstationWorkspaces where row.workstationUuid == workstationUuid {
            guard let key = displayKeys[row.displayUuid] else { continue }
            placement[row.workspaceCode] = key
            if row.isActive { active[key] = row.workspaceCode }
        }
        return MachineHostPlacement.StoredLayout(placement: placement, active: active)
    }

    /// The layout a display enumeration should show, from the recorded workstations or the seed rule.
    ///
    /// - Parameters:
    ///   - readings: Every connected display.
    ///   - snapshot: The machine's rows.
    /// - Returns: The target layout, or nil when no display is connected.
    private static func targetLayout(
        _ readings: [DisplayReading],
        snapshot: MachineHostSnapshotRow
    ) -> MachineHostPlacement.TargetLayout? {
        var known: [String: MachineHostPlacement.StoredLayout] = [:]
        for workstation in snapshot.workstations {
            known[workstation.displaySetKey] = layout(snapshot, workstationUuid: workstation.uuid)
        }
        let displays = readings.map {
            MachineHostPlacement.SeedDisplay(
                stableKey: $0.input.stableKey,
                isBuiltin: $0.input.isBuiltin,
                originX: $0.input.frameX
            )
        }
        return MachineHostPlacement.targetLayout(readings: displays, known: known)
    }

    /// Every workspace code as a strip on the display `placement` puts it on.
    ///
    /// - Parameters:
    ///   - placement: The display stable key per workspace code.
    ///   - seed: Columns per code for strips the reducer holds none of.
    /// - Returns: The strips in code order; a code with no placement is left out.
    private func strips(placement: [String: String], seed: [String: [StripColumn]] = [:]) -> [WorkspaceStrip] {
        MachineHostPlacement.WorkspaceCodes.all.compactMap { code in
            guard let key = placement[code] else { return nil }
            let held = state.workspaces[code].flatMap { $0.columns.isEmpty ? nil : $0 }
            return WorkspaceStrip(
                code: code,
                displayKey: key,
                columns: held?.columns ?? seed[code] ?? [],
                focusedIndex: held?.focusedIndex
            )
        }
    }

    /// The image the mirror should hold: every running regular app, and every window the reducer tracks.
    ///
    /// - Returns: The current mirror image.
    private func mirrorImage() -> MirrorImage {
        var image = MirrorImage()
        for app in Self.liveApps() {
            let key = ProcessKey(pid: app.pid, launchedAt: app.launchedAt)
            image.processes[key] = MirrorProcess(bundleId: app.bundleId, name: app.name, running: true)
        }
        image.windows = MirrorProjection.windows(of: state)
        return image
    }

    /// The user-facing text for a store error.
    ///
    /// - Parameter error: The error.
    /// - Returns: The message.
    static func message(_ error: Error) -> String {
        (error as? DaemonError)?.userMessage ?? String(describing: error)
    }
}

/// One-line renderings of reducer events and effects for the debug log.
private enum WMTrace {
    /// The event's case name with the window, pid and frame it carries.
    ///
    /// - Parameter event: A reducer input.
    /// - Returns: The rendering.
    static func event(_ event: WMEvent) -> String {
        switch event {
        case .enable: return "enable"
        case .configure: return "configure"
        case .disable: return "disable"
        case let .hotkey(binding): return "hotkey \(binding.action.rawValue)"
        case let .appLaunched(pid, _): return "appLaunched pid=\(pid)"
        case let .appTerminated(pid): return "appTerminated pid=\(pid)"
        case let .windowCreated(key, frame, classification, _):
            return "windowCreated \(window(key)) \(rect(frame)) \(classification)"
        case let .windowDestroyed(key): return "windowDestroyed \(window(key))"
        case let .windowFocused(key): return "windowFocused \(window(key))"
        case let .windowMoved(key, frame): return "windowMoved \(window(key)) \(rect(frame))"
        case let .windowResized(key, frame): return "windowResized \(window(key)) \(rect(frame))"
        case let .mousePressed(point): return "mousePressed at=\(point.x),\(point.y)"
        case let .mouseReleased(point): return "mouseReleased at=\(point.map { "\($0.x),\($0.y)" } ?? "nil")"
        case let .displaysChanged(displays): return "displaysChanged count=\(displays.count)"
        case .wake: return "wake"
        case let .reconcile(observed, answered):
            return "reconcile observed=\(observed.count) answered=\(answered.count)"
        }
    }

    /// The effect kinds in order, each with the window it targets.
    ///
    /// - Parameter effects: Reducer output.
    /// - Returns: The rendering, or `none`.
    static func effects(_ effects: [WMEffect]) -> String {
        guard !effects.isEmpty else { return "none" }
        return
            effects.map { effect in
                switch effect {
                case let .setFrame(key, frame): return "setFrame \(window(key)) \(rect(frame))"
                case let .park(key, _): return "park \(window(key))"
                case let .unpark(key, frame): return "unpark \(window(key)) \(rect(frame))"
                case let .focus(key): return "focus \(window(key))"
                case .registerHotkeys: return "registerHotkeys"
                case .unregisterAllHotkeys: return "unregisterAllHotkeys"
                case let .mirrorDirty(windows, _, urgent): return "mirrorDirty count=\(windows.count) urgent=\(urgent)"
                case let .persistActiveWorkspace(displayKey, code): return "persistActive \(code)@\(displayKey)"
                }
            }
            .joined(separator: "; ")
    }

    /// The window as `pid/wid`.
    ///
    /// - Parameter key: A window key.
    /// - Returns: The rendering.
    private static func window(_ key: WindowKey) -> String { "\(key.pid)/\(key.cgWindowId)" }

    /// The frame as `x,y wxh` in whole points.
    ///
    /// - Parameter frame: A frame.
    /// - Returns: The rendering.
    private static func rect(_ frame: CGRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }
}
