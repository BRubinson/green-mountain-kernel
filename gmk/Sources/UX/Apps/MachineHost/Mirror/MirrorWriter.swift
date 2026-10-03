import CoreGraphics
import Foundation

/// The launch-date spelling shared by the reducer keys and the `app_process.launched_at` column.
///
/// Every launch date the shell hands the reducer is canonical, so a key read back from the store equals the
/// key the shell builds from the live process.
enum LaunchStamp {
    /// The column format: ISO-8601 with milliseconds.
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// The column text for `date`.
    ///
    /// - Parameter date: A launch date.
    /// - Returns: The ISO-8601 text with milliseconds.
    static func string(_ date: Date) -> String {
        date.formatted(style)
    }

    /// The date for column text.
    ///
    /// - Parameter text: The `launched_at` value.
    /// - Returns: The date, or nil when the text is not in the column format.
    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: style)
    }

    /// `date` rounded to what the column holds.
    ///
    /// - Parameter date: A launch date.
    /// - Returns: The date as it reads back from the store.
    static func canonical(_ date: Date) -> Date {
        Self.date(string(date)) ?? date
    }
}

/// The debounced writer of the window mirror: `app_process` and `managed_window`, plus the active workspaces.
///
/// A tick diffs the image the service builds against the image the store holds and writes only the delta, so
/// the hotkey path never waits on a write. One flush is in flight at a time; its store calls are injected.
@MainActor
final class MirrorWriter {
    /// Writes one mirror batch in one transaction and answers the rows it inserted or changed.
    typealias Flush = @Sendable (MirrorBatch) async throws -> MirrorFlushRow
    /// Records that a workspace code is the visible one on a display key.
    typealias SetActive = @Sendable (_ displayKey: String, _ workspaceCode: String) async throws -> Void

    /// The pause that coalesces a burst of changes into one tick.
    static let debounce: Duration = .milliseconds(250)
    /// The pause before a failed tick is tried again.
    static let retryDelay: Duration = .seconds(5)

    /// The machine every mirror row belongs to.
    private let machineUuid: String
    /// Builds the image the mirror should hold now.
    private let image: @MainActor () -> MirrorImage
    /// The injected store write for a batch.
    private let flushStore: Flush
    /// The injected store write for an active workspace.
    private let setActive: SetActive

    /// The image the store holds, as far as this writer knows.
    private var lastFlushed = MirrorImage()
    /// Process row uuids by key, for retire lists.
    private var processUuids: [ProcessKey: String] = [:]
    /// Window row uuids by key, for retire lists.
    private var windowUuids: [WindowKey: String] = [:]
    /// Active workspace writes waiting for the next tick, by display key.
    private var pendingActive: [String: String] = [:]
    /// True when something changed since the last tick started.
    private var dirty = false
    /// True when a pending change must not wait for the debounce.
    private var urgentPending = false
    /// True while a tick is writing.
    private var inFlight = false
    /// The scheduled tick, if any.
    private var scheduled: Task<Void, Never>?

    /// Creates a writer for one machine with its store calls injected.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine row every mirror row belongs to.
    ///   - image: Builds the current image from the service's state; called once per tick.
    ///   - flush: Writes one batch; never called on the hotkey path.
    ///   - setActive: Writes one active workspace.
    init(
        machineUuid: String,
        image: @escaping @MainActor () -> MirrorImage,
        flush: @escaping Flush,
        setActive: @escaping SetActive
    ) {
        self.machineUuid = machineUuid
        self.image = image
        self.flushStore = flush
        self.setActive = setActive
    }

    /// Adopts the live mirror rows read at startup as what the store holds.
    ///
    /// - Parameters:
    ///   - processes: The live `app_process` rows of the machine.
    ///   - windows: The live `managed_window` rows of those processes.
    func seed(processes: [AppProcessRow], windows: [ManagedWindowRow]) {
        var seeded = MirrorImage()
        var keysByUuid: [String: ProcessKey] = [:]
        for row in processes {
            guard let launchedAt = LaunchStamp.date(row.launchedAt) else { continue }
            let key = ProcessKey(pid: Int32(row.pid), launchedAt: launchedAt)
            keysByUuid[row.uuid] = key
            processUuids[key] = row.uuid
            seeded.processes[key] = MirrorProcess(bundleId: row.bundleId, name: row.name, running: row.isRunning)
        }
        for row in windows {
            guard let process = keysByUuid[row.appProcessUuid] else { continue }
            let key = WindowKey(pid: process.pid, launchedAt: process.launchedAt, cgWindowId: UInt32(row.cgWindowId))
            windowUuids[key] = row.uuid
            seeded.windows[key] = Self.mirrorWindow(row)
        }
        lastFlushed = seeded
    }

