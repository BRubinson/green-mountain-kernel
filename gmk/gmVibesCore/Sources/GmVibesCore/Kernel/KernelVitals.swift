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
public struct KernelVitalsReport: Equatable, Sendable {
    var uptimeSeconds: Int?
    var residentMemoryBytes: UInt64?
    var cpuPercent: Double?

    init(uptimeSeconds: Int? = nil,
         residentMemoryBytes: UInt64? = nil,
         cpuPercent: Double? = nil) {
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

/// The menu bar's vitals sampler: resident footprint, CPU load, uptime, plus
/// the display strings for all three.
///
/// NAME TRAP, and it is an easy one to walk into: `MemoryWatcher` already
/// exists in `gmk/gmDaemon` and has NOTHING to do with RAM — it is the FSEvents
/// watcher over prompt `memory/` directories. This type is the one that reads
/// bytes. Nothing here extends, imports or resembles that one, deliberately.
///
/// Precedence, which matters because two processes are in play: a reported
/// value always wins over a locally sampled one. The report describes the
/// kernel that actually owns the store, and in CLIENT-ONLY mode that is not
/// this process — showing our own footprint under the owner's label would be a
/// quietly wrong number rather than a missing one. Local sampling is the
/// fallback (and in writer mode it reads the same process anyway), so the rows
/// stay populated when nothing has answered yet.
@Observable
@MainActor
public final class KernelVitals {
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
    /// a display refresh into contention with real work. Nothing shared, so
    /// there is nothing to contend with.
    private let samplingQueue = DispatchQueue(label: "gmvibes.kernel.vitals", qos: .utility)
    private var ticker: DispatchSourceTimer?
    private let cpu = CpuDeltaState()

    public init(interval: TimeInterval = 2,
                report: @escaping @MainActor () -> KernelVitalsReport? = { nil }) {
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

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// One reading now, off the timer's phase — what a surface calls as it
    /// appears so the first row it shows is not a dash.
    func sampleNow() {
        samplingQueue.async { [self, cpu] in
            let reading = Self.read(cpu: cpu)
            Task { @MainActor in self.publish(reading) }
        }
    }

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

    /// Decimal MB/GB, matching what Activity Monitor shows for the same
    /// process — a menu bar that disagrees with Activity Monitor about the
    /// footprint of the same pid reads as a bug in the kernel, not in the unit.
    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.2f GB", mb / 1000)
    }

    static func formatPercent(_ percent: Double) -> String {
        String(format: "%.1f%%", max(0, percent))
    }

    /// The same ladder `DaemonStatusPopover` uses, with a day arm on top: a
    /// menu-bar-resident kernel is expected to run for days, where "51h 12m"
    /// stops being readable at a glance.
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

    private nonisolated static func read(cpu: CpuDeltaState) -> KernelVitalsReading {
        KernelVitalsReading(
            residentMemoryBytes: residentFootprintBytes(),
            cpuPercent: cpuPercentDelta(cpu: cpu))
    }

    /// `phys_footprint` rather than `resident_size`: it is the number the
    /// kernel's own memory limits are enforced against, it counts compressed
    /// and IOKit-mapped pages, and it is what Activity Monitor's "Memory"
    /// column shows. `resident_size` omits compressed pages, so it falls as
    /// pressure rises — exactly backwards for a vitals row.
    private nonisolated static func residentFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    /// CPU as a percentage of one core over the interval BETWEEN samples —
    /// 100% is one saturated core, and a multi-threaded burst legitimately
    /// exceeds it, exactly as Activity Monitor reports.
    ///
    /// `proc_pid_rusage` reports CPU consumed CUMULATIVELY since launch, so its
    /// absolute value says nothing about load now: a process that burned a core
    /// for a minute at startup and has idled since would read hot forever. The
    /// percentage is therefore a delta — CPU consumed since the previous sample
    /// over monotonic time elapsed since the previous sample. The first sample
    /// after a start has no predecessor and returns nil rather than a
    /// fabricated 0.
    private nonisolated static func cpuPercentDelta(cpu: CpuDeltaState) -> Double? {
        // BOTH SIDES OF THE RATIO ARE MACH ABSOLUTE TIME UNITS, and that is the
        // whole trick. `ri_user_time`/`ri_system_time` are documented in
        // "nanoseconds" and are not — they are mach ticks, which on Apple
        // silicon run 125/3 ns each. Dividing them by a real nanosecond clock
        // (`DispatchTime.uptimeNanoseconds`) reports a busy core as 2.4%, and
        // it does so ONLY on arm64: Intel's timebase is 1:1, so the bug hides
        // on the machine nobody ships on any more. Measuring the wall side with
        // `mach_absolute_time()` keeps the units identical, which needs no
        // timebase conversion and cannot drift with the hardware.
        //
        // Mach absolute time also stops across system sleep, which is what we
        // want here: the process consumes no CPU while asleep either, so the
        // two sides pause together instead of a resume printing a fake idle.
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

    /// User + system CPU consumed by this process, in mach absolute time units
    /// (see `cpuPercentDelta` — NOT nanoseconds, whatever the field names say).
    ///
    /// `RUSAGE_INFO_V4` with its matching concrete struct rather than
    /// `RUSAGE_INFO_CURRENT`/`rusage_info_current`: the "current" flavor tracks
    /// whatever the SDK's newest version happens to be, so it moves under the
    /// code on an SDK bump. V4 is fixed, and `ri_user_time`/`ri_system_time`
    /// have been in every flavor since V0.
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
