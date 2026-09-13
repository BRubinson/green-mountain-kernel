import Foundation

/// The ONE repo-root resolver for every test that needs to reach a file on
/// disk rather than a symbol in memory.
///
/// WHAT THIS REPLACED, and why it is worth a package of its own: six test files
/// each re-derived the repo root by counting `deletingLastPathComponent()`
/// calls from `#filePath`. `DocsContractTests` walked exactly four levels;
/// `HookScriptTests` walked exactly four levels; four more did their own
/// variants. Every one of those counts encoded "this test file is N levels
/// below the root", which was true only while the package lived at
/// `plugins/gmcc/daemon`. The move to `gmk/` invalidated all six at once, and
/// 16 test functions in `DocsContractTests` alone depended on its walk landing
/// somewhere real.
///
/// Resolving by MARKER instead of by depth means the next move costs zero
/// edits: the walk stops when it finds the repo, wherever that turns out to be.
///
/// The failure mode is deliberately LOUD. `resolve()` traps with a message
/// naming the file it started from, rather than returning an optional that a
/// caller might quietly treat as "nothing to check" — a doc-contract test that
/// silently examines zero files is worse than one that fails.
enum RepoRoot {

    /// Files that mark the repository root. `.git` is the obvious one;
    /// `.claude-plugin/marketplace.json` is kept alongside it because a git
    /// worktree or an exported tree may not carry a `.git` directory, and a
    /// single-marker walk in that situation climbs to `/` and traps.
    private static let markers = [".git", ".claude-plugin/marketplace.json"]

    /// The repo root, resolved by climbing from `file` until a marker appears.
    static func resolve(from file: StaticString = #filePath) -> URL {
        let start = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        var url = start.standardizedFileURL
        let fm = FileManager.default
        while url.path != "/" {
            for marker in markers
            where fm.fileExists(atPath: url.appendingPathComponent(marker).path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        fatalError("""
            RepoRoot: no repo marker (\(markers.joined(separator: ", "))) at or \
            above \(start.path). A test cannot locate the repository, so every \
            filesystem assertion below this point would pass vacuously.
            """)
    }

    /// `plugins/gmcc/` — the plugin surface. It KEEPS its name: the runtime
    /// prefix retirement deliberately stopped short of the plugin directory,
    /// the `gmcc:` command/skill namespace and the pen server name.
    static func pluginRoot(from file: StaticString = #filePath) -> URL {
        resolve(from: file)
            .appendingPathComponent("plugins/gmcc", isDirectory: true)
    }

    /// `gmk/` — the one Xcode project and the six packages.
    static func gmkRoot(from file: StaticString = #filePath) -> URL {
        resolve(from: file).appendingPathComponent("gmk", isDirectory: true)
    }

    /// One package's directory, e.g. `package("gmDaemonSdk")`.
    static func package(
        _ name: String, from file: StaticString = #filePath
    ) -> URL {
        gmkRoot(from: file).appendingPathComponent(name, isDirectory: true)
    }

    /// Every package's `Sources/` tree. This is what replaced the single
    /// `pluginRoot/daemon/Sources` walk: the sources are in five places now, so
    /// a scan that names one of them silently stops covering four fifths of the
    /// code it was written to guard.
    static let sourcePackages = [
        "gmDaemonSdk", "gmDaemon", "gmUxComponentLibrary",
        "gmAgententicsSdk", "gmMcp", "gmKernel",
    ]

    /// Every `.swift` file under all six packages' `Sources/` trees.
    static func swiftSources(from file: StaticString = #filePath) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for name in sourcePackages {
            let root = package(name, from: file)
                .appendingPathComponent("Sources", isDirectory: true)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            while let url = walker.nextObject() as? URL {
                if url.pathExtension == "swift" { out.append(url) }
            }
        }
        return out
    }
}
