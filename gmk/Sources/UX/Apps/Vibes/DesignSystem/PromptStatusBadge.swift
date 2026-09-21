import SwiftUI

/// Three-state lifecycle badge, shared by the prompt navigator and the phase sections.
///
/// It reports only unstarted / running / finished, because that is all `PromptStatus` carries.
/// Workflow progress lives in the derived phase served by BOT_NEXT, and reading it here would
/// turn a pure function of a value the list already holds into a live call per prompt.
struct PromptStatusBadge: View {
    let status: PromptStatus?
    var tint: Color?
    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .overlay { Capsule().strokeBorder(tint ?? .clear, lineWidth: 1.5) }
    }
    private var label: String { status?.rawValue.capitalized ?? "—" }
    var color: Color { Self.color(for: status) }

    /// The lifecycle palette — a static so callers (the lifecycle rail) read
    /// a color without instantiating a view.
    static func color(for status: PromptStatus?) -> Color {
        // Three well-separated hues rather than three picked out of the old
        // six: orange / blue / green read as distinct at capsule size and in
        // both appearances, which mattered less when six shades shared the rail
        // and the reader was scanning position as much as colour.
        switch status {
        case .draft: return .orange
        case .initiated: return .blue
        case .done: return .green
        case .none: return .gray
        }
    }
}
