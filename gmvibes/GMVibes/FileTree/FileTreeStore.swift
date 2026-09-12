import Foundation
import Observation

// Polled directory snapshots backing the Memories file explorer — the one
// surviving slice of the old ckfs filesystem facade. memory/*.md content stays
// on the filesystem by design (the db stores artifact pointers only), and the
// filesystem emits no daemon events, so this store keeps its page-driven 1s
// refresh honestly.

@Observable
@MainActor
final class FileTreeStore {
    static let shared = FileTreeStore()
    private init() {}

    // Keyed by the walked root URL; refreshed on the page's 1s cadence so live
    // agent writes appear.
    private(set) var fileTrees: [URL: FileTreeNode] = [:]

    // Re-walk a directory subtree off the main actor and publish only if it
    // actually changed (same shape + mtimes ⇒ no @Observable churn, so the
    // explorer's selection/expansion don't thrash on every 1s tick).
    func refreshFileTree(at root: URL) async {
        let tree = await Task.detached(priority: .userInitiated) {
            FileTreeNode.walk(root)
        }.value
        if fileTrees[root] != tree { fileTrees[root] = tree }
    }

    // MARK: - Raw file body (lazy reads)

    nonisolated static func readRawFile(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
