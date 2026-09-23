import Darwin
import Dispatch
import Foundation
import Observation

/// Vitals the kernel was TOLD, as opposed to the ones it reads about itself.
///
/// Uptime lives here and nowhere else: the answering kernel already counts it
/// (`uptime_seconds` on PING/STATUS), and a second clock in the menu bar would
/// drift from it for no gain. Memory and CPU are optional because a very old
/// daemon answers without them — see `KernelVitals` for the precedence.
struct KernelVitalsReport: Equatable, Sendable {
    var uptimeSeconds: Int?
    var residentMemoryBytes: UInt64?
    var cpuPercent: Double?

    /// Creates a kernel vitals report with optional measurements.
    ///
    /// - Parameters:
    ///   - uptimeSeconds: The uptime in seconds, or nil.
    ///   - residentMemoryBytes: The resident memory in bytes, or nil.
    ///   - cpuPercent: The CPU percentage, or nil.
    init(
        uptimeSeconds: Int? = nil,
        residentMemoryBytes: UInt64? = nil,
        cpuPercent: Double? = nil
    ) {
        self.uptimeSeconds = uptimeSeconds
        self.residentMemoryBytes = residentMemoryBytes
        self.cpuPercent = cpuPercent
    }
}

/// One reading taken off this process, published as a value so the syscalls and
/// the observable mutation happen in different places.
struct KernelVitalsReading: Equatable, Sendable {
    var residentMemoryBytes: UInt64?
    var cpuPercent: Double?
}

/// The menu bar's vitals sampler: resident footprint, CPU load, uptime, and the display
/// strings for all three.
///
/// Unrelated to `MemoryWatcher` in `gmk/gmDaemon`, which watches prompt directories unrelated to RAM.
/// REPORTED values win over local samples; reports describe the kernel owning the store, another
/// process in client-only mode. Showing our footprint under the owner's label is wrong, not missing.
/// Local sampling is fallback.
@Observable
@MainActor
final class KernelVitals {
    private(set) var residentMemoryBytes: UInt64?
    private(set) var cpuPercent: Double?
    /// Always adopted from the report — never recomputed from a start date.
    private(set) var uptimeSeconds: Int?

    /// Sampling cadence. 2s is slow enough to be invisible on a battery and
    /// fast enough that a CPU spike is still on screen when the dropdown opens.
    let interval: TimeInterval

    /// What the kernel reported, re-read on every tick rather than pushed, so
    /// this type owns no subscription and cannot fall out of sync with one.
    private let report: @MainActor () -> KernelVitalsReport?

    /// A private serial queue, NOT the cooperative pool and emphatically not
    /// the kernel's serial database queue: a writer-role kernel serializes
    /// every db access on that one lane, and a 2s poll that lands on it turns
    /// a display refresh into contention with real work.
    ///
    /// Nothing shared, so there is nothing to contend with.
    private let samplingQueue = DispatchQueue(label: "gmvibes.kernel.vitals", qos: .utility)
    private var ticker: DispatchSourceTimer?
    private let cpu = CpuDeltaState()

    /// Creates a vitals sampler with an optional report callback.
    ///
    /// - Parameters:
    ///   - interval: The sampling interval in seconds; default 2.
    ///   - report: A closure to fetch kernel-reported vitals; default nil.
    init(
        interval: TimeInterval = 2,
        report: @escaping @MainActor () -> KernelVitalsReport? = { nil }
    ) {
        self.interval = interval
        self.report = report
    }

    isolated deinit {
        ticker?.cancel()
    }

    // MARK: - Lifecycle

