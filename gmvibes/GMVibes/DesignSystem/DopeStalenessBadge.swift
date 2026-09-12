import SwiftUI
import GMCCDaemonKit

/// ONE badge for both staleness types, generic over `DopeScopeStalenessReporting`.
///
/// MOVED (not copied) out of `BriefingPane` — the badge and the dot-path chip
/// flow were private there and served a single pane. `CarePackageStaleness`
/// carries the identical shape, so the care package's ghosts render as the same
/// pixels as a briefing's because this is literally the same view code.
/// BriefingPane must render IDENTICALLY after the extraction: it is a move,
/// not a redesign.
///
/// Staleness is the daemon's read-time computation (`DopeRepository.scopeStaleness`),
/// never a stored column. It warns, it never blocks — nothing here disables a
/// control or hides content.
///
/// The generic parameter is why the protocol exists at N=2: callers hand over
/// either `BriefingStaleness` (non-optional on `BriefingGetResponse`, promoted
/// to `Optional` at the call) or `CarePackageStaleness?` (nil on a daemon that
/// predates the additive field), and inference picks `S` up from the argument.
struct DopeStalenessBadge<S: DopeScopeStalenessReporting>: View {
    let staleness: S?

    var body: some View {
        if let staleness {
            let ghosts = staleness.ghostDotPaths
            if staleness.drifted || !ghosts.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        if let stamped = staleness.stampedRevision,
                           let current = staleness.currentRevision, staleness.drifted {
                            Text("Dope scope moved: composed at r\(stamped), now r\(current).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(ghosts, id: \.self) { path in
                            Text(path)
                                .font(.caption.monospaced())
                                .strikethrough()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                } label: {
                    Label(ghosts.isEmpty ? "dope drifted" : "dope drifted · \(ghosts.count) ghost\(ghosts.count == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: .capsule)
                        .foregroundStyle(.orange)
                }
                .disclosureGroupStyle(.automatic)
            }
        }
    }
}

// MARK: - Dot-path chips

/// One dope dot-path chip — the shared atom. A ghost (a path that no longer
/// resolves against the live scope) is struck through and demoted to secondary;
/// it is still rendered, because a dangling path is a legal state the user needs
/// to see, not an error to swallow.
struct DopeDotPathChip: View {
    let path: String
    let isGhost: Bool

    var body: some View {
        Text(path)
            .font(.caption.monospaced())
            .strikethrough(isGhost)
            .foregroundStyle(isGhost ? .secondary : .primary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(.quaternary.opacity(0.4), in: .capsule)
    }
}

/// The chip layout both panes share, for callers that have bare dot-paths and
/// nothing to hang off them. (The care package annotates each ref with its
/// curator note, so it composes `DopeDotPathChip` directly — same chip, same
/// pixels, one extra caption line.)
///
/// Simple wrapping-free flow: dot-paths are short and few; a vertical list keeps
/// them selectable and legible without a layout dependency.
func dopeChipFlow(paths: [String], ghosts: Set<String>) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        ForEach(paths, id: \.self) { path in
            DopeDotPathChip(path: path, isGhost: ghosts.contains(path))
        }
    }
}
