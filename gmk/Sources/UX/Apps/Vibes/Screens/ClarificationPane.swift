import SwiftUI

/// The app's render of the db-native clarification over CLARIFY_GET: questions with their
/// option and selection children, weighted internal notes, and the care package.
///
/// ANSWERING is the one write door here, and the app's only report-subsystem write: while the
/// summary is `answering`, a question card can select options, type an answer or skip through
/// CLARIFY_ANSWER. Everything else stays bot/CLI-side. ONE data path — the pane holds the
/// whole `ClarifyGetResponse`, so nothing below it introduces a second fetch.
struct ClarificationPane: View {
    let phase: PromptPhaseStore.Phase<ClarifyGetResponse>
    /// Held ONLY so the question cards can reach `phases.answers` — the
    /// per-question draft/version cells every CLARIFY_GET reconciles.
    ///
    /// The pane itself issues nothing through it.
    let phases: PromptPhaseStore

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading clarification…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            // Stays READ-ONLY: every clarify write is bot/CLI-side by design.
            Label(
                "Not opened yet — run the bot to start clarification.",
                systemImage: "questionmark.circle"
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

    /// Renders the clarification response content with status, care package, questions, and notes.
    ///
    /// - Parameter response: The clarification response to display.
    /// - Returns: A view displaying the response content.
    @ViewBuilder
    private func content(_ response: ClarifyGetResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusChip(response.summary.clarificationStatus)
                Spacer()
            }

            if let package = response.carePackage {
                // The pane already holds the whole ClarifyGetResponse, so the
                // staleness report is in hand — no second fetch for the
                // expanded care package. INVARIANT: carePackageStaleness is
                // non-nil IFF carePackage is (nil also on a pre-field daemon).
                CarePackageSection(
                    package: package,
                    staleness: response.carePackageStaleness
                )
            }

            if !response.questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(response.questions, id: \.uuid) { question in
                        ClarificationQuestionCard(
                            question: question,
                            clarificationStatus: response.summary.clarificationStatus,
                            answers: phases.answers
                        )
                    }
                }
            }

            if !response.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Internal Notes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(response.notes, id: \.uuid) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    // MARK: Notes

    /// Renders a single internal note row with optional weight indicator.
    ///
    /// - Parameter note: The note row to display.
    /// - Returns: A view displaying the note with weight and body.
    private func noteRow(_ note: ClarificationNoteRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let weight = note.weight {
                Text("w\(weight)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(weight < 100 ? .orange : .secondary)
            }
            Text(note.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: Chips

    // The per-row status glyph moved to `ClarificationQuestionCard` with the
    // question rows themselves — it is the card's own header now.

    /// Renders a colored status chip for the clarification status.
    ///
    /// - Parameter status: The clarification status to display, or nil for unknown.
    /// - Returns: A capsule-shaped status indicator with text and color.
    @ViewBuilder
    private func statusChip(_ status: ClarificationStatus?) -> some View {
        let (label, color): (String, Color) =
            switch status {
            case .building: ("Building", .orange)
            case .answering: ("Answering", .blue)
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