    /// Idempotent — a second call while running is a no-op, not a second timer.
    func start() {
        guard ticker == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
        // Generous leeway: these readings are for a human reading a dropdown,
        // so letting the kernel coalesce the wakeups is free accuracy to spend.
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [self, cpu] in
            let reading = Self.read(cpu: cpu)
            Task { @MainActor in self.publish(reading) }
        }
        ticker = timer
        timer.resume()
    }

    /// Stops the vitals sampling timer.
    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Takes a sample immediately, off the timer's phase.
    ///
    /// A surface calls this as it appears so the first row shown is not dashes.
    func sampleNow() {
        samplingQueue.async { [self, cpu] in
            let reading = Self.read(cpu: cpu)
            Task { @MainActor in self.publish(reading) }
        }
    }

    /// Publishes vitals, preferring reported values over local samples.
    ///
    /// - Parameter reading: The local sample reading.
    private func publish(_ reading: KernelVitalsReading) {
        let reported = report()
        let memory = reported?.residentMemoryBytes ?? reading.residentMemoryBytes
        let cpu = reported?.cpuPercent ?? reading.cpuPercent
        // Change-gated, like the rest of the app's observables: an unchanged
        // value must not invalidate a view that is only showing three strings.
        if residentMemoryBytes != memory { residentMemoryBytes = memory }
        if cpuPercent != cpu { cpuPercent = cpu }
        if uptimeSeconds != reported?.uptimeSeconds { uptimeSeconds = reported?.uptimeSeconds }
    }

    // MARK: - Display

    var memoryText: String {
        residentMemoryBytes.map(Self.formatBytes) ?? "—"
    }

    var cpuText: String {
        cpuPercent.map(Self.formatPercent) ?? "—"
    }

    var uptimeText: String {
        uptimeSeconds.map(Self.formatUptime) ?? "—"
    }

    /// Formats byte count as decimal MB or GB.
    ///
    /// Matches Activity Monitor's display; a menu bar that disagrees about
    /// the same process reads as a kernel bug, not a unit issue.
    ///
    /// - Parameter bytes: The byte count to format.
    /// - Returns: A formatted string like "123 MB" or "1.23 GB".
    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.2f GB", mb / 1000)
    }

    /// Formats a CPU percentage value.
    ///
    /// - Parameter percent: The percentage value.
    /// - Returns: A formatted string like "45.3%".
    static func formatPercent(_ percent: Double) -> String {
        String(format: "%.1f%%", max(0, percent))
    }

    /// Formats uptime in days, hours, minutes and seconds.
    ///
    /// Adds a day arm (like `DaemonStatusPopover`) since long uptimes
    /// make hour-only display unreadable at a glance.
    ///
    /// - Parameter seconds: The uptime in seconds.
    /// - Returns: A formatted string like "2d 15h 30m" or "45m 30s".
    static func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    // MARK: - Sampling

    /// Previous-sample carrier for the CPU delta.
    ///
    /// Mutated ONLY from `samplingQueue`, which is what makes the unchecked
    /// conformance true rather than hopeful: one serial queue is the single
    /// writer, and nothing else is handed a reference.
    private nonisolated final class CpuDeltaState: @unchecked Sendable {
        var previousCpuTicks: UInt64?
        var previousWallTicks: UInt64?
    }

    /// Takes one reading of resident memory and CPU percentage.
    ///
    /// - Parameter cpu: The CPU delta state tracker.
    /// - Returns: A reading with current memory and CPU values.
    private nonisolated static func read(cpu: CpuDeltaState) -> KernelVitalsReading {
        KernelVitalsReading(
            residentMemoryBytes: residentFootprintBytes(),
            cpuPercent: cpuPercentDelta(cpu: cpu)
        )
    }

    /// Returns the resident footprint in bytes from the Mach task API.
    ///
    /// Uses `phys_footprint` rather than `resident_size` because it is what
    /// the kernel's memory limits are enforced against, counts compressed and
    /// IOKit-mapped pages, and matches Activity Monitor's "Memory" column.
    /// `resident_size` omits compressed pages and falls with pressure.
    ///
    /// - Returns: The physical footprint in bytes, or nil on error.
    private nonisolated static func residentFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    /// Returns the CPU load as a percentage of one core.
    ///
    /// 100% is one saturated core; multithreaded bursts legitimately exceed it.
    /// Percentage is a delta between samples; the first sample returns nil.
    ///
    /// - Parameter cpu: The CPU delta state tracker.
    /// - Returns: The CPU percentage, or nil for the first sample or on error.
    private nonisolated static func cpuPercentDelta(cpu: CpuDeltaState) -> Double? {
        // BOTH SIDES OF THE RATIO ARE MACH ABSOLUTE TIME UNITS. `ri_user_time` and
        // `ri_system_time` are documented as nanoseconds and are not: they are mach ticks,
        // 125/3 ns each on Apple silicon. Dividing them by a real nanosecond clock reports a
        // busy core as 2.4%, and only on arm64, because Intel's timebase is 1:1. Measuring the
        // wall side with `mach_absolute_time()` needs no timebase conversion and cannot drift
        // with the hardware. It also stops across system sleep, which is right here: the
        // process consumes no CPU while asleep, so both sides pause together.
        let wall = mach_absolute_time()
        guard let consumed = cpuTicks() else { return nil }
        defer {
            cpu.previousCpuTicks = consumed
            cpu.previousWallTicks = wall
        }
        guard let previousCpu = cpu.previousCpuTicks,
            let previousWall = cpu.previousWallTicks,
            wall > previousWall, consumed >= previousCpu
        else { return nil }
        return Double(consumed - previousCpu) / Double(wall - previousWall) * 100
    }

    /// Returns the total CPU ticks (user + system) consumed by this process.
    ///
    /// Measured in mach absolute time units, not nanoseconds (see
    /// `cpuPercentDelta`). Uses `RUSAGE_INFO_V4` for stability across SDKs.
    ///
    /// - Returns: The total CPU ticks, or nil on error.
    private nonisolated static func cpuTicks() -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        guard status == 0 else { return nil }
        return info.ri_user_time &+ info.ri_system_time
    }
}
