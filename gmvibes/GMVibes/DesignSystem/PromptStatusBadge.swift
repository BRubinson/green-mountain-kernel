import SwiftUI
import GMCCDaemonKit

/// Six-state lifecycle badge, shared by the prompt navigator and the phase
/// sections (moved out of SessionPromptEditorView, made internal).
struct PromptStatusBadge: View {
    let status: PromptStatus?
    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
    private var label: String { status?.rawValue.capitalized ?? "—" }
    var color: Color { Self.color(for: status) }

    /// The lifecycle palette — a static so callers (the lifecycle rail) read
    /// a color without instantiating a view.
    static func color(for status: PromptStatus?) -> Color {
        switch status {
        case .draft:        return .orange
        case .clarifying:   return .blue
        case .architecting: return .purple
        case .implementing: return .teal
        case .reviewing:    return .indigo
        case .done:         return .green
        case .none:         return .gray
        }
    }
}
