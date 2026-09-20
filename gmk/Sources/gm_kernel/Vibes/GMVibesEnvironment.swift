import Foundation
import Observation
import GmDaemonSdk

enum GMVibesEnvKey: String, CaseIterable, Hashable {
    case gmFsRoot = "GM_FS_ROOT"
    // The kbite roots survive only for the KBites browser's filesystem tabs;
    // they die when the daemon serves kbite tree listings (written goal).
    //
    // Carried onto the GM_ prefix for consistency, not because anything sets
    // them: the session env provisions exactly three vars, and the docs
    // contract has listed this pair as retired for a while. They are a
    // best-effort probe over names nothing writes, which is why the rename is
    // free — but leaving them on the retired prefix would read as an oversight.
    case kbiteDigested = "GM_KBITE_DIGESTED"
    case kbiteOpen = "GM_KBITE_OPEN"
}

/// Locator for the filesystem roots, in two layers with explicit precedence.
///
/// `probed` is synchronous and filled in `init()`, which is why folder-open and the KBites
/// browser survive with the daemon down. `fromDaemon` comes from PATHS_GET and WINS on merge:
/// the daemon's MemoryWatcher is rooted at ITS gmfs root, so a divergent client root would
/// silently mis-resolve memories.
@Observable
@MainActor
final class GMVibesEnvironment {
    private(set) var values: [GMVibesEnvKey: String] = [:]

    private var probed: [GMVibesEnvKey: String] = [:]
    private var fromDaemon: [GMVibesEnvKey: String] = [:]
    private var loadInFlight: Task<Void, Never>?

    subscript(key: GMVibesEnvKey) -> String? { values[key] }

    var isLoaded: Bool { values[.gmFsRoot] != nil }

    init() {
        refresh()
    }

    /// Synchronous fallback resolution for the daemon-down path, and the "Re-scan" affordance.
    ///
    /// THE ROOT COMES FROM `Paths.root`, NEVER FROM A PROBE. A LaunchServices-launched app
    /// inherits no environment, so an env-and-disk probe always answers `~/gmfs` and a
    /// non-production build would paint production chrome over its own data until PATHS_GET
    /// arrived, which is after first paint. `Paths.root` reads the bundle's baked key and
    /// resolves in-process, so the answer is correct at frame zero whatever launched the app.
    func refresh() {
        let env = ProcessInfo.processInfo.environment

        var out: [GMVibesEnvKey: String] = [:]
        for key in GMVibesEnvKey.allCases {
            if let value = env[key.rawValue], !value.isEmpty {
                out[key] = value
            }
        }
        // One resolver for the whole tree. Overrides whatever the environment
        // claimed: the bundle's baked root is the more authoritative answer,
        // and letting an inherited variable win here would reopen exactly the
        // redirection the baked key closed.
        out[.gmFsRoot] = Paths.root.path
        if let root = out[.gmFsRoot] {
            let kbites = URL(fileURLWithPath: root).appendingPathComponent("kbites")
            if out[.kbiteDigested] == nil {
                let digested = kbites.appendingPathComponent("digested")
                if FileManager.default.fileExists(atPath: digested.path) {
                    out[.kbiteDigested] = digested.path
                }
            }
            if out[.kbiteOpen] == nil {
                let open = kbites.appendingPathComponent("open")
                if FileManager.default.fileExists(atPath: open.path) {
                    out[.kbiteOpen] = open.path
                }
            }
        }
        if probed != out { probed = out }
        publish()
    }

    /// Single-flight PATHS_GET — the env is a process-wide singleton, so N
    /// windows' loader tasks must cost ONE round trip on the fairness-free
    /// serial queue, not N (and not 2N on the reconnect stampede, when the
    /// generation restart and the `.paths` yield from invalidateAll() both
    /// fire).
    func loadFromDaemon() async {
        if let running = loadInFlight {
            await running.value
            return
        }
        let task = Task { @MainActor in
            do {
                let response = try await GMCCDaemonService.shared.paths()
                adopt(response)
            } catch {
                // Probe keeps serving; log so a divergent-root situation
                // (daemon root ≠ probed root) is at least diagnosable.
                NSLog(
                    "GMVibes: PATHS_GET failed, keeping probed roots: %@",
                    String(describing: error)
                )
            }
        }
        loadInFlight = task
        await task.value
        loadInFlight = nil
    }

    /// Adopt the daemon's typed roots (PATHS_GET). Strictly an overlay — the
    /// probe stays underneath so a daemon restart never blanks the env.
    /// Roots move as a SET: when the daemon answers with a gmfs root but the
    /// kbite roots are unset daemon-side, they are derived from the daemon's
    /// root rather than left pointing at probe-derived paths under a
    /// possibly-different root.
    func adopt(_ paths: PathsGetResponse) {
        var out: [GMVibesEnvKey: String] = [:]
        if !paths.gmFsRoot.isEmpty { out[.gmFsRoot] = paths.gmFsRoot }
        if !paths.kbiteDigestedRoot.isEmpty { out[.kbiteDigested] = paths.kbiteDigestedRoot }
        if !paths.kbiteOpenRoot.isEmpty { out[.kbiteOpen] = paths.kbiteOpenRoot }
        if let root = out[.gmFsRoot] {
            let kbites = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent("kbites", isDirectory: true)
            if out[.kbiteDigested] == nil {
                out[.kbiteDigested] = kbites.appendingPathComponent("digested").path
            }
            if out[.kbiteOpen] == nil {
                out[.kbiteOpen] = kbites.appendingPathComponent("open").path
            }
        }
        if fromDaemon != out { fromDaemon = out }
        publish()
    }

    private func publish() {
        let merged = probed.merging(fromDaemon) { _, daemon in daemon }
        if values != merged { values = merged }  // change-gated (house idiom)
    }
}
