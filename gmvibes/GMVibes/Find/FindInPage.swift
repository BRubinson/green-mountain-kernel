import SwiftUI
import Observation

// Per-occurrence find-in-page over a set of ordered plain-text segments.
//
// The old anchor-based find engine counted matching *elements* — it could not
// count or step individual substring occurrences inside one blob of text. This is
// the missing piece: occurrences are enumerated per segment, concatenated in the
// host-provided segment order into a flat global list, and the active global index
// selects one occurrence (green) among all (yellow). Scrolling targets the segment
// that owns the active occurrence (a `Text` can't expose sub-string scroll anchors).

@Observable
final class FindController {
    var query: String = ""
    var activeIndex: Int = 0
    var isPresented: Bool = false

    var searchQuery: SearchQuery { SearchQuery(query, mode: .literal) }

    func reset() { activeIndex = 0 }
}

// One match in the flat global list.
struct FindHit: Equatable {
    let segmentID: String
    let segmentIndex: Int
    let localOccurrence: Int   // 0-based index of this match within its segment
}

// Computed view over an ordered segment list for a given query. Pure value type —
// the host recomputes it each render from its known, deterministically-ordered
// segments, so there is no shared mutable registry to race on.
struct FindMatches {
    let hits: [FindHit]

    init(segments: [(id: String, text: String)], query: SearchQuery) {
        guard query.isActive else { hits = []; return }
        var out: [FindHit] = []
        for (index, seg) in segments.enumerated() {
            let count = query.ranges(in: seg.text).count
            for occ in 0..<count {
                out.append(FindHit(segmentID: seg.id, segmentIndex: index, localOccurrence: occ))
            }
        }
        hits = out
    }

    var total: Int { hits.count }

    func clampedActive(_ active: Int) -> Int {
        guard total > 0 else { return 0 }
        return ((active % total) + total) % total
    }

    func activeHit(_ active: Int) -> FindHit? {
        guard total > 0 else { return nil }
        return hits[clampedActive(active)]
    }

    // Which local occurrence (if any) is the active one within `segmentID`.
    func activeLocalOccurrence(in segmentID: String, active: Int) -> Int? {
        guard let hit = activeHit(active), hit.segmentID == segmentID else { return nil }
        return hit.localOccurrence
    }
}

// MARK: - Count chip ("N of M") — shared.

struct FindCountChip: View {
    let current: Int
    let total: Int

    var body: some View {
        Text(label)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }

    private var label: String {
        total == 0 ? "No matches" : "\(current + 1) of \(total)"
    }
}

// MARK: - Inline find bar for read-only content

struct FindBar: View {
    @Bindable var find: FindController
    let total: Int
    let onStep: (Int) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $find.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onStep(+1) }
                .frame(minWidth: 160, maxWidth: 260)
            FindCountChip(current: find.activeIndex, total: total)
            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(total == 0)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button { onStep(+1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(total == 0)
                .keyboardShortcut("g", modifiers: .command)
            Button { find.isPresented = false; find.query = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
        .onChange(of: find.isPresented) { _, shown in if shown { focused = true } }
    }
}
