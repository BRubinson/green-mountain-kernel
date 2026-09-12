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

    var envKey: GMCCEnvKey {
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

    func refresh() {
        rescanToken &+= 1
    }

    func rootURL(for root: KBiteRoot, gmcc: GMCCEnvironment) -> URL? {
        guard let path = gmcc[root.envKey], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func kbites(in root: KBiteRoot, gmcc: GMCCEnvironment) -> [KBiteEntry] {
        _ = rescanToken
        guard let dir = rootURL(for: root, gmcc: gmcc) else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { KBiteEntry(name: $0.lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
