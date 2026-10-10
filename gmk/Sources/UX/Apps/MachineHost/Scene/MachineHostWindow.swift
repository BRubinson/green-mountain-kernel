import SwiftUI

/// The root view of the `gm_machine_host` scene: status, displays, workstations, workspaces, app rules, keys.
struct MachineHostWindow: View {
    @Environment(MachineHostService.self) private var host
    /// The workstation the user picked for the grid; nil follows the active one.
    @State private var pickedWorkstation: String?

    var body: some View {
        Form {
            MachineHostStatusBanner()
            MachineSection()
            DisplaysSection()
            WorkstationsSection(selection: selection)
            WorkspaceGridSection(workstationUuid: selection.wrappedValue)
            AppRulesSection()
            KeyLegendSection()
        }
        .formStyle(.grouped)
        .frame(minWidth: 680, minHeight: 560)
        .onChange(of: host.snapshot?.activeWorkstationUuid) { _, active in
            if pickedWorkstation == active { pickedWorkstation = nil }
        }
        // The Dock/⌘-Tab presence lease, held by the window, as GMVibesWindow holds it.
        .task {
            WindowPresence.shared.acquire()
            host.trust.startPolling()
            defer {
                host.trust.stopPolling()
                WindowPresence.shared.release()
            }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        }
        // Re-read on appear and whenever the mirror writer changes the store; edits re-read themselves.
        .task(id: host.revision) { await host.reload() }
    }

    /// The grid's workstation: the picked one while it still exists, else the active one.
    ///
    /// Picking the active workstation clears the pick, so the grid follows the next switch.
    private var selection: Binding<String?> {
        Binding(
            get: {
                let active = host.snapshot?.activeWorkstationUuid
                guard let picked = pickedWorkstation,
                    host.snapshot?.workstations.contains(where: { $0.uuid == picked }) == true
                else { return active }
                return picked
            },
            set: { picked in
                pickedWorkstation = picked == host.snapshot?.activeWorkstationUuid ? nil : picked
            }
        )
    }
}

/// The status line at the top of the scene, with the action each state offers.
struct MachineHostStatusBanner: View {
    @Environment(MachineHostService.self) private var host

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(MachineHostStatusText.line(host.status))
                Spacer(minLength: 0)
                if host.status == .notTrusted {
                    Button("Reset & Re-prompt") { host.trust.resetAndPrompt() }
                }
            }
            if let error = host.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// The SF Symbol for the current status.
    private var symbol: String {
        switch host.status {
        case .running(let conflicts): conflicts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .off: "pause.circle"
        case .acquiringLock, .stopping: "hourglass"
        case .managedBy: "lock.fill"
        case .otherManagerRunning: "exclamationmark.triangle.fill"
        case .notTrusted, .failed: "exclamationmark.octagon.fill"
        }
    }

    /// The tint for the current status.
    private var color: Color {
        switch host.status {
        case .running(let conflicts): conflicts.isEmpty ? .green : .orange
        case .off, .acquiringLock, .stopping: .secondary
        case .managedBy, .otherManagerRunning, .notTrusted: .orange
        case .failed: .red
        }
    }
}

/// The words for a machine-host status, shared by the scene and the menu bar.
enum MachineHostStatusText {
    /// One line describing `status`.
    ///
    /// - Parameter status: The service status.
    /// - Returns: The line.
    static func line(_ status: MachineHostService.Status) -> String {
        switch status {
        case .off: return "Window management is off"
        case .acquiringLock: return "Starting…"
        case .managedBy(let root): return "Managed by \(root.isEmpty ? "another root" : root)"
        case .otherManagerRunning: return "Quit AeroSpace to enable window management"
        case .notTrusted: return "Accessibility not granted"
        case .running(let conflicts):
            return conflicts.isEmpty ? "Window management is on" : "\(conflicts.count) hotkey conflicts"
        case .stopping: return "Returning windows…"
        case .failed(let message): return message
        }
    }
}
