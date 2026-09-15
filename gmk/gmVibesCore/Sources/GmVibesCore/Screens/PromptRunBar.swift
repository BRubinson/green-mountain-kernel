import SwiftUI
import AppKit
import GmDaemonSdk
import GmITerm2Client

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

    private func failureCopy(_ error: ITerm2Error)
        -> (text: String, affordance: Affordance?, monospaced: Bool) {
        switch error {
        case .appNotInstalled:
            return ("iTerm2 isn't installed.", nil, false)

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

    @MainActor
    private func play() async {
        guard block == nil, let root = gmFsRoot, let repo = repoFolder else { return }
        phase = .launching(.preparing)
        let colour = launchColors.assign(promptUuid: stub.uuid)
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
            let properties = ITerm.workingDirectoryProperties(repo.path) + [
                .string("Custom Command", "Yes"),
                .string("Command", command),
            ]
            let session = try await ITerm2Launcher.launchPane(
                PaneLaunchRequest(profileName: profileName,
                                  profileProperties: properties),
                progress: { stage in
                    MainActor.assumeIsolated { phase = .launching(stage) }
                })
            phase = .launched(session)
        } catch {
            if let scriptURL { try? FileManager.default.removeItem(at: scriptURL) }
            phase = .failed(error)
        }
    }
}
