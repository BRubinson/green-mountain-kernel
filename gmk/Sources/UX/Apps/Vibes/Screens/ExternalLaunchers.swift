import AppKit
import Foundation

// External-app launchers + the bot tier catalog, moved verbatim out of
// SessionPromptEditorView.swift (they are not editor code).

// MARK: - Bot fidelity tiers

// The three GMCC bot fidelity tiers. Each maps to a resume command that the
// editor copies to the clipboard for the user to paste into Claude Code.
enum BotTier: String, CaseIterable, Identifiable {
    case gmBot = "/gm_bot"
    case gmBotRPI = "/gm_bot_rpi"
    case gmBotTeam = "/gm_bot_team"

    var id: String { rawValue }

    /// The bare command name, no slash: "gm_bot_rpi". `rawValue` keeps the
    /// leading slash because it is the UserDefaults key (BotLauncherPreference),
    /// and stripping it there would reset every saved tier choice.
    private var commandName: String { String(rawValue.dropFirst()) }

    /// What Claude Code actually accepts.
    ///
    /// Plugin slash commands are namespaced `/<plugin>:<command>`. The `<plugin>`
    /// is whichever plugin the pane loads (marketplace `gmcc` in prod, working-tree
    /// via `--plugin-dir` in beta/test). Sourced from `loadedPluginNamespace` so
    /// command and plugin never disagree.
    var invocation: String { "/\(Self.loadedPluginNamespace):\(commandName)" }

    /// The name of the plugin a pane loads, read ONCE.
    ///
    /// When a dev plugin dir is baked (beta/test), that directory IS what
    /// `--plugin-dir` loads, so its own `plugin.json` name is the authoritative
    /// namespace — reading it here rather than hardcoding "gmbeta" keeps this
    /// correct even if the alias is renamed. With no dev dir baked (prod) the
    /// pane loads the marketplace plugin, whose name is `gmcc`.
    static let loadedPluginNamespace: String = {
        guard case .present(let dir) = DevPluginDir.current else { return "gmcc" }
        let manifest = URL(fileURLWithPath: dir, isDirectory: true)
            .appendingPathComponent(".claude-plugin", isDirectory: true)
            .appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifest),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = object["name"] as? String, !name.isEmpty
        else { return "gmcc" }
        return name
    }()

    var command: String { invocation }

    // 1 / 2 / 3-person icons — increasing crew size by fidelity tier.
    var symbol: String {
        switch self {
        case .gmBot: return "person.fill"
        case .gmBotRPI: return "person.2.fill"
        case .gmBotTeam: return "person.3.fill"
        }
    }

    /// Returns the invocation command with a numeric workflow instance.
    /// - Parameter id: The workflow instance identifier.
    /// - Returns: The command string with the instance ID appended.
    func command(for id: Int) -> String { "\(command) \(id)" }

    /// The bridge that makes the launcher and the phase strip speak ONE
    /// vocabulary: the tier a user copies IS the `bot_workflow.variant` the
    /// daemon will record, so pills and cluster never disagree.
    ///
    /// `BotVariant.task` has no tier deliberately — `/gm_task`'s write-nothing
    /// contract means no workflow row exists, and it is not a fidelity tier.
    /// (It is also absent from `BotVariant` itself.)
    var variant: BotVariant {
        switch self {
        case .gmBot: return .bot
        case .gmBotRPI: return .rpi
        case .gmBotTeam: return .team
        }
    }

    /// How many phases this tier's run walks, straight off the daemon kit's
    /// compiled-in registry — 10 / 11 / 12 today.
    ///
    /// Read by the launcher's help text, so the number can never drift from the
    /// machine the bot runs.
    var phaseCount: Int { WorkflowSpec.phases(for: variant).count }
}

// MARK: - Launcher preference

/// Which slash command the resume-command launcher emits without an explicit choice, and
/// which tier the cluster highlights.
///
/// App-side `UserDefaults` rather than dope, `daemon_config` or a `run_option_profile`: the
/// app has no runtime channel into the Claude Code session its buttons launch, so this is a
/// preference about the clipboard string and nothing more. It is set EXPLICITLY through
/// `BotLauncherCluster`'s picker and never learned from the last tier clicked, because a
/// transient selection is not a configured one.
enum BotLauncherPreference {
    /// The `@AppStorage` key.
    ///
    /// Views bind it directly — `@AppStorage(BotLauncherPreference.key) var tier = BotLauncherPreference.fallback`
    /// — so the picker, the highlight and this accessor all read one cell.
    static let key = "gmvibes.bot.defaultTier"

    /// Shipped default: the middle tier, the one most runs use.
    static let fallback: BotTier = .gmBotRPI

