import Darwin
import Foundation
import Synchronization

/// Refusal to take the machine-host lock: another root's app already manages this machine's windows.
struct MachineHostLockHeld: Error, Equatable, Sendable {
    /// The root the holder wrote into the lock file, or empty when it could not be read.
    let root: String
}

/// A machine-wide advisory lock that lets only one root's app manage windows at a time.
///
/// The lock is an `flock` on a file outside every root, so the kernel exits or crashes release it with
/// the process. It is unrelated to the kernel's own writer lock.
final class MachineHostLock: Sendable {
    /// The open, locked descriptor while held; -1 otherwise.
    private let descriptor = Mutex<Int32>(-1)

    /// The lock file, shared by every root on the machine.
    static var fileURL: URL {
        // Deliberately outside Paths: the second named exception to Paths.assertContained (Q4),
        // because one file must be seen by every root's app on the machine.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gm_kernel", isDirectory: true)
            .appendingPathComponent("gm_machine_host.lock")
    }

    /// Creates an unheld lock.
    init() {}

    /// Takes the lock for `root` without blocking, and records `root` and this pid in the file.
    ///
    /// Taking a lock this process already holds succeeds without reopening the file.
    ///
    /// - Parameter root: The resolved root of the app taking the lock, shown to a refused app.
    /// - Returns: Success, or `MachineHostLockHeld` naming the holder's root.
    func tryAcquire(root: String) -> Result<Void, MachineHostLockHeld> {
        descriptor.withLock { fd in
            guard fd < 0 else { return .success(()) }
            let url = Self.fileURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let opened = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
            guard opened >= 0 else { return .failure(MachineHostLockHeld(root: "")) }
            guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
                let holder = Self.contents(of: opened)
                close(opened)
                return .failure(MachineHostLockHeld(root: holder.split(separator: "\n").first.map(String.init) ?? ""))
            }
            let stamp = Data("\(root)\n\(getpid())\n".utf8)
            ftruncate(opened, 0)
            _ = stamp.withUnsafeBytes { pwrite(opened, $0.baseAddress, $0.count, 0) }
            fd = opened
            return .success(())
        }
    }

    /// Releases the lock if this process holds it.
    func release() {
        descriptor.withLock { fd in
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
    }

    /// The text of an open lock file.
    ///
    /// - Parameter fd: An open descriptor on the lock file.
    /// - Returns: Its contents, or empty when unreadable.
    private static func contents(of fd: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = pread(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return "" }
        return String(bytes: buffer.prefix(count), encoding: .utf8) ?? ""
    }
}
