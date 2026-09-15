import SwiftUI
import AppKit
import GmDaemonSdk
import GmITerm2Client

// The prompt editor's RUN bar: a bot-tier picker, the launch-colour swatch, a
// Play button, and ONE status line. Play opens an iTerm2 window in the
// instance's repo running that tier's bot command, with `GM_FS_ROOT` exported
// into it and the tab coloured to match the prompt's badge ring.
//
// THE LAUNCH IS OUTBOUND ONLY. There is no return channel, no feedback, no
// generated MCP config and no hooks — GMVibes starts a session and learns
// nothing further about it. The four amended "no RETURN channel" doc comments
// elsewhere in this module say so for the same reason, and none of them should
// be read as promising one later.
//
// ─────────────────────────────────────────────────────────────────────────────
// MANUAL ACCEPTANCE PROCEDURE — this is the verification this slice gets.
//
// Nothing here is reachable by `Gm_Kernel_test`: that package depends only on
// gmDaemonSdk and gmDaemon, and gmVibesCore ships no test target. NO TEST
// PACKAGE MAY BE ADDED — the repo deleted seven on purpose and recorded the
// cost. What stands in for a suite is structure (the pure `nonisolated`
// builders in PaneLaunchScript.swift, and the exhaustive `switch` over
// `ITerm2Error` below, where a new error case with no copy FAILS THE BUILD)
// plus these six steps, run by hand:
//
//   1. Press Play. A window opens in the right repo, on the right branch.
//   2. `echo $GM_FS_ROOT` IN THE PANE matches the root this bar displayed.
//      THIS IS THE HALF WHERE FAILURE LOOKS IDENTICAL TO SUCCESS FROM OUTSIDE —
//      a debug app (baked `~/test_gmfs`) silently launching a production pane
//      opens the same window, in the same repo, and records into the wrong
//      database. CHECK IT EXPLICITLY; never infer it from the window appearing.
//   3. `gm_hook paths --json` in the pane answers from that same root.
//   4. The tab is the colour of the prompt's badge ring in the navigator.
//   5. The prompt resolves to the right seq (the bot reports the prompt name).
//   6. The two by-hand facts about the argv form: that a positional prompt
//      beginning with `/` dispatches as a slash command, and that SessionStart
//      hooks COMPLETE before that first prompt is processed (`/gm_bot_rpi`
//      hard-exits without `$GM_BOOTED`). If either is false, the script's last
//      line becomes bare `exec claude` and the tier command goes to the
//      clipboard.
//
// FIRST RUN ON A MACHINE needs two things a human must do, both surfaced below
// as typed states with affordances rather than as a silent no-op: iTerm2 >
// Settings > General > Magic > Enable Python API, and the one-time "GMVibes
// wants to control iTerm2" Automation prompt (easy to miss — `LSUIElement =
// YES` means no Dock icon).
// ─────────────────────────────────────────────────────────────────────────────

struct PromptRunBar: View {
    let stub: PromptStub
    let windowID: SessionWindowID
    /// The instance's checkout on disk — REUSED from `PromptEditorPane`'s
    /// already-resolved `paths.repoFolder`, never re-derived.
    let repoFolder: URL?
    /// The prompt's session code: the SLUGGED branch, compared against
    /// `CheckoutWatcher`'s slugged code. Never unslugged for display.
    let sessionCode: String?
    /// The authoritative root for this process, as `GMVibesEnvironment`
    /// publishes it. The pane owns that read; this bar takes the answer.
    let gmFsRoot: String?
    /// Only for the per-instance Dynamic Profile's display name.
    let instanceName: String

    /// TIER SELECTION IS `@State`, SEEDED FROM THE PREFERENCE, AND NEVER
    /// WRITES IT BACK. `ExternalLaunchers.swift` calls that "the whole
    /// behavioural contract of Feature 1": the default tier is set explicitly
    /// through the cluster's picker and never learned from the last tier
    /// clicked. Pressing Play here must not silently change anyone's default.
    /// (`BotLauncherPreference.tier` degrades an unrecognised rawValue to
    /// `.gmBotRPI` rather than trapping, so the seed is safe.)
    @State private var tier: BotTier = BotLauncherPreference.tier
    @State private var phase: RunPhase = .idle

