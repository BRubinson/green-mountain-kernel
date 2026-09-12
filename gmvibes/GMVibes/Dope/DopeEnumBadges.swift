import SwiftUI
import GMCCDaemonKit

/// Single-line capsule strip of an enum's option codes with a trailing "+N"
/// overflow chip. `ViewThatFits` picks the widest candidate that fits the
/// width the property row leaves over.
///
/// The candidates are written out rather than generated with `ForEach`:
/// `ViewThatFits` flattening a `ForEach` into separate candidates is not a
/// documented guarantee, and silently getting ONE candidate would defeat the
/// whole mechanism. `limit` caps the ladder — a 40-option enum previews at
/// most `limit` chips; the inspector dialog is where all of them live.
struct DopeEnumBadgeStrip: View {
    let options: [DopeOptionNode]
    var limit = 6

    private var shown: Int { min(options.count, limit) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            candidate(shown)
            candidate(shown - 1)
            candidate(shown - 2)
            candidate(shown - 3)
            candidate(shown - 4)
            candidate(shown - 5)
            candidate(0)
        }
    }

    private func candidate(_ requested: Int) -> some View {
        let count = max(0, min(requested, shown))
        let hidden = options.count - count
        return HStack(spacing: 3) {
            ForEach(options.prefix(count), id: \.identity.uuid) { option in
                DopeOptionBadge(option: option)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.caption2.monospaced().weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(.secondary)
                    .background(.quaternary, in: .capsule)
                    .help("\(hidden) more option\(hidden == 1 ? "" : "s") — click the row to see them all")
            }
        }
        // LOAD-BEARING: without it every candidate reports a compressible
        // width, the first one always "fits", and no badge is ever dropped.
        .fixedSize()
    }
}

/// One option, styled like the existing `entityType` / `enum` chips.
private struct DopeOptionBadge: View {
    let option: DopeOptionNode

    var body: some View {
        Text(option.body.code)
            .font(.caption2.monospaced())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(.quaternary, in: .capsule)
            .help(option.body.description.isEmpty
                  ? option.body.name
                  : "\(option.body.name) — \(option.body.description)")
    }
}
