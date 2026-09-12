import SwiftUI
import GMCCDaemonKit

/// The prompt's `bot_workflow` phase graph, rendered from BOT_NEXT's derived
/// view: one pill per phase of the variant's graph, the served phase
/// highlighted, entry blockers listed underneath.
///
/// **Read-only.** The app never advances the machine; BOT_NEXT is addressed
/// by prompt uuid and never carries a client key, so a live terminal's claim
/// is never stolen.
///
/// **A leaf, by construction.** This view returns `EmptyView()` for every
/// non-`.loaded` phase state. It is a SIBLING of `PromptStatusHeader`, never
/// its parent — it has no say in whether the lifecycle controls render. That
/// is the structural mitigation for deleting the lifecycle rail: the strip
/// can vanish entirely and the surviving header is still a correct,
/// actionable control.
///
/// A variant this build does not recognise is NOT one of those vanishing
/// cases: `WorkflowStripModel.make` degrades it to a one-pill model carrying
/// the served phase with no variant label, and the strip renders that pill.
/// Daemon/app version skew has to stay visible on screen rather than looking
/// identical to "no workflow row".
///
/// There is deliberately no loading spinner, no error banner and no
/// empty-state copy. A prompt with no workflow row (never started, and
/// `/gm_task` where the absence is permanent) shows the header alone — the
/// settled decision.
struct WorkflowStrip: View {
    let phase: PromptPhaseStore.Phase<BotNextResponse>

    /// `nil` only for the genuinely absent cases — `.idle` / `.absent` /
    /// `.failed`, i.e. any non-`.loaded` state. Every `.loaded` response
    /// renders, including the degraded one-pill model an unrecognised variant
    /// produces (`variantLabel == nil`), which draws a single unlabelled pill
    /// rather than nothing.
    private var model: WorkflowStripModel? {
        guard case .loaded(let response) = phase else { return nil }
        return WorkflowStripModel.make(response)
    }

    var body: some View {
        if let model {
            VStack(alignment: .leading, spacing: 6) {
                pillRow(model)
                ForEach(model.blockers, id: \.self) { blocker in
                    // The deleted bar's OWN idiom, on display-ready prose
                    // straight from BotWorkflowRepository.entryBlockers — no
                    // client interpretation of the daemon's reason strings.
                    Label(blocker, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Pills

    private func pillRow(_ model: WorkflowStripModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 10 / 11 / 12 pills per variant — a long row on a narrow pane,
            // so it scrolls rather than truncating the graph.
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.pills) { pill in
                        self.pill(pill)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            if let label = model.variantLabel {
                Text(model.closed ? "\(label) · closed" : label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func pill(_ pill: WorkflowStripModel.Pill) -> some View {
        Text(pill.title)
            .font(.caption2.weight(pill.state == .current ? .semibold : .regular))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(background(for: pill.state), in: .capsule)
            .foregroundStyle(tint(for: pill.state))
            // The exact compiled-in prose the bot reads at that phase. A full
            // instruction panel is a layout project and was cut; the tooltip
            // is the whole per-phase detail surface.
            .help(pill.instructions ?? "Phase \(pill.id) — not in this build's workflow spec")
    }

    private func tint(for state: WorkflowStripModel.PillState) -> AnyShapeStyle {
        switch state {
        case .done:    AnyShapeStyle(.secondary)
        case .current: AnyShapeStyle(Color.accentColor)
        case .pending: AnyShapeStyle(.tertiary)
        // A phase this build's WorkflowSpec does not contain: the daemon is
        // ahead of (or behind) the app. Amber = warn, never block.
        case .unknown: AnyShapeStyle(Color.orange)
        }
    }

    private func background(for state: WorkflowStripModel.PillState) -> AnyShapeStyle {
        switch state {
        case .current: AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .unknown: AnyShapeStyle(Color.orange.opacity(0.15))
        case .done:    AnyShapeStyle(.quaternary.opacity(0.5))
        case .pending: AnyShapeStyle(Color.clear)
        }
    }
}
