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

    /// The Info.plist key an app bundle bakes its root into.
    ///
    /// A bare Mach-O has no such key, which is why the resolution order below
    /// is correct rather than merely convenient: the arm that cannot apply to
    /// the CLI simply does not fire for it.
    public static let bakedRootInfoKey = "GMFSRoot"

    /// The environment name an app bundle declares. Purely informational —
    /// **nothing resolves a path from it**, and it must never become a second
    /// way to answer "which root am I on". The root is the truth; this is a
    /// label for humans reading a plist.
    public static let environmentInfoKey = "GMEnvironment"

    /// The resolved filesystem root. **A property of the BITS, not of the
    /// environment.**
    ///
    /// Order — and the first arm coming FIRST is the whole point:
    ///   1. `Bundle.main`'s `GMFSRoot`, baked in at build time
    ///   2. `$GM_FS_ROOT`
    ///   3. `~/gmfs`
    ///
    /// ## Why the bundle key has to win
    ///
    /// A LaunchServices-launched `.app` inherits **no shell environment at
    /// all**, so arm 2 is unreachable from a GUI launch and the app would
    /// always land on `~/gmfs` no matter what the session that "selected" an
    /// environment said. That is exactly the silent-data hazard that got the
    /// previous snapshot dev loop deleted, and the recorded verdict was that
    /// "every available mitigation was a detection mechanism". A T overlay and
    /// a red bar are detection mechanisms: they make a wrong state visible,
    /// they do not make it impossible.
    ///
    /// Baking the root into the bundle DISSOLVES the hazard instead. Each
    /// bundle carries its own root — production included, set EXPLICITLY rather
    /// than left to the fallback — so no launch context (Finder, Dock,
    /// `open -n`, Xcode Run, a LaunchServices crash-relaunch) can change any
    /// app's database.
    ///
    /// The tempting alternative — an `<EnvironmentVariables>` block in the
    /// scheme — is STRICTLY WORSE than what was deleted: the same bits would
    /// mean two different databases depending on whether you hit Run or
    /// double-clicked.
    ///
    /// This also closes a live bug. Before this ordering, any shell that
    /// exported `GM_FS_ROOT` and then ran `open -a` handed the PRODUCTION app a
    /// different database.
    ///
    /// The CLI keeps env resolution, and the asymmetry is correct rather than
    /// inconsistent: it mirrors the asymmetry in reality, where one shape
    /// inherits an environment and the other does not.
    ///
    /// Resolved once per process: the daemon env is a `posix_spawn` snapshot,
    /// so a per-request read would be stale by design — and ONE ROOT PER
    /// PROCESS is a property callers depend on, not an accident.
    /// HOME overrides cannot work here (`homeDirectoryForCurrentUser` resolves
    /// via `getpwuid`, not `$HOME`), so `$HOME` and `GM_FS_ROOT` are different
    /// levers and setting one does not move the other.
    public static let root: URL = {
        if let baked = Bundle.main.object(forInfoDictionaryKey: bakedRootInfoKey) as? String,
           !baked.isEmpty {
            return URL(fileURLWithPath: (baked as NSString).expandingTildeInPath,
                       isDirectory: true)
        }
        if let override = ProcessInfo.processInfo.environment["GM_FS_ROOT"],
           !override.isEmpty {
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
    public static var defaultProductionRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmfs", isDirectory: true)
    }

    /// Whether this process is looking at the production root.
    ///
    /// **Compares INODES, not paths**, and that is load-bearing rather than
    /// fastidious. `standardizedFileURL` does not resolve symlinks, so a
    /// `~/prod_gmfs` symlink, an APFS firmlink, or `/Users` vs
    /// `/System/Volumes/Data/Users` would all make one root look like two. A
    /// false answer here paints the non-production chrome — the red bar — over
    /// LIVE PRODUCTION DATA, which is the badge lying at the exact moment it
    /// matters most, and precisely the failure the baked-root design exists to
    /// prevent.
    ///
    /// Keyed on `gm.db` rather than the directory because the database is the
    /// thing whose identity actually matters; two roots sharing a `gm.db` inode
    /// ARE the same environment whatever their paths say.
    public static var isProductionRoot: Bool {
        isSameRoot(root, defaultProductionRoot)
    }

    /// Inode-equality of two roots, via their `gm.db`.
    ///
    /// Returns false when either database is absent — an environment that has
    /// never booted is not yet provably production, and guessing "yes" would
    /// suppress the warning chrome on a root we know nothing about.
    public static func isSameRoot(_ a: URL, _ b: URL) -> Bool {
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
    public static var declaredEnvironmentName: String? {
        Bundle.main.object(forInfoDictionaryKey: environmentInfoKey) as? String
    }

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
