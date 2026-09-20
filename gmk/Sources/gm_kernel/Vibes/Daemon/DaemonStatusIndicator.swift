import SwiftUI
import GmDaemonSdk

// The old dot-style DaemonStatusIndicator is gone — the top bar's
// GmDaemonStatus pill (Chrome/GmDaemonStatus.swift) is the single status
// control, and it reuses this popover verbatim.
struct DaemonStatusPopover: View {
    @Environment(DaemonConnectionModel.self) private var daemon

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline

            switch daemon.health {
            case .up:
                detailRows
            case .down(let reason, let intentional):
                Text(intentional ? "The daemon was stopped." : reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                startButton
            case .notInstalled:
                // Resolved, never a literal: with three environments a hardcoded root in a
                // diagnostic is a wrong answer. A declared test/beta root is staged from a
                // checkout by gm_env.sh; "prod" routes to the installer, because gm_env.sh
                // refuses to create prod.
                Text(
                    Paths.declaredEnvironmentName.flatMap { env in
                        env == "prod"
                            ? nil
                            : "Daemon binary missing at \(Paths.binDaemon.path).\nStage binaries with bash gmk/scripts/gm_env.sh create \(env)."
                    }
                        ?? "Daemon binary missing at \(Paths.binDaemon.path).\nRun plugins/gmcc/scripts/install_gm.sh, or bash gmk/scripts/rebuild_local.sh from a checkout."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .incompatible(let daemonVersion):
                Text(
                    "The running daemon speaks protocol v\(daemonVersion.map(String.init) ?? "?"), newer than this build of GMVibes (v\(GmWireProtocol.version)). Rebuild GMVibes against the updated daemon package."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .starting:
                ProgressView().controlSize(.small)
            case .unknown:
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 280, alignment: .leading)
        // Keep counts/uptime live while the popover stays open.
        .task {
            while !Task.isCancelled {
                await daemon.refreshStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(daemon.health == .up ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(headlineText)
                .font(.headline)
        }
    }

    private var headlineText: String {
        switch daemon.health {
        case .up: return "Daemon healthy"
        case .down: return "Daemon down"
        case .notInstalled: return "Daemon not installed"
        case .incompatible: return "Rebuild GMVibes"
        case .starting: return "Starting daemon…"
        case .unknown: return "Daemon status unknown"
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let status = daemon.status {
                row("PID", "\(status.daemonPid)")
                row("Protocol", "v\(status.protocolVersion)")
                row("Schema", "v\(status.schemaVersion)")
                row("Uptime", Self.formatUptime(status.uptimeSeconds))
            }
            if let ping = daemon.ping {
                row("Build", "\(ping.buildSha) · \(ping.buildDate)")
            }
        }
        .font(.caption.monospaced())

        if let counts = daemon.status?.tableCounts, !counts.isEmpty {
            Divider()
            // The db has ~70 tables — unbounded this runs off the screen.
            ScrollView(.vertical) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(counts, id: \.name) { table in
                        row(table.name, "\(table.count)")
                    }
                }
                .font(.caption2.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var startButton: some View {
        Button {
            Task { await daemon.startDaemon() }
        } label: {
            Label("Start daemon", systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private static func formatUptime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
