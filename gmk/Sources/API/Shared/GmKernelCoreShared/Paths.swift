import Foundation

/// Single source of truth for `~/gmfs/`, the ONE top-level filesystem.
///
/// One root is what makes the write-containment rule below a single prefix
/// test; two roots side by side cannot be stated without an exception, and a
/// rule with an exception erodes. Nothing here is committed to git, and
/// **nothing here is CREATED by this type** — see `ensureRuntimeDirs`.
enum Paths {

    // MARK: - The root

    /// The Info.plist key an app bundle bakes its root into.
    ///
    /// A bare Mach-O has no such key, which is why the resolution order below
    /// is correct rather than merely convenient: the arm that cannot apply to
    /// the CLI simply does not fire for it.
    static let bakedRootInfoKey = "GMFSRoot"

    /// The environment name an app bundle declares. Purely informational —
    /// **nothing resolves a path from it**, and it must never become a second
    /// way to answer "which root am I on". The root is the truth; this is a
    /// label for humans reading a plist.
    static let environmentInfoKey = "GMEnvironment"

    /// The resolved filesystem root. **A property of the BITS, not of the
    /// environment.** Order, first arm winning:
    ///   1. `Bundle.main`'s `GMFSRoot`, baked in at build time
    ///   2. `$GM_FS_ROOT`
    ///   3. `~/gmfs`

    /// The bundle key must win: a LaunchServices-launched `.app` inherits no
    /// shell environment, so arm 2 is unreachable from a GUI launch and every
    /// app would land on `~/gmfs` whatever environment the session selected.
    /// Each bundle carries its own root, production included and set
    /// EXPLICITLY, so no launch context can change any app's database. An
    /// `<EnvironmentVariables>` block in the scheme is strictly worse: the
    /// same bits would mean two databases depending on how they were started.
    /// The CLI keeps env resolution, because a CLI does inherit one.

