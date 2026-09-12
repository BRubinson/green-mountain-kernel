import SwiftUI

// Multi-select pill box for managing which kbites are active on a prompt. Renders
// one toggleable capsule per available kbite; selected pills are filled with the
// accent tint, unselected are outlined. Binds to the caller's selection list and
// keeps it ordered to match `available` for a stable on-disk registry. Wraps via
// an internal flow layout.
struct KBitePillBox: View {
    let available: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("KBites").font(.headline)
                Spacer()
                Text("\(selected.count)/\(available.count)")
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            if available.isEmpty {
                Text("No kbites in the GMCC database yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                KBiteFlowLayout(spacing: 6) {
                    ForEach(available, id: \.self) { name in
                        KBitePill(name: name, isSelected: selected.contains(name)) {
                            toggle(name)
                        }
                    }
                }
            }
            Text("Which kbites are active on this prompt — tap to toggle.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func toggle(_ name: String) {
        if selected.contains(name) {
            selected.removeAll { $0 == name }
        } else {
            // Keep `available` ordering so the persisted list is stable.
            selected = available.filter { selected.contains($0) || $0 == name }
        }
    }
}

private struct KBitePill: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.small)
                Text(name)
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                          : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Remove \(name) from this prompt" : "Add \(name) to this prompt")
    }
}

// Wrapping flow layout: lays subviews left-to-right, wrapping to the next row when
// the proposed width is exceeded.
private struct KBiteFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
