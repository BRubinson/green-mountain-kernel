import AppKit
import Foundation
import GmDaemonSdk
import GmITerm2Client

// External-app launchers + the bot tier catalog, moved verbatim out of
// SessionPromptEditorView.swift (they are not editor code).

// MARK: - Bot fidelity tiers

// The three GMCC bot fidelity tiers. Each maps to a resume command that the
// editor copies to the clipboard for the user to paste into Claude Code — and,
// since the run bar landed, the same command the launched pane execs directly.
// The clipboard route still exists and is still the fallback when a launch
// fails; it is no longer the only route.
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
/// `daemon_config`, NOT a `run_option_profile`: GMVibes has no RETURN channel
/// into the Claude Code session its buttons launch; the launch is
/// fire-and-forget. So this is a preference about the clipboard string and
/// nothing more.
///
/// THAT LAST CLAUSE IS STILL LITERALLY CORRECT AFTER THE RUN BAR LANDED, and it
/// is worth leaving standing as evidence that the contract held: `PromptRunBar`
/// seeds its tier from this preference as `@State` and NEVER writes it back.
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
    // window. The profile write is AWAITED before the launch, which also closes
    // the cold-start race where iTerm2 read its dynamic profiles before we
    // finished writing ours.
    @MainActor
    static func open(dir: URL, instanceUUID: UUID, instanceName: String) {
        Task {
            let profileName = await ensureProfile(instanceUUID: instanceUUID,
                                                  instanceName: instanceName,
                                                  workingDir: dir.path)
            await launch(dir: dir, profileName: profileName)
        }
    }

    /// Write (or rewrite) this instance's Dynamic Profile and return its NAME on
    /// success, nil on failure.
    ///
    /// Exposed so `PromptRunBar` REUSES it rather than growing a second copy of
    /// the profile-writing rules. The actual file work runs off the main actor.
    static func ensureProfile(instanceUUID: UUID,
                              instanceName: String,
                              workingDir: String) async -> String? {
        let guid = "gmvibes-\(instanceUUID.uuidString)"
        let name = "GMVibes — \(instanceName)"
        return await Task.detached(priority: .userInitiated) {
            writeProfile(guid: guid, name: name, workingDir: workingDir) ? name : nil
        }.value
    }

    // A TWO-RUNG LADDER: the iTerm2 API, then NSWorkspace open-at-dir / a Finder
    // reveal. The AppleScript window-open rung that used to sit in the middle is
    // GONE — AppleScript survives in this feature only for the API cookie
    // request, which happens inside the transport package.
    //
    // THIS LADDER IS `ITerm.open`'s ALONE, BECAUSE IT CARRIES NO COMMAND. "Show
    // me this folder" is genuinely answered by a Finder window, so degrading is
    // honest here.
    //
    // PLAY HAS NO SUCH FALLBACK AND MUST NEVER ACQUIRE ONE by someone "making
    // the two consistent". Play carries a command: a window WITHOUT it LOOKS
    // LIKE SUCCESS while the prompt never runs, which is worse than no window.
    @MainActor
    private static func launch(dir: URL, profileName: String?) async {
        do {
            _ = try await ITerm2Launcher.openWindow(
                profileName: profileName,
                profileProperties: workingDirectoryProperties(dir.path))
            return
        } catch {
            // Fall through to the degraded rung. Nothing to report: the user
            // asked to see a folder and is about to see it.
        }
        revealFallback(dir)
    }

    /// The two profile keys that put a new session in a directory. Shared with
    /// `PromptRunBar`, which appends the command keys on top of them, so the two
    /// launch paths cannot disagree about what "open here" means.
    ///
    /// Values are iTerm2's own: `Custom Directory` is the enable switch
    /// (`"Yes"`), `Working Directory` is the path.
    static func workingDirectoryProperties(_ path: String) -> [PaneProfileProperty] {
        [.string("Custom Directory", "Yes"),
         .string("Working Directory", path)]
    }

    /// Kept SYNCHRONOUS on purpose: `NSWorkspace.open(_:withApplicationAt:configuration:)`
    /// has an async overload that wins in an `async` context and then demands
    /// `try await`. This is the same fire-and-forget call the launcher has
    /// always made.
    @MainActor
    private static func revealFallback(_ dir: URL) {
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
    //
    // EXACTLY FOUR KEYS — Guid, Name, Custom Directory, Working Directory. NO Tab
    // Color, NO Command, NO Initial Text. Two independent reasons, both of which
    // outlive whatever convenience a fifth key would buy:
    //
    //   1. The profile is per-INSTANCE (guid = "gmvibes-<instanceUUID>"), so any
    //      PER-LAUNCH value put here is last-writer-wins across concurrent
    //      launches. The pane's colour and command ride in the launch script
    //      instead, where they belong to one launch.
    //   2. This function writes to ~/Library/Application Support/iTerm2/
    //      DynamicProfiles/ through FileManager directly — OUTSIDE $GM_FS_ROOT,
    //      OUTSIDE the repo, and NOT through Paths.assertContained. Every key
    //      added makes an uncontained write carry more state.
    //
    // (Initial Text is separately disqualified: iTerm2 evaluates it as a swifty
    // string, so `\(...)` in any interpolated content is an injection hazard.)
    //
    // THE ATOMIC-WRITE DISCIPLINE BELOW IS LOAD-BEARING: one malformed file
    // disables ALL dynamic profiles, not just this one.
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

    // `runAppleScript(profileName:)` WAS HERE and is deliberately gone. It drove
    // `tell application "iTerm2" / create window with profile` through
    // NSAppleScript, and it was the middle rung of the old three-rung ladder.
    //
    // It was removed as a decision, not as cleanup: the API route above does the
    // same job and can also carry a command, which AppleScript could only do by
    // string-splicing into a language with no backslash escaping. Do not restore
    // it as a "harmless extra fallback" — a rung that opens a window without the
    // command is precisely the failure mode this design refuses.
}
