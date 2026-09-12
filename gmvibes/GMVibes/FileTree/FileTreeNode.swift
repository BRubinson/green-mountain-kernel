import Foundation

// A value-typed, polled snapshot of a directory subtree. Unlike KBiteFileNode
// (eager, synchronous, main-actor, never invalidated), this is walked off the main
// actor and re-walked on the app's existing 1s poll cadence via
// FileTreeStore.refreshFileTree — so files an architect agent writes into
// a prompt's memory/ folder appear live without a manual reload. Equality includes
// per-node modifiedAt so a rewrite (not just add/remove) re-publishes.
struct FileTreeNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let modifiedAt: Date
    var children: [FileTreeNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    // Recursively walk `url` to at most `maxDepth` levels. `nonisolated` + intended
    // to be called from Task.detached so the disk I/O never touches the main actor.
    nonisolated static func walk(_ url: URL, maxDepth: Int = 8) -> FileTreeNode {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let values = try? url.resourceValues(forKeys: Set(keys))
        let isDir = values?.isDirectory ?? false
        let mtime = values?.contentModificationDate ?? .distantPast

        guard isDir, maxDepth > 0 else {
            return FileTreeNode(url: url, isDirectory: isDir, modifiedAt: mtime, children: nil)
        }

        let contents = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let children = contents
            .map { child -> FileTreeNode in
                let v = try? child.resourceValues(forKeys: Set(keys))
                let childIsDir = v?.isDirectory ?? false
                if childIsDir {
                    return walk(child, maxDepth: maxDepth - 1)
                }
                return FileTreeNode(url: child, isDirectory: false,
                                    modifiedAt: v?.contentModificationDate ?? .distantPast,
                                    children: nil)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
            }

        return FileTreeNode(url: url, isDirectory: true, modifiedAt: mtime, children: children)
    }
}
