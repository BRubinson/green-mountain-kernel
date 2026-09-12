import Foundation

/// Filesystem events for prompt memory/ directories — one watched root
/// (the ckfs root), stream plumbing delegated to FSEventLane so re-rooting
/// (A3) comes for free: the watcher is constructed once and lives for the
/// daemon's lifetime; a config change pushes a new root rather than
/// replacing the object.
///
/// HARD RULES (the lane contract):
///   1. Holds NO Store and NO Server reference — `deliver` hops onto the
///      server queue and does everything there.
///   2. The lane's 1.0s latency is the debounce — an editor save storm
///      becomes one callback per window.
///   3. Events are EPHEMERAL: no daemon_event row, broadcast-only with id 0
///      (never a replay cursor). A filesystem hint needs no durability.
///
/// EXACT-MATCH CONTRACT (A4): the prompt's stored ckfs_relative_storage_path
/// is the authority. Resolution is case-sensitive string equality, so whoever
/// creates the directory MUST use the path the daemon returned from
/// PROMPT_CREATE, byte for byte — never re-derive {seq}_{name} client-side
/// (the daemon now slugs the name at derivation).
///
/// Honest limitation: only prompts with a non-empty ckfs_relative_storage_path
/// resolve; a prompt row without one keeps the client-side poll.
final class MemoryWatcher: @unchecked Sendable {
    private let lane = FSEventLane(label: "gmcc.daemon.lane", latency: 1.0)
    /// Lane-confined: mutated only inside a lane turn, read only by the
    /// filter, which also runs there.
    private var root: String = ""
    private let deliver: @Sendable (_ promptStoragePath: String) -> Void

    init(deliver: @escaping @Sendable (String) -> Void) {
        self.deliver = deliver
        lane.setHandler { [weak self] paths in self?.handle(paths: paths) }
    }

    /// A3 entry point, pushed by the supervisor. nil or a nonexistent path
    /// stops the stream — a daemon on a machine with no ckfs simply has no
    /// watcher, same as at boot. Idempotent via the lane.
    func setRoot(_ newRoot: String?) {
        let resolved = newRoot ?? ""
        lane.run { self.root = resolved }
        lane.setPaths(resolved.isEmpty ? [] : [resolved])
    }

    func stop() {
        lane.stop()
    }

    /// Runs on the lane. Reduces raw event paths to the set of distinct
    /// prompt storage paths whose memory/ subtree changed, then delivers each.
    private func handle(paths: [String]) {
        guard !root.isEmpty else { return }
        var promptPaths: Set<String> = []
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        for path in paths {
            guard path.hasPrefix(rootPrefix) else { continue }
            let relative = String(path.dropFirst(rootPrefix.count))
            // development/ holds the local-dev sandbox (its own db/ckfs/repo
            // churn). Prune it here to stop the event traffic; even without
            // this, the exact-match contract (A4) can never bind a
            // development/… relative to a stored projects/… path.
            guard !relative.hasPrefix("development/") else { continue }
            // Expect …/prompts/{seq}_{name}/memory[/…] — anchor on the memory
            // segment and keep everything before it as the prompt folder.
            guard let memoryRange = relative.range(of: "/memory") else { continue }
            let promptFolder = String(relative[..<memoryRange.lowerBound])
            guard promptFolder.contains("/prompts/") else { continue }
            // The path must END at the prompt folder boundary: reject
            // lookalikes such as …/memory_bak by requiring the next char (if
            // any) to be a slash.
            let after = relative[memoryRange.upperBound...]
            guard after.isEmpty || after.hasPrefix("/") else { continue }
            promptPaths.insert(promptFolder)
        }
        for promptPath in promptPaths.sorted() {
            deliver(promptPath)
        }
    }
}
