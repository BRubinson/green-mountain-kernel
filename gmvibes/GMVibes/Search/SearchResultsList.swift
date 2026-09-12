import SwiftUI
import GMCCDaemonKit

/// The one SEARCH hit list, shared by the ⌘K palette and the search screen.
/// `List` (not a glass-row ScrollView) because macOS gives it arrow-key
/// traversal and selection for free, matching KBiteSearchPane's hitList.
/// Rows render in the DAEMON'S order — SearchHit.score is bm25-derived and
/// comparable within a kind only, so any client-side re-sort would be noise.
struct SearchResultsList: View {
    let hits: [SearchHit]
    let searched: Bool
    let errorText: String?
    @Binding var selection: String?   // SearchHit.rowID
    let idleDescription: String
    let destination: (SearchHit) -> SessionWindowID?
    let onOpen: (SearchHit) -> Void

    var body: some View {
        if let errorText {
            ContentUnavailableView("Search Unavailable", systemImage: "bolt.slash",
                                   description: Text(errorText))
        } else if hits.isEmpty {
            ContentUnavailableView(
                searched ? "No Matches" : "Search",
                systemImage: "magnifyingglass",
                description: Text(searched
                    ? "Nothing in prompts, clarifications, architecture, exploration, or review matched."
                    : idleDescription)
            )
        } else {
            List(hits, id: \.rowID, selection: $selection) { hit in
                SearchHitRow(hit: hit, navigable: destination(hit) != nil)
                    .tag(hit.rowID)
                    .contentShape(.rect)
                    .onTapGesture {
                        if destination(hit) != nil { onOpen(hit) }
                    }
            }
            .listStyle(.inset)
        }
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit
    let navigable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hit.resolvedKind?.systemImage ?? "questionmark.circle")
                .font(.callout)
                .foregroundStyle(hit.resolvedKind?.tint ?? .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(hit.resolvedKind?.label ?? hit.kind)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background((hit.resolvedKind?.tint ?? .gray).opacity(0.15), in: .capsule)
                }
                // FTS5 snippet with empty highlight markers by construction —
                // render verbatim, no stripping needed.
                if !hit.excerpt.isEmpty {
                    Text(hit.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 5) {
                    Text(hit.sessionCode).font(.caption2.monospaced())
                    Text("·").foregroundStyle(.tertiary)
                    Text("#\(hit.promptSeq) \(hit.promptName)")
                        .font(.caption2)
                        .lineLimit(1)
                    PromptStatusBadge(status: PromptStatus(rawValue: hit.promptStatus))
                }
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if navigable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("This session isn't in the catalog snapshot yet — can't open it.")
            }
        }
        .padding(.vertical, 3)
        .opacity(navigable ? 1 : 0.55)
    }
}

/// Kind filter chip — the stateBorder idiom keeps the selected state from
/// shifting layout.
struct SearchKindChip: View {
    let kind: SearchKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(kind.label, systemImage: kind.systemImage)
                .font(.caption)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? kind.tint : .secondary)
        .background(kind.tint.opacity(isOn ? 0.15 : 0), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .stateBorder(kind.tint, active: isOn, cornerRadius: 999)
    }
}
