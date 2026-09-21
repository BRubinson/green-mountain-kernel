import Foundation

/// Filesystem events for prompt memory/ directories — one watched root (the
/// gmfs root), stream plumbing delegated to FSEventLane, so a config change
/// pushes a new root rather than replacing the watcher.
///
/// Lane contract: holds no Store and no Server; the 1.0s latency debounces a
/// save storm into one callback; events are EPHEMERAL, broadcast-only with id 0
/// and no daemon_event row. Prompt resolution is case-sensitive equality on the
/// stored gmfs_relative_storage_path; a row without one keeps the client poll.
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

    /// Pushed by the supervisor. nil or a nonexistent path stops the stream, so
    /// a machine with no gmfs simply has no watcher. Idempotent via the lane.
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
