import Foundation
import Observation

// Polled directory snapshots backing the Memories file explorer. Markdown under a prompt's
// memory directory lives on the filesystem by design (the db stores artifact pointers only),
// and the filesystem emits no daemon events, so this store polls on a page-driven 1s cadence.

@Observable
@MainActor
final class FileTreeStore {
    static let shared = FileTreeStore()
    /// Create the shared file tree store.
    private init() {}

    // Keyed by the walked root URL; refreshed on the page's 1s cadence so live
    // agent writes appear.
    private(set) var fileTrees: [URL: FileTreeNode] = [:]

    // Re-walk a directory subtree off the main actor and publish only if it
    // actually changed (same shape + mtimes ⇒ no @Observable churn, so the
    // explorer's selection/expansion don't thrash on every 1s tick).
    /// Re-walk a directory subtree and publish if the tree changed.
    ///
    /// - Parameter root: The root URL to walk.
    func refreshFileTree(at root: URL) async {
        let tree =
            await Task.detached(priority: .userInitiated) {
                FileTreeNode.walk(root)
            }
            .value
        if fileTrees[root] != tree { fileTrees[root] = tree }
    }

    // MARK: - Raw file body (lazy reads)

    /// Read a file's contents as a UTF-8 string.
    ///
    /// - Parameter url: The file URL.
    /// - Returns: The file contents, or empty string if read fails.
    nonisolated static func readRawFile(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
