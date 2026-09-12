import Foundation

/// A8's source: filesystem events for instance repos' git directories,
/// filtered to HEAD itself. Watches the git DIRECTORY, never the repository
/// root — the root would fire on every source file the user saves. Everything
/// else under the git dir is noise too (index, refs, objects, packed-refs, gc
/// temp files), so only paths ending in /HEAD are delivered.
///
/// Same lane contract as MemoryWatcher: no Store, no Server; `deliver` hops
/// onto the server queue, which resolves the head state there (the same tiny
/// HEAD read the poll messages already perform) and dedupes against its own
/// per-instance last-emitted cache — only a genuine change broadcasts.
final class CheckoutWatcher: @unchecked Sendable {
    private let lane = FSEventLane(label: "gmcc.daemon.git", latency: 0.5)
    /// Lane-confined: gitDir → (instanceUuid, repoRoot).
    private var byGitDir: [String: (instanceUuid: String, repoRoot: String)] = [:]
    private let deliver: @Sendable (_ instanceUuid: String, _ repoRoot: String) -> Void

    init(deliver: @escaping @Sendable (String, String) -> Void) {
        self.deliver = deliver
        lane.setHandler { [weak self] paths in self?.handle(paths: paths) }
    }

    /// Pushed by the supervisor. Idempotent via the lane.
    func setRoots(_ roots: [(instanceUuid: String, repoRoot: String, gitDir: String)]) {
        lane.run {
            self.byGitDir = Dictionary(
                roots.map { ($0.gitDir, ($0.instanceUuid, $0.repoRoot)) },
                uniquingKeysWith: { first, _ in first })
        }
        lane.setPaths(roots.map(\.gitDir))
    }

    func stop() {
        lane.stop()
    }

    /// Runs on the lane. Only HEAD matters; dedupe per flush window.
    private func handle(paths: [String]) {
        var hit: Set<String> = []
        for path in paths {
            guard path == "HEAD" || path.hasSuffix("/HEAD") else { continue }
            // Longest byGitDir key that prefixes the path (worktree gitdirs
            // can nest under a shared .git).
            let owner = byGitDir.keys
                .filter { path == $0 + "/HEAD" || path.hasPrefix($0 + "/") }
                .max(by: { $0.count < $1.count })
            if let owner { hit.insert(owner) }
        }
        for gitDir in hit.sorted() {
            if let entry = byGitDir[gitDir] {
                deliver(entry.instanceUuid, entry.repoRoot)
            }
        }
    }
}
