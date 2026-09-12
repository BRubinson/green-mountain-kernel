import SwiftUI
import GMCCDaemonKit

/// One clarification question — Feature 2's answering surface, and the only
/// interactive control in the whole report subsystem.
///
/// ## The gate
///
/// `ClarificationRepository.answer()` throws `invalidEntityTransition` unless
/// the summary is `answering` ("answers are writable only while the summary is
/// answering"). So the controls exist ONLY in that state: `building` and
/// `complete` render today's read-only layout, byte for byte, and there is no
/// disabled-control tease of a write the daemon would refuse. The `.disabled`
/// term restating the gate is deliberate belt-and-braces — the branch already
/// makes it redundant, and it should stay redundant.
///
/// Save carries one ADDITIONAL disable: text and selection both empty, which
/// mirrors the daemon's `badRequest`, so the user never eats a server error for
/// pressing a button the app offered.
///
/// Every edit is local until Save. There is no autosave and no Submit-all —
/// each question is its own round trip with its own version cell, so a
/// collision on one question never touches the drafts of the others.
struct ClarificationQuestionCard: View {
    let question: ClarificationQuestionRow
    /// The summary's status — the gate, passed down rather than re-derived.
    let clarificationStatus: ClarificationStatus?
    /// Owned by `PromptPhaseStore` and reached through `SessionScope`, so the
    /// draft survives pane navigation and every CLARIFY_GET refreshes its
    /// version cell.
    let answers: ClarificationAnswerModel

    private var isAnswering: Bool { clarificationStatus == .answering }

    private var draft: ClarificationAnswerModel.Draft? { answers.draft(for: question.uuid) }

    private var inFlight: Bool { draft?.inFlight ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                rowStatusIcon(question.status)
                Text(question.question)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
            }
            if isAnswering {
                editor
            } else {
                readOnlyAnswer
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Read-only (building / complete)

    /// Today's layout, unchanged: selections as static checkmarks, the typed
    /// answer under a person glyph. This is what every non-`answering` state
    /// renders, and what the pane rendered before answering existed.
    @ViewBuilder
    private var readOnlyAnswer: some View {
        ForEach(question.options, id: \.uuid) { option in
            let selected = question.selectedOptionUuids.contains(option.uuid)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.green : Color.secondary)
                Text(option.body)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, 18)
        }
        if let answer = question.answerText, !answer.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(answer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.leading, 18)
        }
    }

    // MARK: Answering

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(question.options, id: \.uuid) { option in
                optionToggle(option)
            }
            TextField("Type an answer…", text: textBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(2...8)
                .padding(.leading, 18)
            controls
            if let message = draft?.conflict {
                conflictBanner(message)
            }
        }
        // Redundant with the `isAnswering` branch above, and kept that way: the
        // daemon's gate should be visible in the code that writes through it.
        .disabled(!isAnswering || inFlight)
    }

    private func optionToggle(_ option: ClarificationOptionRow) -> some View {
        let selected = draft?.selected.contains(option.uuid) ?? false
        return Button {
            answers.toggle(option: option.uuid, for: question.uuid)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.green : Color.secondary)
                Text(option.body)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            Button("Save") {
                Task { await answers.save(questionUuid: question.uuid) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            // The daemon's badRequest, mirrored client-side.
            .disabled(!answers.canSave(question.uuid))

            Button("Skip") {
                Task { await answers.skip(questionUuid: question.uuid) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if inFlight {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(.leading, 18)
    }

    /// Scoped to THIS question — a collision on one question says nothing about
    /// any other, and every other draft on the pane is still live.
    private func conflictBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.leading, 18)
    }

    /// Reads through the model so observation tracks it, writes through
    /// `setText` so the dirty flag and the in-flight lock stay authoritative.
    /// Falls back to the server row before the first `adopt` lands.
    private var textBinding: Binding<String> {
        Binding(
            get: { answers.draft(for: question.uuid)?.text ?? (question.answerText ?? "") },
            set: { answers.setText($0, for: question.uuid) }
        )
    }

    // MARK: Bits

    @ViewBuilder
    private func rowStatusIcon(_ status: String) -> some View {
        switch ClarificationRowStatus(rawValue: status) {
        case .answered:
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").font(.caption).foregroundStyle(.secondary)
        default:
            Image(systemName: "circle").font(.caption).foregroundStyle(.orange)
        }
    }
}
