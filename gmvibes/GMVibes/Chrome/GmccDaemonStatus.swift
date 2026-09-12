import SwiftUI

/// The top-bar daemon status pill: "gmcc" in a capsule whose BORDER color
/// tracks daemon health. Clicking opens the same diagnostic popover as the old
/// dot indicator (`DaemonStatusPopover` reused verbatim).
struct GmccDaemonStatus: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Text("gmcc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(color, lineWidth: 1.5)
                }
                .animation(.snappy(duration: 0.18), value: color)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("GMCC daemon status")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            DaemonStatusPopover()
                .environment(daemon)
        }
    }

    private var color: Color {
        switch daemon.health {
        case .up: return .green
        case .down: return .red
        case .notInstalled: return .gray
        case .incompatible: return .orange
        case .starting: return .yellow
        case .unknown: return .gray.opacity(0.5)
        }
    }
}
