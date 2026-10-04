import Foundation

/// Filesystem events for instance repos' git directories (paths ending /HEAD).
///
/// Watches git DIRECTORY, not repository root, to avoid firing on every source
/// file save. Lane contract: no Store, no Server; `deliver` hops to server queue
/// which resolves head state and dedupes against per-instance cache, so only
/// genuine changes broadcast.
final class CheckoutFSEventLane: @unchecked Sendable {
    private let lane = FSEventLane(label: "gmcc.daemon.git", latency: 0.5)
    /// Lane-confined: gitDir → (instanceUuid, repoRoot).
    private var byGitDir: [String: (instanceUuid: String, repoRoot: String)] = [:]
    private let deliver: @Sendable (_ instanceUuid: String, _ repoRoot: String) -> Void

    /// Creates a filesystem event watcher for git directories.
    ///
    /// - Parameter deliver: Callback invoked on genuine HEAD changes,
    ///   receives instance UUID and repo root.
    init(deliver: @escaping @Sendable (String, String) -> Void) {
        self.deliver = deliver
        lane.setHandler { [weak self] paths in self?.handle(paths: paths) }
    }

    /// Updates the set of git directories to watch.
    ///
    /// Pushed by the supervisor. Idempotent; previous roots are replaced.
    ///
    /// - Parameter roots: Array of instance UUID, repo root, and git directory tuples.
    func setRoots(_ roots: [(instanceUuid: String, repoRoot: String, gitDir: String)]) {
        lane.run {
            self.byGitDir = Dictionary(
                roots.map { ($0.gitDir, ($0.instanceUuid, $0.repoRoot)) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        lane.setPaths(roots.map(\.gitDir))
    }

    /// Stops watching for filesystem events.
    func stop() {
        lane.stop()
    }

    /// Processes filesystem event paths and delivers changes to interested instances.
    ///
    /// Only HEAD file changes trigger deliveries. Runs on the lane; dedupes per
    /// flush window. Handles nested worktree git directories correctly.
    ///
    /// - Parameter paths: Changed paths from the filesystem event.
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
