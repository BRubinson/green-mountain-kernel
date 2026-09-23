import Darwin
import Foundation

/// The kernel's own resource usage and writer identity, as reported on the wire.
///
/// The numbers a person wants are the WRITER's, and that is often not the
/// process displaying them: the app may be a socket client of a headless kernel,
/// or a second copy that lost the ownership lock. So the answering kernel
/// measures itself and the client renders what it is told. Every field is an
/// additive OPTIONAL on the wire; a peer that reports no vitals answers nil,
/// which the UI reads as "—" rather than zero.
enum KernelVitalsSource {

    /// Resident footprint in bytes.
    ///
    /// Via `TASK_VM_INFO`'s `phys_footprint` — not `resident_size`, which counts
    /// shared pages this process did not cause. `phys_footprint` is what Activity
    /// Monitor shows as "Memory" and what the OS uses for pressure decisions.
    ///
    /// - Returns: The resident memory in bytes, or nil on error.
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
    /// A DELTA: a cumulative total says nothing about what the kernel is doing
    /// now. BOTH SIDES OF THE RATIO ARE MACH ABSOLUTE UNITS. `proc_pid_rusage`'s
    /// `ri_user_time`/`ri_system_time` are NOT nanoseconds, and dividing them by
    /// a nanosecond wall clock under-reports by the timebase ratio — on arm64 a
    /// saturated core then reads as roughly 2%. `mach_absolute_time()` keeps both
    /// sides in one unit, so there is no conversion to get wrong.
    ///
    /// - Returns: The CPU percentage (0-100+), nil on the first call or on error.
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

    /// Previous sample.
    ///
    /// Guarded by the server's serial queue, which is the only thing that
    /// answers PING, so no lock is needed — and adding one would suggest a
    /// concurrency that does not exist here.
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
