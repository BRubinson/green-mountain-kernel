import Foundation

/// The plugin tree a non-production pane loads: a property of the ENVIRONMENT,
/// resolved from the root this kernel holds, never of the checkout that
/// compiled the app.
///
/// An environment is a whole root with its own repo clone under `repos/`, and
/// the seed generates `plugins/gmbeta` INSIDE that clone from the kernel it
/// just staged — so the plugin a pane loads and the kernel it dials match by
/// construction. Production has no `repos/` and loads the marketplace plugin.
enum DevPluginDir {
    /// Three cases, not an optional: "no environment plugin" and "an environment
    /// that has lost its plugin" want opposite answers.
    enum Resolution: Equatable {
        /// No `repos/` under the root: production. Silent, no flag, no block.
        case none
        /// A root with clones but no plugin in any of them. BLOCKS: launching
        /// without `--plugin-dir` would quietly load the marketplace plugin.
        case missing(String)
        /// The plugin directory to hand `claude --plugin-dir`.
        case present(String)
    }

    static var current: Resolution {
        let repos = Paths.root.appendingPathComponent("repos", isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: repos.path, isDirectory: &isDir), isDir.boolValue else {
            return .none
        }
        let clones =
            ((try? fm.contentsOfDirectory(at: repos, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // The seeded alias first; a clone's committed tree second.
        for name in ["gmbeta", "gmcc"] {
            for clone in clones {
                let plugin = clone.appendingPathComponent("plugins/\(name)", isDirectory: true)
                let manifest = plugin.appendingPathComponent(".claude-plugin/plugin.json")
                if fm.fileExists(atPath: manifest.path) { return .present(plugin.path) }
            }
        }
        return .missing(repos.path)
    }
}
