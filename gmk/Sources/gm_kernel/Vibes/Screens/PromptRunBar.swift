import SwiftUI
import AppKit

/// The disk reads behind the plugin preflight, taken ONCE per process, because
/// `PromptRunBar.block` is recomputed on every view update. The cache cannot see a
/// regeneration made while the app runs, so EVERY BLOCK MESSAGE ENDS IN "then relaunch".
///
/// The reference is the TREE's `gmk/VERSION`, never `CFBundleShortVersionString`, which is
/// stale on any Xcode Run. `claude --plugin-dir <dir>` REPLACES the installed plugin with no
/// fallback, so a stale tree resolves every `mcp__plugin_gmcc_cde__*` grant to nothing and the
/// only symptom is agents that write nothing. An unreadable VERSION file returns `.ok`.
private enum PluginPreflight {
    enum Result: Equatable {
        /// No baked directory — production, or a bundle built without one.
        /// Not a block: the pane loads the installed plugin, as it always has.
        case notConfigured
        /// A baked directory that is NOT on disk. This one blocks: emitting no
        /// `--plugin-dir` here would load the installed marketplace plugin
        /// silently, which is the failure this preflight exists to make loud.
        case directoryMissing(path: String)
        case manifestMissing(path: String)
        case versionMismatch(pluginVersion: String, treeVersion: String)
        case ok
    }

    /// The baked directory's resolution, taken once.
    static let resolution: DevPluginDir.Resolution = DevPluginDir.current

    /// The path to hand `claude --plugin-dir`, or `nil`. ONLY `.present`
    /// yields one: a directory that is not there must never reach the flag,
    /// blocked button or not.
    static var directory: String? {
        if case .present(let path) = resolution { return path }
        return nil
    }

    static let current: Result = evaluate()

    private static func evaluate() -> Result {
        let dir: String
        switch resolution {
        case .none: return .notConfigured
        case .missing(let path): return .directoryMissing(path: path)
        case .present(let path): dir = path
        }
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        let manifest =
            root
            .appendingPathComponent(".claude-plugin", isDirectory: true)
            .appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifest),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pluginVersion = object["version"] as? String
        else { return .manifestMissing(path: dir) }

        // `dir` is <repo>/plugins/gmcc, possibly spelled <repo>/gmk/../plugins/gmcc
        // by `$(SRCROOT)/../plugins/gmcc`. `standardizedFileURL` collapses the
        // `gmk/..` segment lexically, which is exactly right here — it must NOT
        // resolve symlinks, only the dot segments.
        let repoRoot = root
            .standardizedFileURL
            .deletingLastPathComponent()  // -> <repo>/plugins
            .deletingLastPathComponent()  // -> <repo>
        let versionFile =
            repoRoot
            .appendingPathComponent("gmk", isDirectory: true)
            .appendingPathComponent("VERSION")
        guard let raw = try? String(contentsOf: versionFile, encoding: .utf8) else { return .ok }
        let treeVersion = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !treeVersion.isEmpty else { return .ok }

        guard pluginVersion == treeVersion else {
            return .versionMismatch(pluginVersion: pluginVersion, treeVersion: treeVersion)
        }
        return .ok
    }
}

struct PromptRunBar: View {
    let stub: PromptStub
    let windowID: SessionWindowID
    let repoFolder: URL?
    let sessionCode: String?
    let gmFsRoot: String?
    let instanceName: String

    @State private var tier: BotTier = BotLauncherPreference.tier
    @State private var phase: RunPhase = .idle

    @Environment(CheckoutWatcher.self) private var checkout
    @Environment(LaunchColorRegistry.self) private var launchColors
    @Environment(DaemonConnectionModel.self) private var daemon

    enum Block: Equatable {
        case branchUnresolved
        case detachedHead
        case headUnavailable
        case wrongBranch(current: String, needs: String)
        case noRoot
        case gmHookMissing(root: String)
        case noRepo
        case pluginDirMissing(path: String)
        case pluginManifestMissing(path: String)
        case pluginVersionMismatch(pluginVersion: String, treeVersion: String)
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

