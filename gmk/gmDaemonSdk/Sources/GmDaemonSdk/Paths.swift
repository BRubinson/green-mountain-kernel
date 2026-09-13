import Foundation

/// Single source of truth for `~/gmfs/`, the ONE top-level filesystem.
///
/// `~/gmfs/` replaces what used to be TWO sibling roots — one for binaries and
/// daemon runtime state, a second for per-repo content. The collapse is
/// not tidying: it is what makes the write-containment rule below expressible
/// as a single prefix test. Two roots beside each other cannot be stated as
/// "never write outside gmfs or the working repo" without immediately needing
/// an exception, and a rule with an exception erodes.
///
/// Nothing here is committed to git, and — importantly — **nothing here is
/// CREATED by this type**. See `ensureRuntimeDirs`.
public enum Paths {

    // MARK: - The root

    /// `~/gmfs/`, or `$GM_FS_ROOT` when set — the sandbox escape hatch, and now
    /// the ONLY root var. Resolved once per process: the daemon env is a
    /// posix_spawn snapshot, so a per-request read would be stale by design.
    /// HOME overrides cannot work here (homeDirectoryForCurrentUser resolves
    /// via getpwuid, not $HOME).
    public static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["GM_FS_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmfs", isDirectory: true)
    }()

    // MARK: - Daemon runtime state

    /// `~/gmfs/gm.db`
    public static var db: URL {
        root.appendingPathComponent("gm.db", isDirectory: false)
    }

    /// `~/gmfs/daemon.sock`
    public static var socket: URL {
        root.appendingPathComponent("daemon.sock", isDirectory: false)
    }

    /// `~/gmfs/daemon.pid`
    public static var pidfile: URL {
        root.appendingPathComponent("daemon.pid", isDirectory: false)
    }

    /// `~/gmfs/daemon.log`
    public static var log: URL {
        root.appendingPathComponent("daemon.log", isDirectory: false)
    }

    /// `~/gmfs/backups/`
    public static var backups: URL {
        root.appendingPathComponent("backups", isDirectory: true)
    }

    // MARK: - Binaries

    /// `~/gmfs/bin/`
    public static var bin: URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    /// `~/gmfs/bin/gm_kernel` — the ONE staged Mach-O.
    ///
    /// `binDaemon`, `binMcp` and `binHook` below are now SYMLINK names pointing
    /// here, not separate binaries. Keeping them as named accessors rather than
    /// collapsing every caller onto this one is deliberate: the entry-point
    /// names are what `hooks.json`, `.mcp.json`, `run_mcp.sh` and
    /// `check_gm_stale.sh` resolve, and argv[0] is what the multi-call dispatch
    /// reads — so the names are load-bearing even though the inode is shared.
    public static var binKernel: URL {
        bin.appendingPathComponent("gm_kernel", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_daemon` — a symlink to `gm_kernel`; argv[0] selects the
    /// headless daemon personality.
    public static var binDaemon: URL {
        bin.appendingPathComponent("gm_daemon", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_mcp`
    public static var binMcp: URL {
        bin.appendingPathComponent("gm_mcp", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_hook`
    public static var binHook: URL {
        bin.appendingPathComponent("gm_hook", isDirectory: false)
    }

    /// `~/gmfs/bin/.gm_version` — the install stamp. The FILENAME carried the
    /// retired prefix too, which is why it is named here rather than composed
    /// at each of its call sites.
    public static var versionStamp: URL {
        bin.appendingPathComponent(".gm_version", isDirectory: false)
    }

    // MARK: - Content

    /// `~/gmfs/` — the content root. Identical to `root` by construction, and
    /// named separately on purpose: it is the successor to the retired separate
    /// content root, and the call sites that meant "content" are
    /// worth keeping distinguishable from the ones that meant "runtime". If the
    /// two ever need to diverge again, this is the one line that changes.
    public static var contentRoot: URL { root }

    /// `~/gmfs/projects/` — what every `gmfs_relative_storage_path` resolves
    /// against. Those columns are RELATIVE by design; this is the only place
    /// the absolute half lives.
    public static var projectsRoot: URL {
        contentRoot.appendingPathComponent("projects", isDirectory: true)
    }

    /// `~/gmfs/kbites/`
    public static var kbitesRoot: URL {
        contentRoot.appendingPathComponent("kbites", isDirectory: true)
    }

    /// `~/gmfs/kbites/open/`
    public static var kbitesOpenRoot: URL {
        kbitesRoot.appendingPathComponent("open", isDirectory: true)
    }

    /// `~/gmfs/kbites/digested/`
    public static var kbitesDigestedRoot: URL {
        kbitesRoot.appendingPathComponent("digested", isDirectory: true)
    }

    // MARK: - Write containment

    public struct ContainmentViolation: Error, CustomStringConvertible {
        public let attempted: String
        public let allowed: [String]
        public var description: String {
            "refusing to write outside the permitted roots: \(attempted) is under "
            + "none of \(allowed.joined(separator: ", "))"
        }
    }

    /// The write-containment invariant, ENFORCED rather than documented:
    /// *never write files outside either gmfs or the working repo.*
    ///
    /// The reason this is a throwing choke point and not a comment: a rule that
    /// lives only in prose is obeyed exactly as long as everyone who adds a
    /// write has read the prose, which is a guarantee that decays with every
    /// contributor. This one fails the write.
    ///
    /// `repoRoot` is the working repo when there is one — a caller that has
    /// already resolved it (from a git toplevel, or a hook payload's cwd) hands
    /// it in. A caller with no repo context passes nil and gets the strict
    /// gmfs-only rule, which is the correct default: code that does not know
    /// where the repo is has no business writing into one.
    ///
    /// Paths are compared after `standardizedFileURL` resolution so `..`
    /// traversal cannot smuggle a write out of the root, and the prefix test is
    /// on a path-component boundary so `~/gmfs-evil` is not read as being
    /// inside `~/gmfs`.
    public static func assertContained(_ url: URL, repoRoot: URL? = nil) throws {
        let permitted = ([root] + (repoRoot.map { [$0] } ?? []))
            .map { $0.standardizedFileURL.path }
        let target = url.standardizedFileURL.path
        for allowed in permitted where target == allowed || target.hasPrefix(allowed + "/") {
            return
        }
        throw ContainmentViolation(attempted: target, allowed: permitted)
    }

    // MARK: - Directory creation

    /// Create `~/gmfs/`, `~/gmfs/bin/` and `~/gmfs/backups/` if missing.
    /// Idempotent.
    ///
    /// DELIBERATELY NOT CALLED FROM ANY BUILD OR TEST PATH. This type DEFINES
    /// the layout; populating `~/gmfs` belongs to the migration/cutover step
    /// and to nothing else. A stray call here would have the build itself
    /// create a runtime root as a side effect — on a machine where the old
    /// runtime is still the live one, and where the test suite is supposed to
    /// be provably unable to touch anything outside a temp dir.
    public static func ensureRuntimeDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
    }
}
