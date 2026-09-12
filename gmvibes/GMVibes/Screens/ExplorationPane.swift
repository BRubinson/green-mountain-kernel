import SwiftUI
import GMCCDaemonKit

/// Read-only exploration section (EXPLORE_GET, m0025 per-agent rows):
/// every summary (synthesis first) + key files + PARTITIONED findings —
/// full rows are the sub-threshold/unranked set, rendered IN WIRE ORDER
/// (unranked first is the daemon's resume-queue contract, never re-sorted),
/// stubs collapse behind a one-shot full:true widen. All exploration writes
/// stay bot/CLI-side.
struct ExplorationPane: View {
    let phase: PromptPhaseStore.Phase<ExploreGetResponse>
    /// Widen the store to full:true — invoked once when the user reveals the
    /// at/above-threshold stubs. Keeps the pane a pure function of its phase.
    let onRequestFull: () async -> Void

    @State private var showLowPriority = false
    @State private var showTombstones = false
    @State private var isWidening = false

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading exploration…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            Label("Not opened yet — run the bot to start exploration.",
                  systemImage: "binoculars")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .loaded(let response):
            content(response)
        }
    }

    @ViewBuilder
    private func content(_ response: ExploreGetResponse) -> some View {
        let visible = response.findings.visibleFindings(
            showLowPriority: showLowPriority, showTombstones: showTombstones
        )
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Spacer()
                ReportBadgeCluster(items: ReportBadgeItem.exploration(response))
            }

            // m0025: one summary row per agent, synthesis (the seal) first.
            // Overviews are written only by each summary's COMPLETE —
            // legitimately empty while still exploring.
            ForEach(response.summaries, id: \.uuid) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(summary.agentType)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(.secondary)
                        statusChip(summary.explorationStatus)
                        Spacer()
                    }
                    if !summary.overview.isEmpty {
                        Text(summary.overview)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.indigo.opacity(0.06), in: .rect(cornerRadius: 8))
                    }
                }
            }

            if !response.keyFiles.isEmpty {
                sectionHeader("Key Files")
                ForEach(response.keyFiles, id: \.uuid) { keyFile in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(keyFile.filePath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            }

            if !visible.isEmpty {
                sectionHeader("Findings")
                ForEach(visible, id: \.uuid) { finding in
                    findingRow(finding)
                }
            }

            // The at/above-threshold partition, collapsed by default. When
            // the store is already full the toggle alone re-partitions
            // client-side; otherwise it also triggers the one-shot widen.
            if !response.findingStubs.isEmpty && !showLowPriority {
                HStack(spacing: 8) {
                    Text("\(response.findingStubs.count) more findings at or above the read threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isWidening {
                        // Reveal only after the full payload lands — flipping
                        // showLowPriority first left a gap where neither the
                        // strip nor the revealed rows were on screen.
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Show all") {
                            Task {
                                isWidening = true
                                await onRequestFull()
                                isWidening = false
                                showLowPriority = true
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }

            if showLowPriority, response.findings.tombstoneCount > 0 {
                Toggle("Show \(response.findings.tombstoneCount) false-positive tombstones",
                       isOn: $showTombstones)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
            }
        }
    }

    private func findingRow(_ finding: ExplorationFindingRow) -> some View {
        DisclosureGroup {
            Text(finding.body)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
        } label: {
            HStack(spacing: 8) {
                let style = ReportKindStyle.exploration(finding.kind)
                FindingKindBadge(label: style.label, tint: style.tint)
                Text(finding.title)
                    .font(.callout)
                    .lineLimit(1)
                FindingRatingPill(rating: finding.findingRating)
                Spacer()
                Text(finding.agentName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func statusChip(_ status: ExplorationStatus?) -> some View {
        let (label, color): (String, Color) = switch status {
        case .exploring: ("Exploring", .orange)
        case .complete: ("Complete", .green)
        case .none: ("—", .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