    @Environment(CheckoutWatcher.self) private var checkout
    @Environment(LaunchColorRegistry.self) private var launchColors
    /// Not a new service — the generation is what `ensureWatching` keys its
    /// resync on, exactly as `InstanceScreen` does it.
    @Environment(DaemonConnectionModel.self) private var daemon

    // MARK: - State

    /// Why Play cannot run right now. Computed from live state rather than
    /// stored, so a branch switch re-enables the button with no event wiring.
    enum Block: Equatable {
        /// Absent CheckoutWatcher entry = NEVER RESOLVED. That is NOT a
        /// mismatch and must not read as one.
        case branchUnresolved
        case detachedHead
        case headUnavailable
        case wrongBranch(current: String, needs: String)
        case noRoot
        case gmHookMissing(root: String)
        case noRepo
    }

    enum RunPhase {
        case idle
        case blocked(Block)
        case launching(LaunchStage)
        case launched(PaneSession)
        case failed(ITerm2Error)
    }

    private enum Affordance {
        case openITerm
        case openAutomationSettings
        case copyCommand
    }

    private var instanceUuid: String { windowID.instanceUUID.wireString }

    /// `BotTier.command(for:)` emits `"<command> <seq>"`. ONE argument is the
    /// working form for an EXISTING prompt; the frontmatter's second argument is
    /// for the create case, which this bar never takes.
    private var tierCommand: String { tier.command(for: Int(stub.seq)) }

    /// FOUR outcomes on the branch gate, not two — plus the three preflight
    /// blocks. `.detached` and `.unavailable` are real HEAD states and NEITHER
    /// is "wrong branch".
    private var block: Block? {
        guard let state = checkout.stateByInstance[instanceUuid] else {
            return .branchUnresolved
        }
        switch state.headState {
        case .detached: return .detachedHead
        case .unavailable: return .headUnavailable
        case .branch:
            guard let needs = sessionCode else { return .branchUnresolved }
            if state.currentSessionCode != needs {
                return .wrongBranch(current: state.currentBranch ?? "—", needs: needs)
            }
        }
        guard let root = gmFsRoot, !root.isEmpty else { return .noRoot }
        // BUILT FROM THE ENVIRONMENT STRING, not `Paths.binHook`, so the check
        // tests the root THE PANE WILL ACTUALLY USE.
        //
        // THIS IS THE TRAP: `gm_hook.sh` exits 0 SILENTLY when its binary is
        // missing, so a pane on an unpopulated root records NOTHING and reports
        // no error. Debug bakes `~/test_gmfs` and Release `~/gmfs`, which makes
        // this a daily hazard rather than a theoretical one.
        let hook = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gm_hook")
        guard FileManager.default.isExecutableFile(atPath: hook.path) else {
            return .gmHookMissing(root: root)
        }
        guard repoFolder != nil else { return .noRepo }
        return nil
    }

    private var displayPhase: RunPhase {
        if let block { return .blocked(block) }
        return phase
    }

