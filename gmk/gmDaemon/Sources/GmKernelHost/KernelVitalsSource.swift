import Darwin
import Foundation
import GmDaemonSdk

/// The kernel's own resource usage and writer identity, as reported on the wire.
///
/// ## Why the KERNEL measures itself
///
/// The menu bar could sample its own process, and `KernelVitals` in the app does
/// exactly that as a fallback. But the numbers a person wants are the WRITER's —
/// the process holding the database — and in the two shapes that matter those
/// are not the same process:
///
/// - the app is a socket client and the writer is a headless `gm_kernel daemon`
/// - a second app copy lost the ownership lock and runs client-only
///
/// In both, self-sampling would display the wrong process's memory beside a role
/// row saying the database is owned elsewhere. So the answering kernel measures
/// itself, and the client renders what it is told.
///
/// Every field is an additive OPTIONAL on the wire. A kernel that predates them
/// answers nil and the UI reads "—" rather than zero, which is the honest
/// rendering of "this peer does not report vitals".
enum KernelVitalsSource {

    /// Resident footprint in bytes, via `TASK_VM_INFO`'s `phys_footprint`.
    ///
    /// `phys_footprint` rather than `resident_size`: it is the number Activity
    /// Monitor shows as "Memory" and the one the OS uses for pressure decisions,
    /// whereas `resident_size` counts shared pages this process did not cause.
    static func residentMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    /// CPU percent since the previous call, or nil on the first.
    ///
    /// A DELTA, because a cumulative total is meaningless to display: a kernel up
    /// for a week has burned a lot of CPU and is doing nothing right now.
    ///
    /// BOTH SIDES OF THE RATIO ARE MACH ABSOLUTE UNITS. `proc_pid_rusage`'s
    /// `ri_user_time`/`ri_system_time` are NOT nanoseconds, and dividing them by
    /// a nanosecond wall clock under-reports by the timebase ratio — on arm64 a
    /// fully saturated core reads as roughly 2%, while on Intel, where the
    /// timebase is 1:1, the same code looks correct. Measuring the wall side with
    /// `mach_absolute_time()` keeps both sides in one unit, so there is no
    /// conversion to get wrong.
    static func cpuPercent() -> Double? {
        var usage = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }

        let cpu = usage.ri_user_time &+ usage.ri_system_time
        let wall = mach_absolute_time()

        defer { previous = (cpu: cpu, wall: wall) }
        guard let last = previous, wall > last.wall else { return nil }

        let cpuDelta = Double(cpu &- last.cpu)
        let wallDelta = Double(wall &- last.wall)
        guard wallDelta > 0 else { return nil }
        return (cpuDelta / wallDelta) * 100
    }

    /// Previous sample. Guarded by the server's serial queue, which is the only
    /// thing that answers PING, so no lock is needed — and adding one would
    /// suggest a concurrency that does not exist here.
    nonisolated(unsafe) private static var previous: (cpu: UInt64, wall: UInt64)?

    /// `"writer"` when this process holds the database, `"client"` when another
    /// kernel does.
    ///
    /// Set by whichever host booted. A headless kernel that reached the point of
    /// answering PING necessarily won the ownership lock, so it reports `writer`;
    /// an app instance that lost it reports `client` and names the holder.
    nonisolated(unsafe) static var writerRole: String = "writer"

    /// Bundle path of the process that actually owns the lock, so a client-mode
    /// kernel can name BOTH bundles rather than only its own — which is the whole
    /// point of the row in the second-copy case.
    nonisolated(unsafe) static var writerBundlePath: String?
}
