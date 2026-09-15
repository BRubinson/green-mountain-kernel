import SwiftUI
import GmDaemonSdk

/// Three-state lifecycle badge, shared by the prompt navigator and the phase
/// sections (moved out of SessionPromptEditorView, made internal).
///
/// IT SHOWS LESS THAN IT USED TO, and that is worth knowing rather than
/// discovering. m0028 collapsed the lifecycle from six states to three, so this
/// badge can say only whether a prompt is unstarted, running, or finished — it
/// can no longer say whether a running prompt is clarifying, architecting,
/// implementing or reviewing.
///
/// That detail is not lost, it moved: phase is derived from db evidence at every
/// BOT_NEXT, and there are twelve phases rather than the six states this badge
/// used to approximate. Showing real progress again means reading the derived
/// phase rather than the prompt row. That is deliberately NOT done here — it is
/// a live call per prompt where this is a pure function of a value the list
/// already holds, and wiring it belongs to whoever wants the feature, with the
/// twelve-phase vocabulary designed for properly.
///
/// IT NOW CARRIES TWO FACTS, and they are independent. The FILL is the
/// lifecycle — draft / initiated / done — and is untouched by anything below.
/// The optional `tint` is a RING drawn around it, and it means something else
/// entirely: which iTerm2 pane this prompt was launched into. The launch tint is
/// in-memory only (`LaunchColorRegistry`), so it is ABSENT AFTER A RESTART BY
/// DESIGN — a prompt whose pane is gone should not still claim a colour.
///
/// `tint` has a default, so every existing call site compiles unchanged and
/// opting in is per-call-site rather than global.
struct PromptStatusBadge: View {
    let status: PromptStatus?
    /// The launch colour, additive. nil renders exactly what this badge always
    /// rendered.
    var tint: Color? = nil
    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            // ADDITIVE: a ring outside the lifecycle fill, never a replacement
            // for it. The two facts must stay separable at a glance.
            .overlay { Capsule().strokeBorder(tint ?? .clear, lineWidth: 1.5) }
    }
    private var label: String { status?.rawValue.capitalized ?? "—" }
    var color: Color { Self.color(for: status) }

    /// The lifecycle palette — a static so callers (the lifecycle rail) read
    /// a color without instantiating a view. ITS SIGNATURE IS UNCHANGED and
    /// stays that way: the launch tint is not a lifecycle state and has no
    /// business in here.
    static func color(for status: PromptStatus?) -> Color {
        // Three well-separated hues rather than three picked out of the old
        // six: orange / blue / green read as distinct at capsule size and in
        // both appearances, which mattered less when six shades shared the rail
        // and the reader was scanning position as much as colour.
        switch status {
        case .draft:     return .orange
        case .initiated: return .blue
        case .done:      return .green
        case .none:      return .gray
        }
    }
}
