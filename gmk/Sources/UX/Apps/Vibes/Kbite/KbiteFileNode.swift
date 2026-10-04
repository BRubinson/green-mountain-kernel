import Foundation

struct KbiteFileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [KbiteFileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// Loads a file or directory tree into a node hierarchy.
    ///
    /// - Parameter url: The file or directory URL to load.
    /// - Returns: A KbiteFileNode representing the file system tree.
    static func load(from url: URL) -> KbiteFileNode {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return KbiteFileNode(url: url, isDirectory: false, children: nil)
        }

        if !isDir.boolValue {
            return KbiteFileNode(url: url, isDirectory: false, children: nil)
        }

        let kids =
            (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

        let sorted =
            kids
            .map { child -> KbiteFileNode in
                let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return KbiteFileNode(url: child, isDirectory: childIsDir, children: childIsDir ? [] : nil)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { node -> KbiteFileNode in
                node.isDirectory ? KbiteFileNode.load(from: node.url) : node
            }

        return KbiteFileNode(url: url, isDirectory: true, children: sorted)
    }
}
