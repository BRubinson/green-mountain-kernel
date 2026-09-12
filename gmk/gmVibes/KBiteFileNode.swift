import Foundation

struct KBiteFileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [KBiteFileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    static func load(from url: URL) -> KBiteFileNode {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return KBiteFileNode(url: url, isDirectory: false, children: nil)
        }

        if !isDir.boolValue {
            return KBiteFileNode(url: url, isDirectory: false, children: nil)
        }

        let kids = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sorted = kids
            .map { child -> KBiteFileNode in
                let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return KBiteFileNode(url: child, isDirectory: childIsDir, children: childIsDir ? [] : nil)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { node -> KBiteFileNode in
                node.isDirectory ? KBiteFileNode.load(from: node.url) : node
            }

        return KBiteFileNode(url: url, isDirectory: true, children: sorted)
    }
}