    /// Non-SwiftUI read/write of the same cell, for call sites outside a view
    /// body.
    ///
    /// An unset or unrecognised rawValue (a preference written by a build that
    /// knew a tier this one does not) degrades to `fallback` rather than
    /// trapping.
    static var tier: BotTier {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                let tier = BotTier(rawValue: raw)
            else { return fallback }
            return tier
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Clipboard helper

enum Clipboard {
    /// Copies a string to the general pasteboard.
    /// - Parameter string: The text to copy.
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

// MARK: - VS Code launcher

enum VSCode {
    /// Opens a folder as a VS Code workspace.
    ///
    /// Prefers launching the app bundle directly and falls back to revealing
    /// the folder in Finder if VS Code is not installed.
    /// - Parameter url: The directory URL to open.
    static func open(_ url: URL) {
        let ws = NSWorkspace.shared
        if let app = ws.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            let config = NSWorkspace.OpenConfiguration()
            ws.open([url], withApplicationAt: app, configuration: config)
        } else {
            ws.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - iTerm2 launcher

// Opens an iTerm2 window rooted at `dir` via a PER-INSTANCE Dynamic Profile, so
// windows/tabs spawned from it default to the same repo dir. The profile JSON is
// rewritten in place (deterministic Guid) on every open; a single malformed file
// disables ALL dynamic profiles, so we serialize/validate, then write atomically.
// Falls back to NSWorkspace open-at-dir, then a Finder reveal — mirroring VSCode.
enum ITerm {
    /// Opens an iTerm2 window rooted at a directory with dynamic profile configuration.
    ///
    /// Writes the dynamic profile off the main thread and opens the window on the
    /// main thread to avoid UI hitching.
    /// - Parameters:
    ///   - dir: The directory to set as the working directory.
    ///   - instanceUUID: The unique identifier for this instance.
    ///   - instanceName: The human-readable name for the dynamic profile.
    @MainActor
    static func open(dir: URL, instanceUUID: UUID, instanceName: String) {
        Task {
            let profileName = await ensureProfile(
                instanceUUID: instanceUUID,
                instanceName: instanceName,
                workingDir: dir.path
            )
            await launch(dir: dir, profileName: profileName)
        }
    }

    /// Ensures a dynamic profile exists for the given instance.
    /// - Parameters:
    ///   - instanceUUID: The unique identifier for this instance.
    ///   - instanceName: The human-readable name for the dynamic profile.
    ///   - workingDir: The working directory path for the profile.
    /// - Returns: The profile name if the profile was created successfully, nil otherwise.
    static func ensureProfile(
        instanceUUID: UUID,
        instanceName: String,
        workingDir: String
    ) async -> String? {
        let guid = "gmvibes-\(instanceUUID.uuidString)"
        let name = "GMVibes — \(instanceName)"
        return
            await Task.detached(priority: .userInitiated) {
                writeProfile(guid: guid, name: name, workingDir: workingDir) ? name : nil
            }
            .value
    }

    /// Launches an iTerm2 window with the specified profile.
    ///
    /// Falls back to NSWorkspace and Finder reveal if launch fails.
    /// - Parameters:
    ///   - dir: The directory to reveal or open.
    ///   - profileName: The dynamic profile name, if available.
    @MainActor
    private static func launch(dir: URL, profileName: String?) async {
        do {
            _ = try await ITerm2Launcher.openWindow(
                profileName: profileName,
                profileProperties: workingDirectoryProperties(dir.path)
            )
            return
        } catch {
        }
        revealFallback(dir)
    }

    /// Returns the iTerm2 profile properties for setting a working directory.
    /// - Parameter path: The directory path to configure.
    /// - Returns: An array of profile properties specifying the working directory.
    static func workingDirectoryProperties(_ path: String) -> [PaneProfileProperty] {
        [
            .string("Custom Directory", "Yes"),
            .string("Working Directory", path),
        ]
    }

    /// Opens a directory with iTerm2 or reveals it in Finder as a fallback.
    /// - Parameter dir: The directory URL to open or reveal.
    @MainActor
    private static func revealFallback(_ dir: URL) {
        let ws = NSWorkspace.shared
        if let term = ws.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
            ws.open([dir], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.activateFileViewerSelecting([dir])
        }
    }

    /// Returns the iTerm2 dynamic profiles directory, creating it if absent.
    ///
    /// The path is `~/Library/Application Support/iTerm2/DynamicProfiles`.
    /// - Returns: The directory URL, or nil if the app support directory cannot be resolved.
    private nonisolated static func dynamicProfilesDir() -> URL? {
        guard
            let appSup = FileManager.default
                .urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )
                .first
        else { return nil }
        let dir = appSup.appendingPathComponent("iTerm2/DynamicProfiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a dynamic profile JSON file for an iTerm2 instance.
    ///
    /// Creates an idempotent per-instance profile file with atomic write
    /// semantics. JSONSerialization validates the shape before writing.
    /// - Parameters:
    ///   - guid: The unique identifier for this profile.
    ///   - name: The human-readable profile name.
    ///   - workingDir: The working directory path to configure.
    /// - Returns: True if the profile was written successfully, false otherwise.
    private nonisolated static func writeProfile(guid: String, name: String, workingDir: String) -> Bool {
        guard let dir = dynamicProfilesDir() else { return false }
        let payload: [String: Any] = [
            "Profiles": [
                [
                    "Guid": guid,
                    "Name": name,
                    "Custom Directory": "Yes",
                    "Working Directory": workingDir,
                ]
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted]
            )
        else { return false }
        let url = dir.appendingPathComponent("\(guid).json")
        let tmp = dir.appendingPathComponent(".\(guid).json.tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

}
