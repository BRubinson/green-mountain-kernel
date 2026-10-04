import Foundation

/// Who owns the database, decided before anything can open it.
///
/// LaunchServices gives one instance per bundle PATH, not per application, so a
/// debug build beside the installed app is a second process that would open the
/// same `gm.db` through GRDB's WAL — unrecoverable in append-only history. The
/// lock is therefore the only way to obtain the capability: `Token` cannot be
/// constructed outside this file, `acquire()` is its only producer, and
/// `KernelWriter.start` — the single `Store(path:)` site — consumes one.
enum KernelOwnership {

    /// Proof that this process holds the exclusive database lock.
    ///
    /// `~Copyable` so it cannot be duplicated into a second writer, and its
    /// initialiser is `fileprivate` so `acquire()` is the only thing that can
    /// mint one. The held descriptor is never closed: the lock is meant to last
    /// for the process's lifetime, and letting the kernel release it at exit is
    /// what makes a CRASHED kernel leave no stale lock behind.
    struct Token: ~Copyable {
        fileprivate let fd: Int32
    }

    /// Who holds the lock, when we did not get it.
    struct Holder: Sendable, Equatable {
        let pid: pid_t
        let executablePath: String
        /// nil means the holder is HEADLESS — a `gm_kernel daemon` process
        /// rather than an app bundle.
        ///
        /// The distinction decides what a losing app does next: take over from a headless writer, but never from
        /// another app copy.
        let bundlePath: String?
    }

    enum Outcome: ~Copyable {
        case acquired(Token)
        case heldBy(Holder)
    }

    /// Take the lock, or report who has it.
    ///
    /// The ORDER below is the invariant, not the lock itself. Every step that
    /// could touch the database happens after the `flock`, and the `.heldBy`
    /// path has no fall-through — it cannot reach a `Store` even by accident,
    /// because it does not produce a `Token`.
    /// Attempts to acquire the ownership lock for this kernel instance.
    ///
    /// - Returns: An `Outcome.acquired` with a lock token on success, or `Outcome.heldBy` if already held by another process.
    /// - Throws: `OwnershipError` errors if the lock cannot be acquired due to system errors.
    static func acquire() throws -> Outcome {
        try Paths.ensureRuntimeDirs()

        // The pidfile is DELIBERATELY `daemon.pid` in every root. A renamed
        // pidfile is a DIFFERENT LOCK: two instances would each hold one and
        // write the same database believing each was alone.
        let fd = open(Paths.pidfile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw OwnershipError.cannotOpenPidfile(errno: errno)
        }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            // Do NOT close `fd` on this path before reading: the holder's record
            // is in this same file, and we still need to read it.
            let holder = readHolder(fd: fd)
            close(fd)
            return .heldBy(
                holder
                    ?? Holder(
                        pid: 0,
                        executablePath: "(unknown — pidfile unreadable)",
                        bundlePath: nil
                    )
            )
        }

        // Won it. Record WHO we are, so a loser can name us.
        ftruncate(fd, 0)
        let record =
            [
                "\(getpid())",
                Bundle.main.executablePath ?? CommandLine.arguments.first ?? "(unknown)",
                Self.ownBundlePath() ?? "",
            ]
            .joined(separator: "\n") + "\n"
        _ = record.withCString { write(fd, $0, strlen($0)) }

        return .acquired(Token(fd: fd))
    }

    /// Reads the current lock holder without attempting to acquire the lock.
    ///
    /// Used by the menu bar to name the owning process in client mode.
    ///
    /// - Returns: The current holder information, or nil if the pidfile cannot be read.
    static func readHolder() -> Holder? {
        let fd = open(Paths.pidfile.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return readHolder(fd: fd)
    }

    /// Reads holder information from the pidfile descriptor.
    ///
    /// Parses three lines: pid, executable path, bundle path (empty when headless).
    /// This is the only reader of the contents; one retry handles the race window
    /// between `ftruncate` and `write`.
    ///
    /// - Parameter fd: The file descriptor for the pidfile.
    /// - Returns: The holder information, or nil if the file is unreadable or improperly formatted.
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

    /// Returns this process's bundle path if it is a bundled app.
    ///
    /// A headless `gm_kernel daemon` has a `Bundle.main` but no identifier;
    /// only a real `.app` carries an identifier and a `.app` suffix.
    ///
    /// - Returns: The bundle path ending in `.app`, or nil if not a bundled app.
    private static func ownBundlePath() -> String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") ? path : nil
    }

    enum OwnershipError: Error, CustomStringConvertible {
        case cannotOpenPidfile(errno: Int32)

        var description: String {
            switch self {
            case .cannotOpenPidfile(let code):
                return "cannot open \(Paths.pidfile.path): \(String(cString: strerror(code)))"
            }
        }
    }
}