    private var tierCommand: String { tier.command(for: Int(stub.seq)) }

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
        let hook = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gm_hook")
        guard FileManager.default.isExecutableFile(atPath: hook.path) else {
            return .gmHookMissing(root: root)
        }
        guard repoFolder != nil else { return .noRepo }
        switch PluginPreflight.current {
        case .notConfigured, .ok:
            break
        case .directoryMissing(let path):
            return .pluginDirMissing(path: path)
        case .manifestMissing(let path):
            return .pluginManifestMissing(path: path)
        case .versionMismatch(let pluginVersion, let treeVersion):
            return .pluginVersionMismatch(pluginVersion: pluginVersion, treeVersion: treeVersion)
        }
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

                // The INDEPENDENT open. Deliberately NOT gated on the branch
                // match, gm_hook, or the plugin preflight — a plain terminal
                // is precisely the tool for fixing the states those gates
                // block Play on. Only root+repo are required, because without
                // them there is nowhere to cd and no environment to export.
                Button {
                    Task { await openTerminal() }
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .disabled(gmFsRoot?.isEmpty != false || repoFolder == nil || isLaunching)
                .help("Open an iTerm2 window in this repo with GM_FS_ROOT set — no bot run.")

                Spacer(minLength: 0)
            }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .help(
                    """
                    This prompt's pane colour — the TAB hue tells prompts apart. \
                    The pane's BACKGROUND tint is a different signal: it tells you \
                    which ENVIRONMENT the pane is writing to, and production leaves \
                    it alone. iTerm2 exposes no window-border API: tab colour tints \
                    window chrome under the Minimal or Compact window styles and \
                    colours the tab alone under Regular, and nothing here can tell \
                    which style your profile uses — which is why the environment \
                    rides the background instead.
                    """
                )
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
            message(
                "Running in iTerm2 (session \(session.sessionId))"
                    + (session.usedDefaultProfile
                        ? " — the instance profile was rejected, so this pane uses the default profile and the wrong colours."
                        : ""),
                symbol: "checkmark.circle.fill",
                tone: .green
            )
        case .failed(let error):
            let copy = failureCopy(error)
            VStack(alignment: .leading, spacing: 4) {
                message(
                    copy.text,
                    symbol: "xmark.octagon.fill",
                    tone: .red,
                    monospaced: copy.monospaced
                )
                if let affordance = copy.affordance {
                    affordanceButton(affordance)
                }
            }
        }
    }

    private func message(
        _ text: String,
        symbol: String,
        tone: Color,
        monospaced: Bool = false
    ) -> some View {
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
                    .urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
                {
                    NSWorkspace.shared.open(app)
                }
            }
            .controlSize(.small)
        case .openAutomationSettings:
            Button("Open Automation Settings") {
                if let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        case .copyCommand:
            Button("Copy command") { Clipboard.copy(tierCommand) }
                .controlSize(.small)
        }
    }

    private func blockCopy(_ block: Block) -> String {
        switch block {
        case .branchUnresolved:
            return "Checking this repo's branch…"
        case .detachedHead:
            return "This repo is on a detached HEAD; no session corresponds to it."
        case .headUnavailable:
            return "Can't read this repo's HEAD — the path may be gone."
        case .wrongBranch(let current, let needs):
            return "On `\(current)`, this prompt needs `\(needs)`."
        case .noRoot:
            return "No GM_FS_ROOT resolved, so a pane would have no environment to record into."
        case .gmHookMissing(let root):
            return "No executable gm_hook at \(root)/bin/gm_hook — a pane on this root would record nothing, silently."
        case .noRepo:
            return "This instance has no resolved checkout on disk."
        case .pluginDirMissing(let path):
            return
                "This build's plugin directory is gone: \(path). `claude --plugin-dir` REPLACES the installed plugin and there is no fallback, so launching without it would silently run the installed plugin instead of this tree's. Restore it with `bash gmk/scripts/generate_plugin.sh`, then relaunch GMVibes."
        case .pluginManifestMissing(let path):
            return
                "No plugin manifest at \(path)/.claude-plugin/plugin.json. `claude --plugin-dir` REPLACES the installed plugin with no fallback, so a pane launched now would load a plugin serving none of the tools its agents are granted. Run `bash gmk/scripts/generate_plugin.sh`, then relaunch GMVibes."
        case .pluginVersionMismatch(let pluginVersion, let treeVersion):
            return
                "The plugin at \(PluginPreflight.directory ?? "—") is \(pluginVersion); that tree's gmk/VERSION says \(treeVersion). Run `bash gmk/scripts/generate_plugin.sh`, then relaunch GMVibes."
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

    private func failureCopy(
        _ error: ITerm2Error
    )
        -> (text: String, affordance: Affordance?, monospaced: Bool)
    {
        switch error {
        case .appNotInstalled:
            return ("iTerm2 isn't installed.", nil, false)

        case .apiDisabled, .apiServerUnavailable:
            return (
                "iTerm2's Python API is off. Turn it on in iTerm2 > Settings > "
                    + "General > Magic > Enable Python API, then press Play again.",
                .openITerm, false
            )

        case .automationDenied:
            return (
                "macOS denied GMVibes permission to control iTerm2.",
                .openAutomationSettings, false
            )

        case .handshakeFailed(let status):
            return ("iTerm2 refused the connection: \(status)", .copyCommand, true)
        case .launchRejected(let status):
            return ("iTerm2 rejected the launch: \(status)", .copyCommand, true)
        case .serverError(let detail):
            return ("iTerm2 reported an error: \(detail)", .copyCommand, true)
        case .transportFailed(let reason, let code):
            let suffix = code.map { " (errno \($0))" } ?? ""
            return ("Transport failed: \(reason)\(suffix)", .copyCommand, true)
        case .responseLost(let reason):
            return (
                "iTerm2 stopped answering after the launch was sent, so a window "
                    + "may already have opened — check iTerm2 before pressing Play "
                    + "again. (\(reason))", .copyCommand, true
            )

        case .unsafeCommandPath(let path):
            return ("Refused to launch: unusable path \(path)", .copyCommand, true)
        case .cancelled:
            return ("Launch cancelled.", nil, false)
        }
    }

    /// The environment's badge text — the pane's HEADER. Production carries
    /// none, mirroring paneBackgroundHex's nil: both channels answer "which
    /// environment is this pane writing to", and production's answer is
    /// silence.
    private var envBadgeText: String? {
        let kind = EnvironmentKind.current
        return kind == .production ? nil : kind.displayName.uppercased()
    }

    @MainActor
    private func play() async {
        guard block == nil, let root = gmFsRoot, let repo = repoFolder else { return }
        let script = paneLaunchScript(
            root: root,
            repoPath: repo.path,
            tabColorHex: launchColors.assign(promptUuid: stub.uuid).hex,
            tierCommand: tierCommand,
            pluginDir: PluginPreflight.directory,
            badgeText: envBadgeText,
            envBackgroundHex: EnvironmentKind.current.paneBackgroundHex
        )
        await launchPane(script: script, root: root, repo: repo)
    }

    /// The independent open: the same prepared pane, an interactive shell
    /// instead of a bot run. See the button's comment for why its gating is
    /// deliberately looser than Play's.
    @MainActor
    private func openTerminal() async {
        guard let root = gmFsRoot, !root.isEmpty, let repo = repoFolder else { return }
        let script = paneShellScript(
            root: root,
            repoPath: repo.path,
            tabColorHex: launchColors.assign(promptUuid: stub.uuid).hex,
            badgeText: envBadgeText,
            envBackgroundHex: EnvironmentKind.current.paneBackgroundHex,
            shell: loginShellPath()
        )
        await launchPane(script: script, root: root, repo: repo)
    }

    /// The launch dance both buttons share: profile, script on disk, command
    /// line, iTerm2 window. One implementation so the claude pane and the
    /// shell pane cannot drift in how they reach iTerm2.
    @MainActor
    private func launchPane(script: String, root: String, repo: URL) async {
        phase = .launching(.preparing)
        var scriptURL: URL?
        do {
            let profileName = await ITerm.ensureProfile(
                instanceUUID: windowID.instanceUUID,
                instanceName: instanceName,
                workingDir: repo.path
            )
            scriptURL = try PaneScriptWriter.write(script: script, root: root)
            let command = try paneCommandLine(
                shell: loginShellPath(),
                scriptPath: scriptURL!.path
            )
            let properties =
                ITerm.workingDirectoryProperties(repo.path) + [
                    .string("Custom Command", "Yes"),
                    .string("Command", command),
                ]
            let session = try await ITerm2Launcher.launchPane(
                PaneLaunchRequest(
                    profileName: profileName,
                    profileProperties: properties
                ),
                progress: { stage in
                    MainActor.assumeIsolated { phase = .launching(stage) }
                }
            )
            phase = .launched(session)
        } catch {
            if let scriptURL { try? FileManager.default.removeItem(at: scriptURL) }
            phase = .failed(error)
        }
    }
}
