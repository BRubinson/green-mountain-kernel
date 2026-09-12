import AppKit
import Foundation
import GMCCDaemonKit

// External-app launchers + the bot tier catalog, moved verbatim out of
// SessionPromptEditorView.swift (they are not editor code).

// MARK: - Bot fidelity tiers

// The three GMCC bot fidelity tiers. Each maps to a resume command that the
// editor copies to the clipboard for the user to paste into Claude Code.
enum BotTier: String, CaseIterable, Identifiable {
    case gmBot     = "/gm_bot"
    case gmBotRPI  = "/gm_bot_rpi"
    case gmBotTeam = "/gm_bot_team"

    var id: String { rawValue }
    var command: String { rawValue }

    // 1 / 2 / 3-person icons — increasing crew size by fidelity tier.
    var symbol: String {
        switch self {
        case .gmBot:     return "person.fill"
        case .gmBotRPI:  return "person.2.fill"
        case .gmBotTeam: return "person.3.fill"
        }
    }

    func command(for id: Int) -> String { "\(command) \(id)" }

    /// The bridge that makes the launcher and the phase strip speak ONE
    /// vocabulary: the tier a user copies IS the `bot_workflow.variant` the
    /// daemon will record, so `WorkflowStrip`'s pills and this cluster can
    /// never disagree about what `/gm_bot_rpi` means.
    ///
    /// `BotVariant.task` has no tier deliberately — `/gm_task`'s
    /// write-nothing contract means no workflow row exists, and it is not a
    /// fidelity tier. (It is also absent from `BotVariant` itself.)
    var variant: BotVariant {
        switch self {
        case .gmBot:     return .bot
        case .gmBotRPI:  return .rpi
        case .gmBotTeam: return .team
        }
    }

    /// How many phases this tier's run walks, straight off the daemon kit's
    /// compiled-in registry — 10 / 11 / 12 today. Read by the launcher's help
    /// text, so the number can never drift from the machine the bot runs.
    var phaseCount: Int { WorkflowSpec.phases(for: variant).count }
}

// MARK: - Launcher preference

/// Feature 1, in full: which slash command the resume-command launcher emits
/// when invoked without an explicit choice, and which tier the cluster
/// highlights. App-side `UserDefaults` — deliberately NOT dope, NOT
/// `daemon_config`, NOT a `run_option_profile`: GMVibes has no runtime
/// channel into the Claude Code session its buttons launch, so this is a
/// preference about the clipboard string and nothing more.
///
/// It is set **explicitly**, through `BotLauncherCluster`'s inline picker —
/// never learned from the last tier clicked. A user copying `/gm_bot` once to
/// try it must not silently change their default; a transient selection is
/// not a configured one. (This replaces the old per-window `@State
/// selectedTier`, which meant nothing across windows and was lost on close.)
enum BotLauncherPreference {
    /// The `@AppStorage` key. Views bind it directly —
    /// `@AppStorage(BotLauncherPreference.key) var tier = BotLauncherPreference.fallback`
    /// — so the picker, the highlight and this accessor all read one cell.
    static let key = "gmvibes.bot.defaultTier"

    /// Shipped default: the middle tier, the one most runs use.
    static let fallback: BotTier = .gmBotRPI

    /// Non-SwiftUI read/write of the same cell, for call sites outside a view
    /// body. An unset or unrecognised rawValue (a preference written by a
    /// build that knew a tier this one does not) degrades to `fallback`
    /// rather than trapping.
    static var tier: BotTier {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let tier = BotTier(rawValue: raw) else { return fallback }
            return tier
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Clipboard helper

enum Clipboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

// MARK: - VS Code launcher

enum VSCode {
    // Opens a folder as a VS Code workspace. Prefers launching the app bundle
    // directly (no dependency on the `code` CLI being on PATH); falls back to
    // revealing the folder in Finder if VS Code isn't installed.
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
    // Writes the per-instance Dynamic Profile OFF the main thread, then opens the
    // window ON the main thread. Both the file write and a cold-iTerm AppleScript
    // launch are slow enough to hitch the UI if run inline from the button action.
    static func open(dir: URL, instanceUUID: UUID, instanceName: String) {
        let guid = "gmvibes-\(instanceUUID.uuidString)"
        let name = "GMVibes — \(instanceName)"
        Task.detached(priority: .userInitiated) {
            let wrote = writeProfile(guid: guid, name: name, workingDir: dir.path)
            await MainActor.run { launch(dir: dir, profileName: name, profileWritten: wrote) }
        }
    }

    // Open a window for the per-instance profile, falling back to NSWorkspace
    // open-at-dir, then a Finder reveal — mirroring VSCode. NSAppleScript must run
    // on the main thread (TN2097), so this whole step is MainActor-isolated.
    @MainActor
    private static func launch(dir: URL, profileName: String, profileWritten: Bool) {
        if profileWritten, runAppleScript(profileName: profileName) { return }
        let ws = NSWorkspace.shared
        if let term = ws.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
            ws.open([dir], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.activateFileViewerSelecting([dir])
        }
    }

    // ~/Library/Application Support/iTerm2/DynamicProfiles, created if absent.
    // `nonisolated` so the profile write can run off the main actor.
    private nonisolated static func dynamicProfilesDir() -> URL? {
        guard let appSup = FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask).first else { return nil }
        let dir = appSup.appendingPathComponent("iTerm2/DynamicProfiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Idempotent per-instance profile file: gmvibes-<UUID>.json with one profile.
    // JSONSerialization both validates the shape and renders the bytes we write.
    // `nonisolated` so it can run off the main actor (pure FileManager/JSON work).
    private nonisolated static func writeProfile(guid: String, name: String, workingDir: String) -> Bool {
        guard let dir = dynamicProfilesDir() else { return false }
        let payload: [String: Any] = ["Profiles": [[
            "Guid": guid,
            "Name": name,
            "Custom Directory": "Yes",
            "Working Directory": workingDir,
        ]]]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted]) else { return false }
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

    // Open a window for the named profile (NSWorkspace can't select a profile).
    // The AppleScript API is deprecated but functional; NSAppleScript drives it.
    @MainActor
    private static func runAppleScript(profileName: String) -> Bool {
        // AppleScript string literals don't support backslash escaping — splice any
        // embedded double quote in via the `quote` constant instead.
        let escaped = profileName.replacingOccurrences(of: "\"", with: "\" & quote & \"")
        let source = """
        tell application "iTerm2"
            create window with profile "\(escaped)"
            activate
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        return err == nil
    }
}