    private var isLaunching: Bool {
        if case .launching = phase { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("Tier", selection: $tier) {
                    ForEach(BotTier.allCases) { option in
                        Label(option.command, systemImage: option.symbol).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(isLaunching)

                swatch

                Button {
                    Task { await play() }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(block != nil || isLaunching)
                .help("Open an iTerm2 window in this repo running \(tierCommand)")

                Spacer(minLength: 0)
            }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same idiom as InstanceScreen: the watcher needs this instance in its
        // set before `stateByInstance` can answer anything but "unresolved".
        .task(id: daemon.generation) {
            checkout.ensureWatching(instanceUuid: instanceUuid, generation: daemon.generation)
        }
    }

    @ViewBuilder
    private var swatch: some View {
        if let assigned = launchColors.color(for: stub.uuid) {
            Circle()
                .fill(assigned.color)
                .frame(width: 10, height: 10)
                .help("""
                This prompt's pane colour. iTerm2 exposes no window-border API: \
                tab colour tints window chrome under the Minimal or Compact \
                window styles and colours the tab alone under Regular, and \
                nothing here can tell which style your profile uses.
                """)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch displayPhase {
        case .idle:
            EmptyView()
        case .blocked(let block):
            message(blockCopy(block), symbol: "exclamationmark.triangle.fill", tone: .orange)
        case .launching(let stage):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(stageCopy(stage)).font(.caption).foregroundStyle(.secondary)
            }
        case .launched(let session):
            message("Running in iTerm2 (session \(session.sessionId))"
                    + (session.usedDefaultProfile
                       ? " — the instance profile was rejected, so this pane uses the default profile and the wrong colours."
                       : ""),
                    symbol: "checkmark.circle.fill", tone: .green)
        case .failed(let error):
            let copy = failureCopy(error)
            VStack(alignment: .leading, spacing: 4) {
                message(copy.text, symbol: "xmark.octagon.fill", tone: .red,
                        monospaced: copy.monospaced)
                if let affordance = copy.affordance {
                    affordanceButton(affordance)
                }
            }
        }
    }

    private func message(_ text: String, symbol: String, tone: Color,
                         monospaced: Bool = false) -> some View {
        Label {
            Text(text)
                .font(monospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func affordanceButton(_ affordance: Affordance) -> some View {
        switch affordance {
        case .openITerm:
            Button("Open iTerm2") {
                if let app = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
                    NSWorkspace.shared.open(app)
                }
            }
            .controlSize(.small)
        case .openAutomationSettings:
            Button("Open Automation Settings") {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        case .copyCommand:
            // The run stays reachable by hand. No new wire verb, no
            // SendTextRequest — the clipboard is the fallback this slice owns.
            Button("Copy command") { Clipboard.copy(tierCommand) }
                .controlSize(.small)
        }
    }

    // MARK: - Copy

    private func blockCopy(_ block: Block) -> String {
        switch block {
        case .branchUnresolved:
            return "Checking this repo's branch…"
        case .detachedHead:
            return "This repo is on a detached HEAD; no session corresponds to it."
        case .headUnavailable:
            return "Can't read this repo's HEAD — the path may be gone."
        case .wrongBranch(let current, let needs):
            // BOTH FORMS, verbatim: `GitHead.sessionCode(forBranch:)` is
            // FORWARD-ONLY (`/` → `__`) and must never be inverted for display.
            // Play NEVER runs `git checkout` — that arm was explicitly declined.
            return "On `\(current)`, this prompt needs `\(needs)`."
        case .noRoot:
            return "No GM_FS_ROOT resolved, so a pane would have no environment to record into."
        case .gmHookMissing(let root):
            return "No executable gm_hook at \(root)/bin/gm_hook — a pane on this root would record nothing, silently."
        case .noRepo:
            return "This instance has no resolved checkout on disk."
        }
    }

    private func stageCopy(_ stage: LaunchStage) -> String {
        switch stage {
        case .preparing: return "Preparing…"
        case .startingApp: return "Starting iTerm2…"
        case .connecting: return "Connecting…"
        case .openingWindow: return "Opening window…"
        }
    }

    /// THE COMPILE-TIME GUARD THIS SLICE ACTUALLY GETS. An EXHAUSTIVE switch
    /// over `ITerm2Error` with no `default`: a new error case added to the
    /// transport package and left without copy here FAILS THE BUILD, which is
    /// precisely the silent no-op this design must not have.
    private func failureCopy(_ error: ITerm2Error)
        -> (text: String, affordance: Affordance?, monospaced: Bool) {
        switch error {
        case .appNotInstalled:
            return ("iTerm2 isn't installed.", nil, false)

        // THESE TWO SHARE ONE TREATMENT, deliberately. "iTerm2 came up but
        // never bound its socket" is overwhelmingly "the Python API is off",
        // and that is the thing the user must act on. A separate, technically
        // honest "timed out" would be practically useless.
        case .apiDisabled, .apiServerUnavailable:
            return ("iTerm2's Python API is off. Turn it on in iTerm2 > Settings > "
                    + "General > Magic > Enable Python API, then press Play again.",
                    .openITerm, false)

        case .automationDenied:
            return ("macOS denied GMVibes permission to control iTerm2.",
                    .openAutomationSettings, false)

        case .handshakeFailed(let status):
            return ("iTerm2 refused the connection: \(status)", .copyCommand, true)
        case .launchRejected(let status):
            return ("iTerm2 rejected the launch: \(status)", .copyCommand, true)
        case .serverError(let detail):
            return ("iTerm2 reported an error: \(detail)", .copyCommand, true)
        case .transportFailed(let reason, let code):
            let suffix = code.map { " (errno \($0))" } ?? ""
            return ("Transport failed: \(reason)\(suffix)", .copyCommand, true)
        // The ONE case whose copy must not say "press Play again". The request
        // reached iTerm2 and only the answer was lost, so a window MAY ALREADY
        // BE OPEN and running the command — and a second press would open a
        // second one on the same prompt. Tell the user to look before retrying.
        case .responseLost(let reason):
            return ("iTerm2 stopped answering after the launch was sent, so a window "
                    + "may already have opened — check iTerm2 before pressing Play "
                    + "again. (\(reason))", .copyCommand, true)

        case .unsafeCommandPath(let path):
            return ("Refused to launch: unusable path \(path)", .copyCommand, true)
        case .cancelled:
            return ("Launch cancelled.", nil, false)
        }
    }

    // MARK: - Play

    /// Straight `async` on the main actor: no `Task.detached`, no
    /// `MainActor.run`. The transport does its blocking socket work on its own
    /// serial executor, which is the package's job and not this view's.
    @MainActor
    private func play() async {
        guard block == nil, let root = gmFsRoot, let repo = repoFolder else { return }
        phase = .launching(.preparing)
        // Assign the colour BEFORE building the script — the script carries the
        // hex, and the badge ring reads the same entry.
        let colour = launchColors.assign(promptUuid: stub.uuid)
        // Hoisted so the catch can reap it. A launch that throws never reaches
        // the script's own `rm -f "$0"`, and the API-off path — the one the
        // architecture calls the normal first run — throws on EVERY press.
        // Without this, each press leaves a script carrying that launch's
        // GM_FS_ROOT and tier command, and nothing in the tree ever reaps
        // `tmp/gm_pane/`. That is the accumulation the self-delete exists to
        // prevent, arriving through the failure path instead.
        var scriptURL: URL?
        do {
            let profileName = await ITerm.ensureProfile(
                instanceUUID: windowID.instanceUUID,
                instanceName: instanceName,
                workingDir: repo.path)
            let script = paneLaunchScript(root: root,
                                          repoPath: repo.path,
                                          tabColorHex: colour.hex,
                                          tierCommand: tierCommand)
            scriptURL = try PaneScriptWriter.write(script: script, root: root)
            let command = try paneCommandLine(shell: loginShellPath(),
                                              scriptPath: scriptURL!.path)
            // The instance profile's directory keys, plus the command keys on
            // top. `Custom Command` is the enable switch; `Command` is the
            // ARGV-SPLIT line `paneCommandLine` built.
            let properties = ITerm.workingDirectoryProperties(repo.path) + [
                .string("Custom Command", "Yes"),
                .string("Command", command),
            ]
            let session = try await ITerm2Launcher.launchPane(
                PaneLaunchRequest(profileName: profileName,
                                  profileProperties: properties),
                progress: { stage in
                    // SYNCHRONOUS, and it must stay that way. `launchPane` is
                    // @MainActor and so is this function, so the closure is
                    // already running on the main actor — but a `Task { }` here
                    // would ENQUEUE rather than run, and the last stage
                    // (.openingWindow) is emitted with NO suspension point
                    // after it. The queued job would therefore land AFTER
                    // `.launched` and overwrite it, leaving every successful
                    // launch showing a spinner forever with Play disabled, and
                    // making the `.launched` arm — and with it the
                    // `usedDefaultProfile` degraded-rung notice — dead code.
                    MainActor.assumeIsolated { phase = .launching(stage) }
                })
            phase = .launched(session)
        } catch {
            if let scriptURL { try? FileManager.default.removeItem(at: scriptURL) }
            phase = .failed(error)
        }
    }
}
