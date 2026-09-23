import SwiftUI

/// One clarification question: the answering surface, and the only interactive control in the
/// report subsystem.
///
/// `ClarificationRepository.answer()` throws unless the summary is `answering`, so the
/// controls exist only in that state and `building` / `complete` render read-only. The
/// `.disabled` term restating the gate is deliberate belt-and-braces. Save carries one further
/// disable, text and selection both empty, mirroring the daemon's `badRequest`. Every edit is
/// local until Save: each question is its own round trip with its own version cell.
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
    /// answer under a person glyph.
    ///
    /// This is what every non-`answering` state renders, and what the pane
    /// rendered before answering existed.
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

    /// Builds a toggle button for a clarification option.
    /// - Parameter option: The clarification option to toggle.
    /// - Returns: A view containing the option toggle button.
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

    /// Displays a conflict banner for the question.
    ///
    /// Scoped to THIS question — a collision on one question says nothing about
    /// any other, and every other draft on the pane is still live.
    ///
    /// - Parameter message: The error message to display in the banner.
    /// - Returns: A view containing the conflict warning.
    private func conflictBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.leading, 18)
    }

    /// Reads through the model so observation tracks it, writes through
    /// `setText` so the dirty flag and the in-flight lock stay authoritative.
    ///
    /// Falls back to the server row before the first `adopt` lands.
    private var textBinding: Binding<String> {
        Binding(
            get: { answers.draft(for: question.uuid)?.text ?? (question.answerText ?? "") },
            set: { answers.setText($0, for: question.uuid) }
        )
    }

    // MARK: Bits

    /// Renders a status icon for a clarification row.
    /// - Parameter status: The raw status string from the wire.
    /// - Returns: A view displaying the appropriate status icon.
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