    /// Marks the mirror stale and schedules a tick: after the debounce, or on the next turn when `urgent`.
    ///
    /// - Parameter urgent: True when a pre-park frame changed, so crash recovery must see it at once.
    func markDirty(urgent: Bool) {
        dirty = true
        urgentPending = urgentPending || urgent
        guard !inFlight else { return }
        if scheduled != nil, !urgentPending { return }
        schedule(after: urgentPending ? .zero : Self.debounce)
    }

    /// Queues the visible workspace of a display for the next tick; a later call for the same display wins.
    ///
    /// - Parameters:
    ///   - displayKey: The display's stable key.
    ///   - workspaceCode: The workspace now visible there.
    func enqueueActive(displayKey: String, workspaceCode: String) {
        pendingActive[displayKey] = workspaceCode
        markDirty(urgent: false)
    }

    /// Cancels the scheduled tick; a tick already writing finishes.
    func cancel() {
        scheduled?.cancel()
        scheduled = nil
        dirty = false
        urgentPending = false
        pendingActive = [:]
    }

    // MARK: - Tick

    /// Replaces the scheduled tick with one that runs after `delay`.
    ///
    /// - Parameter delay: The pause before the tick.
    private func schedule(after delay: Duration) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    /// Writes the delta and the pending active workspaces, then reschedules if more changed meanwhile.
    private func tick() async {
        scheduled = nil
        guard dirty else { return }
        dirty = false
        urgentPending = false
        inFlight = true
        let failed = await writeDelta()
        let actives = pendingActive
        pendingActive = [:]
        for (displayKey, code) in actives {
            do { try await setActive(displayKey, code) } catch { Self.log("active workspace write failed: \(error)") }
        }
        inFlight = false
        if failed {
            dirty = true
            schedule(after: Self.retryDelay)
        } else if dirty {
            schedule(after: urgentPending ? .zero : Self.debounce)
        }
    }

    /// Diffs, writes and adopts one batch.
    ///
    /// - Returns: True when the store refused the batch, so the tick must be retried.
    private func writeDelta() async -> Bool {
        let delta = MirrorProjection.diff(last: lastFlushed, current: image())
        guard !delta.isEmpty else { return false }
        let (batch, applied) = makeBatch(delta)
        guard !applied.isEmpty else { return false }
        do {
            let written = try await flushStore(batch)
            adopt(written, retired: applied)
            lastFlushed = lastFlushed.applying(applied)
            return false
        } catch {
            Self.log("mirror flush failed: \(error)")
            return true
        }
    }

    /// Maps a delta to the store's batch, dropping what the store cannot take yet.
    ///
    /// A window whose process has no row and is not in this batch waits for a later tick; a retirement of a
    /// row whose uuid is unknown needs no write.
    ///
    /// - Parameter delta: The projection's delta.
    /// - Returns: The batch, and the part of `delta` it covers.
    private func makeBatch(_ delta: MirrorDelta) -> (MirrorBatch, MirrorDelta) {
        var applied = delta
        let upsertedProcesses = Set(delta.processUpserts.keys)
        for key in delta.windowUpserts.keys {
            let process = ProcessKey(pid: key.pid, launchedAt: key.launchedAt)
            if processUuids[process] == nil, !upsertedProcesses.contains(process) { applied.windowUpserts[key] = nil }
        }
        var processes = applied.processUpserts.map { Self.processUpsert($0.key, $0.value) }
        for key in delta.processRetirements {
            guard let process = lastFlushed.processes[key], processUuids[key] != nil else { continue }
            var stopped = process
            stopped.running = false
            processes.append(Self.processUpsert(key, stopped))
        }
        let batch = MirrorBatch(
            machineUuid: machineUuid,
            processes: processes,
            windows: applied.windowUpserts.map { Self.windowUpsert($0.key, $0.value) },
            retireProcessUuids: delta.processRetirements.compactMap { processUuids[$0] },
            retireWindowUuids: delta.windowRetirements.compactMap { windowUuids[$0] }
        )
        return (batch, applied)
    }

