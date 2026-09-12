import SwiftUI
import GMCCDaemonKit

/// The app's render of the db-native clarification (CLARIFY_GET, m0025 split):
/// user questions with option/selection children, weighted internal notes, and
/// the care package (the standalone clarified-intent bundle).
///
/// ANSWERING is the one write door here, and the app's only report-subsystem
/// write at all: while the summary is `answering`, each question card can
/// select options / type an answer / skip through CLARIFY_ANSWER. Everything
/// else — the care package, the notes, the summary's own status — stays
/// bot/CLI-side, and nothing on this pane ever writes prompt content.
///
/// ONE data path: the pane holds the whole `ClarifyGetResponse`, so neither the
/// expanded care package nor the answering cards introduce a second fetch.
struct ClarificationPane: View {
    let phase: PromptPhaseStore.Phase<ClarifyGetResponse>
    /// Held ONLY so the question cards can reach `phases.answers` — the
    /// per-question draft/version cells every CLARIFY_GET reconciles. The pane
    /// itself issues nothing through it.
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
            Label("Not opened yet — run the bot to start clarification.",
                  systemImage: "questionmark.circle")
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
                CarePackageSection(package: package,
                                   staleness: response.carePackageStaleness)
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
                            answers: phases.answers)
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

    @ViewBuilder
    private func statusChip(_ status: ClarificationStatus?) -> some View {
        let (label, color): (String, Color) = switch status {
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
