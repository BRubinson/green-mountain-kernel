import AppKit
import SwiftUI

/// Which role this process holds over the database.
enum KernelRole: Equatable, Sendable {
    /// This process took the lock and serves the database.
    case writer
    /// This process won the lock but the database failed to open, so nobody is serving.
    case unknown
}

/// The menu bar dropdown's content.
///
/// STYLE REQUIREMENT: written for `.menuBarExtraStyle(.window)`, not the default `.menu`.
/// AppKit's menu style renders only menu items and drops the role row's colour and layout,
/// and the role row is the one thing here that has to be unmissable.
///
/// Every action is INJECTED: this view knows the order of the rows and the words on them,
/// and nothing about how a window is opened.
struct KernelMenuBarContent: View {
    let role: KernelRole
    let vitals: KernelVitals
    let protocolVersion: Int?
    let buildSha: String?
    let onNewWindow: () -> Void
    let onQuit: () -> Void

    /// Two-step quit, in place.
    ///
    /// NOT a `confirmationDialog`: the menu bar panel is a transient window
    /// that dismisses the moment focus leaves it, which takes any sheet or
    /// alert presented from it down too — the confirmation would flash and
    /// vanish, reading as a quit that did not happen.
    @State private var confirmingQuit = false

    /// Creates the menu bar dropdown view with all required state and callbacks.
    ///
    /// - Parameters:
    ///   - role: The kernel's current role (writer, or unknown when the database failed to open).
    ///   - vitals: Live kernel vitals (uptime, memory, CPU).
    ///   - protocolVersion: Wire protocol version, or `nil` if unknown.
    ///   - buildSha: Build identifier, or `nil` if unknown.
    ///   - onNewWindow: Callback to open a new window.
    ///   - onQuit: Callback to quit the kernel.
    init(
        role: KernelRole,
        vitals: KernelVitals,
        protocolVersion: Int? = nil,
        buildSha: String? = nil,
        onNewWindow: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.role = role
        self.vitals = vitals
        self.protocolVersion = protocolVersion
        self.buildSha = buildSha
        self.onNewWindow = onNewWindow
        self.onQuit = onQuit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            roleRow

            Divider()
            vitalRows
            Divider()
            buildRow

            Divider()
            menuRow("New Vibe Window", systemImage: "macwindow.badge.plus") {
                // BEFORE the open, always. An LSUIElement process can order a window on
                // screen without becoming active, leaving the new window unfocused behind
                // whatever the user was in. Not redundant with `WindowPresence`: this
                // activates the current accessory process so the open is seen, while
                // WindowPresence re-activates after the policy is raised.
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

    /// FIRST row, and deliberately so: a kernel that won the lock but serves
    /// nothing must be visible the moment the panel opens.
    ///
    /// It gets the colour, the weight and the top of the panel.
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
    }

    private var roleTitle: String {
        switch role {
        case .writer: return "WRITER"
        case .unknown: return "ROLE UNKNOWN"
        }
    }

    private var roleSymbol: String {
        switch role {
        case .writer: return "lock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var roleColor: Color {
        switch role {
        case .writer: return .green
        case .unknown: return .gray
        }
    }

    private var roleDetail: String? {
        switch role {
        case .writer:
            return "This kernel owns the database."
        case .unknown:
            return "The lock is held but the database failed to open."
        }
    }

    /// Title and detail as one sentence: "WRITER — This kernel owns the database.".
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

    /// Builds a menu-style row suitable for the window panel layout.
    ///
    /// Provides full-width hit target with a secondary symbol and no button chrome.
    /// (`.menu` style provides this by default; `.window` style does not.)
    ///
    /// - Parameters:
    ///   - title: The row text label.
    ///   - systemImage: The SF Symbols name for the icon.
    ///   - action: Callback invoked when the row is selected.
    /// - Returns: A styled menu row view.
    private func menuRow(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
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
