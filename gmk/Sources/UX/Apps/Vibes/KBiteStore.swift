import Foundation
import Observation

enum KBiteRoot: String, CaseIterable, Hashable, Identifiable {
    case open
    case digested

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .digested: "Digested"
        }
    }

    var envKey: GMVibesEnvKey {
        switch self {
        case .open: .kbiteOpen
        case .digested: .kbiteDigested
        }
    }
}

struct KBiteEntry: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: URL { url }
}

@Observable
@MainActor
final class KBiteStore {
    private(set) var rescanToken: Int = 0

    /// Triggers a rescan of the kbite directories.
    ///
    /// Increments the rescan token to notify observers of changes.
    func refresh() {
        rescanToken &+= 1
    }

    /// Returns the filesystem URL for a kbite root directory.
    ///
    /// - Parameters:
    ///   - root: The kbite root (open or digested).
    ///   - gmcc: The Vibes environment for path resolution.
    /// - Returns: The directory URL, or nil if not configured.
    func rootURL(for root: KBiteRoot, gmcc: GMVibesEnvironment) -> URL? {
        guard let path = gmcc[root.envKey], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Returns the kbites in a root directory.
    ///
    /// Directories are sorted by name case-insensitively.
    ///
    /// - Parameters:
    ///   - root: The kbite root (open or digested).
    ///   - gmcc: The Vibes environment for path resolution.
    /// - Returns: An array of kbite entries; empty if not configured or inaccessible.
    func kbites(in root: KBiteRoot, gmcc: GMVibesEnvironment) -> [KBiteEntry] {
        _ = rescanToken
        guard let dir = rootURL(for: root, gmcc: gmcc) else { return [] }
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return
            entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { KBiteEntry(name: $0.lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
