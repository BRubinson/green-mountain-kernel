import SwiftUI
import GMCCDaemonKit

/// Read-only briefing section (BRIEFING_LIST + per-row BRIEFING_GET): the
/// context packages a doper agent assembled per phase step. One sub-section
/// per row, keyed by `briefing_for_step` (registry-extensible — whatever LIST
/// returns is rendered, never a hardcoded step set). Staleness is the
/// daemon's read-time computation; it renders as a subtle amber badge with
/// expandable ghost-path detail — warn, never block. That badge and the
/// dot-path chip flow now live in `DesignSystem/DopeStalenessBadge.swift`,
/// shared verbatim with the care package. All briefing writes stay
/// bot/CLI-side.
struct BriefingPane: View {
    let phase: PromptPhaseStore.Phase<[PromptPhaseStore.BriefingItem]>

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading briefings…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            notOpened
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .loaded(let items):
            if items.isEmpty {
                // Empty list IS the never-opened state — briefings have no
                // SUMMARY_ABSENT on LIST.
                notOpened
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(items, id: \.briefing.uuid) { item in
                        section(item)
                    }
                }
            }
        }
    }

    private var notOpened: some View {
        Label("No briefings yet — the doper writes one at each phase boundary.",
              systemImage: "shippingbox")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func section(_ item: PromptPhaseStore.BriefingItem) -> some View {
        let briefing = item.briefing
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(stepTitle(briefing.briefingForStep))
                    .font(.subheadline.weight(.semibold))
                statusChip(briefing.status)
                DopeStalenessBadge(staleness: item.staleness)
                Spacer()
            }

            // m0025: briefings are opinion-free ref sets — typed child
            // rows, no body. Refs are legitimately empty while building.
            let dopePaths = briefing.dopeRefs.map(\.dopeCode)
            if !dopePaths.isEmpty {
                sectionHeader("Dope Refs")
                dopeChipFlow(paths: dopePaths, ghosts: Set(item.staleness.ghostDotPaths))
            }

            if !briefing.kbiteRefs.isEmpty {
                sectionHeader("KBites")
                ForEach(briefing.kbiteRefs, id: \.uuid) { ref in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "text.book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text((ref.brief?.isEmpty ?? true) ? ref.kbiteResourceFileUuid : ref.brief!)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            }

            if !briefing.fileChangeRefs.isEmpty {
                sectionHeader("File Changes")
                ForEach(briefing.fileChangeRefs, id: \.uuid) { ref in
                    Text(ref.fileChangeUuid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Bits

    private func stepTitle(_ raw: String) -> String {
        raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "ready": ("Ready", .green)
        case "building": ("Building", .orange)
        default: (status, .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
