import AppKit
import SwiftUI

/// Which role the answering kernel holds over the database.
///
/// Mapped from the wire's `writer_role` string here rather than imported from
/// the kit, so this view's inputs stay three plain values: an unrecognised role
/// degrades to `.unknown` instead of asserting, because a menu bar that cannot
/// name the role is still better than one that refuses to draw.
enum KernelRole: Equatable, Sendable {
    case writer
    /// Another copy of the app owns the store. `holderPid` is the owning
    /// process, `bundlePath` the bundle it was launched from — both optional
    /// because a kernel that has not answered yet knows neither.
    case client(holderPid: Int32?, bundlePath: String?)
    case unknown

    init(writerRole: String?, holderPid: Int32?, bundlePath: String?) {
        switch writerRole {
        case "writer": self = .writer
        case "client": self = .client(holderPid: holderPid, bundlePath: bundlePath)
        default: self = .unknown
        }
    }
}

/// The menu bar dropdown's content.
///
/// STYLE REQUIREMENT: this is written for `.menuBarExtraStyle(.window)`, not the
/// default `.menu`. AppKit's menu style renders only menu items and drops the
/// role row's colour and layout on the floor — and the role row is the one thing
/// here that has to be unmissable, so the panel style is load-bearing rather
/// than a preference.
///
/// Every action is INJECTED. The scene, the `WindowGroup` value and the quit
/// path all belong to the app struct; this view knows the order of the rows and
/// the words on them, and nothing about how a window is opened.
struct KernelMenuBarContent: View {
    let role: KernelRole
    let vitals: KernelVitals
    let protocolVersion: Int?
    let buildSha: String?
    let onNewWindow: () -> Void
    let onQuit: () -> Void
    /// Client mode only: bring the kernel that actually owns the store to the
    /// front. nil when the owner cannot be activated (unknown bundle, or this
    /// kernel is the writer), and the row is absent rather than disabled.
    var onActivateHolder: (() -> Void)?

    /// Two-step quit, in place. NOT a `confirmationDialog`: the menu bar panel
    /// is a transient window that dismisses the moment focus leaves it, which
    /// takes any sheet or alert presented from it down too — the confirmation
    /// would flash and vanish, reading as a quit that did not happen.
    @State private var confirmingQuit = false