    /// Resolved once per process: the daemon env is a `posix_spawn` snapshot,
    /// so a per-request read would be stale by design, and ONE ROOT PER
    /// PROCESS is a property callers depend on. `$HOME` is a different lever —
    /// `homeDirectoryForCurrentUser` resolves via `getpwuid`, not `$HOME`.
    static let root: URL = {
        if let baked = Bundle.main.object(forInfoDictionaryKey: bakedRootInfoKey) as? String,
            !baked.isEmpty
        {
            return URL(
                fileURLWithPath: (baked as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        if let override = ProcessInfo.processInfo.environment["GM_FS_ROOT"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return defaultProductionRoot
    }()

    /// `~/gmfs` — where production lives, and the fallback when nothing else
    /// answers.
    ///
    /// Production deliberately keeps this path rather than becoming
    /// `~/prod_gmfs` for symmetry with the other environments: renaming it
    /// would mean rewriting the absolute `daemon_config` roots against the
    /// documented rollback anchor and tripping `migrate_to_gmfs.sh`'s own
    /// refusal check, all to make three names look alike.
    static var defaultProductionRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmfs", isDirectory: true)
    }

    /// Whether this process is looking at the production root.
    ///
    /// **Compares INODES, not paths.** `standardizedFileURL` does not resolve
    /// symlinks, so a symlink, an APFS firmlink, or `/Users` vs
    /// `/System/Volumes/Data/Users` would make one root look like two, and a
    /// false answer here paints the non-production red bar over LIVE
    /// PRODUCTION DATA. Keyed on `gm.db` rather than the directory: two roots
    /// sharing a `gm.db` inode ARE the same environment, whatever their paths.
    static var isProductionRoot: Bool {
        isSameRoot(root, defaultProductionRoot)
    }

    /// Inode-equality of two roots, via their `gm.db`.
    ///
    /// Returns false when either database is absent — an environment that has
    /// never booted is not yet provably production, and guessing "yes" would
    /// suppress the warning chrome on a root we know nothing about.
    static func isSameRoot(_ a: URL, _ b: URL) -> Bool {
        var sa = stat(), sb = stat()
        let pa = a.appendingPathComponent("gm.db", isDirectory: false).path
        let pb = b.appendingPathComponent("gm.db", isDirectory: false).path
        guard stat(pa, &sa) == 0, stat(pb, &sb) == 0 else { return false }
        return sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino
    }

    /// The environment label this bundle declares, or nil for the CLI and for
    /// production bundles that declare none.
    ///
    /// FOR DISPLAY ONLY. Never resolve a path from it: a label and a root that
    /// can disagree is a second source of truth, and the whole point of the
    /// baked root is that there is exactly one.
    static var declaredEnvironmentName: String? {
        Bundle.main.object(forInfoDictionaryKey: environmentInfoKey) as? String
    }

    // MARK: - Daemon runtime state

    /// `~/gmfs/gm.db`
    static var db: URL {
        root.appendingPathComponent("gm.db", isDirectory: false)
    }

    /// `~/gmfs/daemon.sock`
    static var socket: URL {
        root.appendingPathComponent("daemon.sock", isDirectory: false)
    }

    /// `~/gmfs/daemon.pid`
    static var pidfile: URL {
        root.appendingPathComponent("daemon.pid", isDirectory: false)
    }

    /// `~/gmfs/daemon.log`
    static var log: URL {
        root.appendingPathComponent("daemon.log", isDirectory: false)
    }

    /// `~/gmfs/backups/`
    static var backups: URL {
        root.appendingPathComponent("backups", isDirectory: true)
    }

    // MARK: - Binaries

    /// `~/gmfs/bin/`
    static var bin: URL {
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
    static var binKernel: URL {
        bin.appendingPathComponent("gm_kernel", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_daemon` — a symlink to `gm_kernel`; argv[0] selects the
    /// headless daemon personality.
    static var binDaemon: URL {
        bin.appendingPathComponent("gm_daemon", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_mcp`
    static var binMcp: URL {
        bin.appendingPathComponent("gm_mcp", isDirectory: false)
    }

    /// `~/gmfs/bin/gm_hook`
    static var binHook: URL {
        bin.appendingPathComponent("gm_hook", isDirectory: false)
    }

    /// `~/gmfs/bin/.gm_version` — the install stamp. The FILENAME carried the
    /// retired prefix too, which is why it is named here rather than composed
    /// at each of its call sites.
    static var versionStamp: URL {
        bin.appendingPathComponent(".gm_version", isDirectory: false)
    }

    // MARK: - Content

    /// `~/gmfs/` — the content root. Identical to `root` by construction, and
    /// named separately on purpose: it is the successor to the retired separate
    /// content root, and the call sites that meant "content" are
    /// worth keeping distinguishable from the ones that meant "runtime". If the
    /// two ever need to diverge again, this is the one line that changes.
    static var contentRoot: URL { root }

    /// `~/gmfs/projects/` — what every `gmfs_relative_storage_path` resolves
    /// against. Those columns are RELATIVE by design; this is the only place
    /// the absolute half lives.
    static var projectsRoot: URL {
        contentRoot.appendingPathComponent("projects", isDirectory: true)
    }

    /// `~/gmfs/kbites/`
    static var kbitesRoot: URL {
        contentRoot.appendingPathComponent("kbites", isDirectory: true)
    }

    /// `~/gmfs/kbites/open/`
    static var kbitesOpenRoot: URL {
        kbitesRoot.appendingPathComponent("open", isDirectory: true)
    }

    /// `~/gmfs/kbites/digested/`
    static var kbitesDigestedRoot: URL {
        kbitesRoot.appendingPathComponent("digested", isDirectory: true)
    }

    // MARK: - Write containment

    struct ContainmentViolation: Error, CustomStringConvertible {
        let attempted: String
        let allowed: [String]
        var description: String {
            "refusing to write outside the permitted roots: \(attempted) is under "
                + "none of \(allowed.joined(separator: ", "))"
        }
    }

    /// The write-containment invariant, ENFORCED rather than documented:
    /// *never write files outside either gmfs or the working repo.*
    ///
    /// `repoRoot` is the working repo when a caller has resolved one; a caller
    /// with no repo context passes nil and gets the strict gmfs-only rule.
    /// Paths are compared after `standardizedFileURL` resolution so `..`
    /// cannot smuggle a write out, and the prefix test is on a path-component
    /// boundary so `~/gmfs-evil` is not inside `~/gmfs`.
    static func assertContained(_ url: URL, repoRoot: URL? = nil) throws {
        let permitted = ([root] + (repoRoot.map { [$0] } ?? []))
            .map(\.standardizedFileURL.path)
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
    /// the layout; populating `~/gmfs` belongs to the cutover step alone. A
    /// stray call would have a build create a runtime root as a side effect,
    /// on a machine whose test suite must be unable to touch anything outside
    /// a temp dir.
    static func ensureRuntimeDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
    }
}
