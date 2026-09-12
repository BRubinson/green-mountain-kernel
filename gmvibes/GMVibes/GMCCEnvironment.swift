import Foundation
import Observation
import GMCCDaemonKit

enum GMCCEnvKey: String, CaseIterable, Hashable {
    case ckfsRoot       = "GMCC_CKFS_ROOT"
    // The kbite roots survive only for the KBites browser's filesystem tabs;
    // they die when the daemon serves kbite tree listings (written goal).
    case kbiteDigested  = "GMCC_KBITE_DIGESTED"
    case kbiteOpen      = "GMCC_KBITE_OPEN"
}

/// Locator for the filesystem roots (memory files, folder-open actions, KBites
/// browse tabs). Two layers with explicit precedence:
///
/// - `probed` — process environment + conventional-location probe. Synchronous,
///   filled in `init()`, and the reason folder-open and the KBites browser
///   survive with the daemon down.
/// - `fromDaemon` — PATHS_GET, adopted asynchronously by the window root's
///   loader task (on `daemon.generation` and `.paths` invalidations). WINS on
///   merge: the daemon's MemoryWatcher is rooted at ITS ckfs root, so a
///   divergent client root would silently mis-resolve memories, and a
///   Finder-launched app's stale exported var is the likelier wrong answer.
@Observable
@MainActor
final class GMCCEnvironment {
    private(set) var values: [GMCCEnvKey: String] = [:]

    private var probed: [GMCCEnvKey: String] = [:]
    private var fromDaemon: [GMCCEnvKey: String] = [:]
    private var loadInFlight: Task<Void, Never>?

    subscript(key: GMCCEnvKey) -> String? { values[key] }

    var isLoaded: Bool { values[.ckfsRoot] != nil }

    init() {
        refresh()
    }

    /// Synchronous fallback resolution (daemon-down path). Kept as the
    /// "Re-scan" affordance too.
    func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment

        var out: [GMCCEnvKey: String] = [:]
        for key in GMCCEnvKey.allCases {
            if let value = env[key.rawValue], !value.isEmpty {
                out[key] = value
            }
        }
        // Conventional-location probe: the standard install puts the ckfs at
        // ~/gmcc_ckfs (and kbites under it).
        if out[.ckfsRoot] == nil {
            let conventional = home.appendingPathComponent("gmcc_ckfs")
            if FileManager.default.fileExists(atPath: conventional.path) {
                out[.ckfsRoot] = conventional.path
            }
        }
        if let root = out[.ckfsRoot] {
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
                NSLog("GMVibes: PATHS_GET failed, keeping probed roots: %@",
                      String(describing: error))
            }
        }
        loadInFlight = task
        await task.value
        loadInFlight = nil
    }

    /// Adopt the daemon's typed roots (PATHS_GET). Strictly an overlay — the
    /// probe stays underneath so a daemon restart never blanks the env.
    /// Roots move as a SET: when the daemon answers with a ckfs root but the
    /// kbite roots are unset daemon-side, they are derived from the daemon's
    /// root rather than left pointing at probe-derived paths under a
    /// possibly-different root.
    func adopt(_ paths: PathsGetResponse) {
        var out: [GMCCEnvKey: String] = [:]
        if !paths.ckfsRoot.isEmpty { out[.ckfsRoot] = paths.ckfsRoot }
        if !paths.kbiteDigestedRoot.isEmpty { out[.kbiteDigested] = paths.kbiteDigestedRoot }
        if !paths.kbiteOpenRoot.isEmpty { out[.kbiteOpen] = paths.kbiteOpenRoot }
        if let root = out[.ckfsRoot] {
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
        if values != merged { values = merged }   // change-gated (house idiom)
    }
}