    /// Records the uuids of the rows a batch wrote and forgets the rows it retired.
    ///
    /// - Parameters:
    ///   - written: The rows the store inserted or changed.
    ///   - retired: The delta the batch covered.
    private func adopt(_ written: MirrorFlushRow, retired: MirrorDelta) {
        retired.windowRetirements.forEach { windowUuids[$0] = nil }
        retired.processRetirements.forEach { processUuids[$0] = nil }
        var keysByUuid = Dictionary(processUuids.map { ($0.value, $0.key) }) { first, _ in first }
        for row in written.appProcesses where row.deletedOn == nil {
            guard let launchedAt = LaunchStamp.date(row.launchedAt) else { continue }
            let key = ProcessKey(pid: Int32(row.pid), launchedAt: launchedAt)
            processUuids[key] = row.uuid
            keysByUuid[row.uuid] = key
        }
        for row in written.managedWindows where row.deletedOn == nil {
            guard let process = keysByUuid[row.appProcessUuid] else { continue }
            let key = WindowKey(pid: process.pid, launchedAt: process.launchedAt, cgWindowId: UInt32(row.cgWindowId))
            windowUuids[key] = row.uuid
        }
    }

    // MARK: - Mapping

    /// The store upsert for one mirrored process.
    ///
    /// - Parameters:
    ///   - key: The process key.
    ///   - process: Its mirrored values.
    /// - Returns: The upsert.
    private static func processUpsert(_ key: ProcessKey, _ process: MirrorProcess) -> AppProcessUpsert {
        AppProcessUpsert(
            identity: identity(key),
            bundleId: process.bundleId,
            name: process.name,
            isRunning: process.running
        )
    }

    /// The store upsert for one mirrored window.
    ///
    /// - Parameters:
    ///   - key: The window key.
    ///   - window: Its mirrored values.
    /// - Returns: The upsert.
    private static func windowUpsert(_ key: WindowKey, _ window: MirrorWindow) -> ManagedWindowUpsert {
        ManagedWindowUpsert(
            process: identity(ProcessKey(pid: key.pid, launchedAt: key.launchedAt)),
            cgWindowId: Int64(key.cgWindowId),
            workspaceCode: window.workspaceCode,
            title: window.title,
            columnIndex: window.columnIndex.map(Int64.init),
            columnWeight: window.weight,
            isFloating: window.floating,
            frameX: window.frame.map { Double($0.minX) },
            frameY: window.frame.map { Double($0.minY) },
            frameWidth: window.frame.map { Double($0.width) },
            frameHeight: window.frame.map { Double($0.height) },
            preParkX: window.prePark.map { Double($0.minX) },
            preParkY: window.prePark.map { Double($0.minY) },
            preParkWidth: window.prePark.map { Double($0.width) },
            preParkHeight: window.prePark.map { Double($0.height) }
        )
    }

    /// The mirrored values a stored window row holds.
    ///
    /// - Parameter row: The stored row.
    /// - Returns: The mirrored values.
    private static func mirrorWindow(_ row: ManagedWindowRow) -> MirrorWindow {
        MirrorWindow(
            workspaceCode: row.workspaceCode,
            columnIndex: row.columnIndex.map(Int.init),
            weight: row.columnWeight,
            floating: row.isFloating,
            frame: rect(row.frameX, row.frameY, row.frameWidth, row.frameHeight),
            prePark: rect(row.preParkX, row.preParkY, row.preParkWidth, row.preParkHeight),
            title: row.title
        )
    }

    /// A rectangle from four optional columns.
    ///
    /// - Parameters:
    ///   - x: The origin x.
    ///   - y: The origin y.
    ///   - width: The width.
    ///   - height: The height.
    /// - Returns: The rectangle, or nil unless all four are present.
    private static func rect(_ x: Double?, _ y: Double?, _ width: Double?, _ height: Double?) -> CGRect? {
        guard let x, let y, let width, let height else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The store identity for a process key.
    ///
    /// - Parameter key: The process key.
    /// - Returns: The pid and launch stamp.
    private static func identity(_ key: ProcessKey) -> AppProcessIdentity {
        AppProcessIdentity(pid: Int64(key.pid), launchedAt: LaunchStamp.string(key.launchedAt))
    }

    /// Reports a failed write; the tick is retried, so nothing is raised.
    ///
    /// - Parameter message: What failed.
    private static func log(_ message: String) {
        NSLog("[gm_machine_host] %@", message)
    }
}
