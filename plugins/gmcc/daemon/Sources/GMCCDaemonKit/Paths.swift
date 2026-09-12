import Foundation

/// Single source of truth for the `~/gmcc/` runtime directory conventions.
///
/// The runtime dir is created by the build/install script (or lazily by the
/// daemon) and is
/// never committed to git. Distinct from `~/gmcc_ckfs/` — that tree holds the
/// per-repo CKFS yamls; `~/gmcc/` holds binaries and daemon runtime state.
public enum Paths {
    /// `~/gmcc/`, or `$GMCC_ROOT` when set — the sandbox escape hatch. Resolved
    /// once per process: the daemon env is a posix_spawn snapshot, so a
    /// per-request read would be stale by design. HOME overrides cannot work
    /// here (homeDirectoryForCurrentUser resolves via getpwuid, not $HOME).
    public static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["GMCC_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmcc", isDirectory: true)
    }()

    /// `~/gmcc/bin/`
    public static var bin: URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    /// `~/gmcc/bin/gm`
    public static var binGm: URL {
        bin.appendingPathComponent("gm", isDirectory: false)
    }

    /// `~/gmcc/bin/gmcc_daemon`
    public static var binDaemon: URL {
        bin.appendingPathComponent("gmcc_daemon", isDirectory: false)
    }

    /// `~/gmcc/daemon.sock`
    public static var socket: URL {
        root.appendingPathComponent("daemon.sock", isDirectory: false)
    }

    /// `~/gmcc/daemon.pid`
    public static var pidfile: URL {
        root.appendingPathComponent("daemon.pid", isDirectory: false)
    }

    /// `~/gmcc/daemon.log`
    public static var log: URL {
        root.appendingPathComponent("daemon.log", isDirectory: false)
    }

    /// `~/gmcc/gmcc.db`
    public static var db: URL {
        root.appendingPathComponent("gmcc.db", isDirectory: false)
    }

    /// `~/gmcc/backups/`
    public static var backups: URL {
        root.appendingPathComponent("backups", isDirectory: true)
    }

    /// Create `~/gmcc/`, `~/gmcc/bin/`, and `~/gmcc/backups/` if missing. Idempotent.
    public static func ensureRuntimeDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
    }
}
