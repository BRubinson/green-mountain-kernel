import Foundation
import GmDaemon
import GmDaemonSdk

/// Who owns the database, decided before anything can open it.
///
/// ## The problem this type exists for
///
/// Single-writer used to be a PROCESS property enforced by a shape: only
/// `gm_daemon` ever constructed a `Store`, and it took a `flock` first. Nothing
/// in the type system said so — the guarantee was "there is one program that
/// does this, and it does it correctly".
///
/// The collapse breaks that by construction. The writer now lives inside an
/// application bundle, and macOS will happily run a second copy of one: an Xcode
/// debug build beside the installed app, a copy in `~/Downloads`, or `open -n` on
/// the installed bundle outright. LaunchServices gives one instance per bundle
/// PATH, not one per application. Each of those copies would open the same
/// `~/gmfs/gm.db` through GRDB's WAL, and two writers into append-only history is
/// not recoverable.
///
/// So the lock stops being a step a correct program remembers to take, and
/// becomes the only way to obtain the capability. `Token` cannot be constructed
/// outside this file, `acquire()` is its only producer, and `KernelWriter.start`
/// — the single `Store(path:)` site in the tree — consumes one. A losing instance
/// cannot open the database because there is no expression that opens it.
/// `KernelHostContractTests` scans for a second `Store(path:` so that stays true.
public enum KernelOwnership {

    /// Proof that this process holds the exclusive database lock.
    ///
    /// `~Copyable` so it cannot be duplicated into a second writer, and its
    /// initialiser is `fileprivate` so `acquire()` is the only thing that can
    /// mint one. The held descriptor is never closed: the lock is meant to last
    /// for the process's lifetime, and letting the kernel release it at exit is
    /// what makes a CRASHED kernel leave no stale lock behind.
    public struct Token: ~Copyable {
        fileprivate let fd: Int32
        fileprivate init(fd: Int32) { self.fd = fd }
    }

    /// Who holds the lock, when we did not get it.
    public struct Holder: Sendable, Equatable {
        public let pid: pid_t
        public let executablePath: String
        /// nil means the holder is HEADLESS — a `gm_kernel daemon` process
        /// rather than an app bundle. The distinction decides what a losing app
        /// does next: take over from a headless writer, but never from another
        /// app copy.
        public let bundlePath: String?
    }

    public enum Outcome: ~Copyable {
        case acquired(Token)
        case heldBy(Holder)
    }

    /// Take the lock, or report who has it.
    ///
    /// The ORDER below is the invariant, not the lock itself. Every step that
    /// could touch the database happens after the `flock`, and the `.heldBy`
    /// path has no fall-through — it cannot reach a `Store` even by accident,
    /// because it does not produce a `Token`.
    public static func acquire() throws -> Outcome {
        try Paths.ensureRuntimeDirs()

        // The pidfile PATH IS DELIBERATELY UNCHANGED (`~/gmfs/daemon.pid`).
        // Renaming runtime state to match the kernel's new name would be the
        // most dangerous cosmetic edit available here: a new instance locking
        // `kernel.pid` while an older one still holds `daemon.pid` takes a
        // DIFFERENT LOCK, and the two would proceed to write the same database
        // believing each was alone. The word "daemon" in a filename costs
        // nothing; a second writer costs the history.
        let fd = open(Paths.pidfile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw OwnershipError.cannotOpenPidfile(errno: errno)
        }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            // Do NOT close `fd` on this path before reading: the holder's record
            // is in this same file, and we still need to read it.
            let holder = readHolder(fd: fd)
            close(fd)
            return .heldBy(holder ?? Holder(
                pid: 0,
                executablePath: "(unknown — pidfile unreadable)",
                bundlePath: nil))
        }

        // Won it. Record WHO we are, so a loser can name us.
        ftruncate(fd, 0)
        let record = [
            "\(getpid())",
            Bundle.main.executablePath ?? CommandLine.arguments.first ?? "(unknown)",
            Self.ownBundlePath() ?? "",
        ].joined(separator: "\n") + "\n"
        _ = record.withCString { write(fd, $0, strlen($0)) }

        return .acquired(Token(fd: fd))
    }

    /// The current holder, read without attempting to take the lock. Used by the
    /// menu bar to name the owning process in client mode.
    public static func readHolder() -> Holder? {
        let fd = open(Paths.pidfile.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return readHolder(fd: fd)
    }

    /// Three lines: pid, executable path, bundle path (empty when headless).
    ///
    /// The pidfile gaining two lines is safe because NOTHING reads its contents
    /// — verified across the tree: it is written at boot and unlinked at
    /// shutdown, and every other consumer only ever `flock`s it.
    ///
    /// One retry, because a loser can catch the winner between `ftruncate` and
    /// `write` and see an empty file. Reporting "unknown holder" for a race that
    /// resolves in microseconds would make the client-mode banner lie.
    private static func readHolder(fd: Int32) -> Holder? {
        for attempt in 0..<2 {
            lseek(fd, 0, SEEK_SET)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                let text = String(decoding: buffer[0..<n], as: UTF8.self)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                if let first = lines.first, let pid = pid_t(first.trimmingCharacters(in: .whitespaces)) {
                    let exe = lines.count > 1 ? lines[1] : "(unknown)"
                    let bundle = lines.count > 2 && !lines[2].isEmpty ? lines[2] : nil
                    return Holder(pid: pid, executablePath: exe, bundlePath: bundle)
                }
            }
            if attempt == 0 { usleep(50_000) }  // 50ms — the winner's write window
        }
        return nil
    }

    /// This process's bundle path, or nil when it is not a bundled app.
    ///
    /// A headless `gm_kernel daemon` still has a `Bundle.main`, so the presence
    /// of a bundle object proves nothing — what distinguishes the two is whether
    /// it carries an identifier, which only a real `.app` does.
    private static func ownBundlePath() -> String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") ? path : nil
    }

    public enum OwnershipError: Error, CustomStringConvertible {
        case cannotOpenPidfile(errno: Int32)

        public var description: String {
            switch self {
            case .cannotOpenPidfile(let code):
                return "cannot open \(Paths.pidfile.path): \(String(cString: strerror(code)))"
            }
        }
    }
}