    init(role: KernelRole,
         vitals: KernelVitals,
         protocolVersion: Int? = nil,
         buildSha: String? = nil,
         onNewWindow: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onActivateHolder: (() -> Void)? = nil) {
        self.role = role
        self.vitals = vitals
        self.protocolVersion = protocolVersion
        self.buildSha = buildSha
        self.onNewWindow = onNewWindow
        self.onQuit = onQuit
        self.onActivateHolder = onActivateHolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            roleRow
            if case .client = role, let onActivateHolder {
                menuRow("Activate the running kernel", systemImage: "arrow.up.left.square") {
                    onActivateHolder()
                }
            }

            Divider()
            vitalRows
            Divider()
            buildRow

            Divider()
            menuRow("New Vibe Window", systemImage: "macwindow.badge.plus") {
                // BEFORE the open, always. An LSUIElement process is not a
                // regular app in the window server's eyes: it can order a
                // window on screen without ever becoming active, and the new
                // window then sits unfocused behind whatever the user was in.
                // Read as "the button does nothing", which is the single
                // easiest way to lose trust in a menu bar app.
                //
                // Still needed with `WindowPresence` in place, and the two are
                // not redundant: this activates the CURRENT (accessory) process
                // so the open is seen, while WindowPresence re-activates after
                // the policy is raised. Opening from zero windows needs both,
                // and opening from one needs only this one.
                NSApp.activate()
                onNewWindow()
            }
            quitRow
        }
        .padding(12)
        .frame(width: 288, alignment: .leading)
        // The dropdown is only on screen while the user is looking at it, so
        // the first numbers it shows are taken now rather than inherited from
        // whenever the last tick happened to land.
        .task { vitals.sampleNow() }
    }

    // MARK: - Role

    /// FIRST row, and deliberately so: client mode IS the mitigation for a
    /// second copy of the app opening the same database, and a mitigation the
    /// user cannot see mitigates nothing. It gets the colour, the weight and
    /// the top of the panel.
    @ViewBuilder
    private var roleRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: roleSymbol)
                Text(roleTitle)
                    .font(.caption.weight(.bold))
                    .monospaced()
            }
            .foregroundStyle(roleColor)

            if let detail = roleDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    // Middle truncation keeps both ends of a long bundle path:
                    // the volume says whether this is /Applications or somebody's
                    // build directory, and the name says which app it is.
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // The one-line form the role is specified in. Two stacked lines read
        // better in 288pt than one wrapped sentence, so the sentence itself
        // survives as the accessibility label and the tooltip rather than being
        // lost to the layout.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(roleSentence)
        .help(roleSentence)
        .background(roleColor.opacity(0.14), in: .rect(cornerRadius: 7))
        .overlay {
            // Only client mode gets a border. Writer mode is the expected
            // state and must not shout at the user every time they look.
            if case .client = role {
                RoundedRectangle(cornerRadius: 7).strokeBorder(roleColor.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private var roleTitle: String {
        switch role {
        case .writer: return "WRITER"
        case .client: return "CLIENT MODE"
        case .unknown: return "ROLE UNKNOWN"
        }
    }

    private var roleSymbol: String {
        switch role {
        case .writer: return "lock.fill"
        case .client: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var roleColor: Color {
        switch role {
        case .writer: return .green
        case .client: return .orange
        case .unknown: return .gray
        }
    }

    private var roleDetail: String? {
        switch role {
        case .writer:
            return "This kernel owns the database."
        case .client(let pid, let path):
            // The sentence the user has to be able to read off the screen:
            // which process owns the store, and which bundle it came from.
            let who = pid.map { "pid \($0)" } ?? "another kernel"
            let where_ = path ?? "path unknown"
            return "the database is owned by \(who) (\(where_))"
        case .unknown:
            return "The kernel has not reported a role yet."
        }
    }

    /// Title and detail as one sentence: "CLIENT MODE — the database is owned
    /// by pid 4213 (/Applications/GMVibes.app)".
    private var roleSentence: String {
        guard let detail = roleDetail else { return roleTitle }
        return "\(roleTitle) — \(detail)"
    }

    // MARK: - Vitals

    @ViewBuilder
    private var vitalRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("Uptime").foregroundStyle(.secondary)
                Text(vitals.uptimeText)
            }
            GridRow {
                Text("Memory").foregroundStyle(.secondary)
                Text(vitals.memoryText)
            }
            GridRow {
                Text("CPU").foregroundStyle(.secondary)
                Text(vitals.cpuText)
            }
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buildRow: some View {
        Text(buildText)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buildText: String {
        let version = protocolVersion.map { "protocol v\($0)" } ?? "protocol v?"
        let build = buildSha.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown build"
        return "\(version) · \(build)"
    }

    // MARK: - Actions

    /// Cmd-Q is deliberately unbound: a menu-bar-resident kernel that quits on
    /// a reflex keystroke takes the writer role down with it, and the windows
    /// are what the user meant to close.
    @ViewBuilder
    private var quitRow: some View {
        if confirmingQuit {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quit the kernel? Sessions lose their writer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Quit", role: .destructive) { onQuit() }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { confirmingQuit = false }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
        } else {
            menuRow("Quit GM Kernel", systemImage: "power") { confirmingQuit = true }
        }
    }

    /// A menu-shaped row for the panel style: full-width hit target, secondary
    /// symbol, no button chrome — `.menu` gives this for free and `.window`
    /// does not.
    private func menuRow(_ title: String,
                         systemImage: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 14)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
