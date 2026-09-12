import SwiftUI

// Renders a plain string with find-in-page highlighting: every occurrence of the
// literal query gets a yellow background; the active occurrence (if it falls in
// this segment) is recolored GREEN per spec. Built on the same AttributedString
// range-walk the old reader used, but keyed by per-occurrence ordinal rather than
// by a structural anchor, so it can distinguish the Nth match within one string.
enum FindHighlight {
    static func attributed(_ source: String,
                           query: SearchQuery,
                           activeLocalOccurrence: Int?) -> AttributedString {
        var attr = AttributedString(source)
        let ranges = query.ranges(in: source)
        guard !ranges.isEmpty else { return attr }
        for (occ, found) in ranges.enumerated() {
            guard let attrRange = Range(found, in: attr) else { continue }
            if occ == activeLocalOccurrence {
                attr[attrRange].backgroundColor = Color.green.opacity(0.55)
                attr[attrRange].foregroundColor = .black
            } else {
                attr[attrRange].backgroundColor = Color.yellow.opacity(0.55)
            }
        }
        return attr
    }
}

// A text view that applies find highlighting when the query is active, and renders
// the plain source otherwise. Used for the read-only prompt sections and (in plain
// mode) the Memories reader while searching.
struct HighlightedText: View {
    let source: String
    let query: SearchQuery
    let activeLocalOccurrence: Int?
    var font: Font = .system(.body, design: .monospaced)

    var body: some View {
        Text(query.isActive
             ? FindHighlight.attributed(source, query: query, activeLocalOccurrence: activeLocalOccurrence)
             : AttributedString(source))
            .font(font)
            .textSelection(.enabled)
    }
}
