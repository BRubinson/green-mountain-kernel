import SwiftUI

/// Read-only review section (REVIEW_GET): verdict + overview + PARTITIONED
/// findings with per-finding fix-loop resolution badges — full rows rendered
/// IN WIRE ORDER (unranked first, the resume-queue contract), stubs collapse
/// behind a one-shot full:true widen.
///
/// All review writes stay bot/CLI-side.
struct ReviewPane: View {
    let phase: PromptPhaseStore.Phase<ReviewGetResponse>
    /// Widen the store to full:true — invoked once when the user reveals the
    /// at/above-threshold stubs.
    let onRequestFull: () async -> Void

    @State private var showLowPriority = false
    @State private var showTombstones = false
    @State private var isWidening = false

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading review…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            Label(
                "Not opened yet — run the bot to start review.",
                systemImage: "checkmark.seal"
            )
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

    /// Builds the review panel content from the response.
    /// - Parameter response: The review response to display.
    /// - Returns: A view containing the review status, verdict, findings, and controls.
    @ViewBuilder
    private func content(_ response: ReviewGetResponse) -> some View {
        let visible = response.findings.visibleFindings(
            showLowPriority: showLowPriority,
            showTombstones: showTombstones
        )
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusChip(response.summary.reviewStatus)
                verdictChip(response.summary.verdict)
                Spacer()
                ReportBadgeCluster(items: ReportBadgeItem.review(response))
            }

            // Overview is written only by REVIEW_COMPLETE — legitimately
            // empty while still reviewing.
            if !response.summary.overview.isEmpty {
                Text(response.summary.overview)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.pink.opacity(0.06), in: .rect(cornerRadius: 8))
            }

            if !visible.isEmpty {
                sectionHeader("Findings")
                ForEach(visible, id: \.uuid) { finding in
                    findingRow(finding)
                }
            }

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
                Toggle(
                    "Show \(response.findings.tombstoneCount) false-positive tombstones",
                    isOn: $showTombstones
                )
                .font(.caption)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
            }
        }
    }

    /// Builds a row view for a single finding.
    /// - Parameter finding: The finding to display.
    /// - Returns: A disclosure group with the finding details and metadata.
    private func findingRow(_ finding: ReviewFindingRow) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if let path = finding.filePath {
                    Text(location(path: path, start: finding.lineStart, end: finding.lineEnd))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(finding.body)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
            }
        } label: {
            HStack(spacing: 8) {
                let style = ReportKindStyle.review(finding.kind)
                FindingKindBadge(label: style.label, tint: style.tint)
                Text(finding.title)
                    .font(.callout)
                    .lineLimit(1)
                FindingRatingPill(rating: finding.findingRating)
                ResolutionBadge(rawStatus: finding.status)
                Spacer()
                Text(finding.agentName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Formats a file location as a string for display.
    ///
    /// A nil path indicates a cross-cutting finding per the wire contract, so no location row is shown.
    /// - Parameters:
    ///   - path: The file path; may be nil for cross-cutting findings.
    ///   - start: The starting line number, or nil for a path-only location.
    ///   - end: The ending line number, or nil for a single-line location.
    /// - Returns: The formatted location string like "path:line" or "path:start–end".
    private func location(path: String, start: Int?, end: Int?) -> String {
        switch (start, end) {
        case (let s?, let e?) where s != e: "\(path):\(s)–\(e)"
        case (let s?, _): "\(path):\(s)"
        default: path
        }
    }

    /// Builds a styled section header view.
    /// - Parameter title: The header text.
    /// - Returns: A text view styled as a section header.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Builds a status chip view for the review status.
    /// - Parameter status: The review status to display.
    /// - Returns: A capsule-styled chip with the status label and color.
    @ViewBuilder
    private func statusChip(_ status: ReviewSummaryStatus?) -> some View {
        let (label, color): (String, Color) =
            switch status {
            case .reviewing: ("Reviewing", .orange)
            case .complete: ("Complete", .green)
            case .none: ("—", .gray)
            }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    /// Builds a verdict chip view for the review verdict.
    ///
    /// Verdict is written only by REVIEW_COMPLETE and is nil while reviewing. Unknown raw verdicts
    /// render their raw string rather than vanishing.
    /// - Parameter raw: The raw verdict string, or nil if not yet complete.
    /// - Returns: A capsule-styled chip with the verdict label and color, or an empty view if nil.
    @ViewBuilder
    private func verdictChip(_ raw: String?) -> some View {
        if let raw {
            let display = ReviewVerdict(rawValue: raw)?.display ?? (raw, .gray)
            Text(display.label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(display.tint.opacity(0.18), in: .capsule)
                .foregroundStyle(display.tint)
        }
    }
}
