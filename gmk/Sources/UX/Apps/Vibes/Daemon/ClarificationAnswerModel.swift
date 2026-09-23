import Foundation
import Observation

/// Per-question answer drafts over CLARIFY_ANSWER, the app's only clarification write.
///
/// `ClarificationRepository.answer()` rewrites both axes wholesale, so `save()` always sends
/// text AND selection in full; an empty selection array is a real value, never an omission.
/// `expectedVersion` targets the QUESTION row, so a conflict banners on that one question.
/// Stays `@MainActor @Observable`: SwiftUI reads this state synchronously during `body`.
@MainActor
@Observable
final class ClarificationAnswerModel {
    /// One question's local edit state. `version` is the QUESTION row's
    /// version — NOT the summary's.
    struct Draft: Equatable {
        var text: String
        var selected: Set<String>
        var version: Int64
        /// The user has edits the server has not accepted yet.
        var dirty: Bool
        /// A save/skip round trip is open; controls are locked for the duration.
        var inFlight: Bool
        /// Banners on THIS question only.
        ///
        /// Carries the version-conflict message and any other per-question write failure (an
        /// illegal transition, a transport error) — never a whole-pane banner, because a
        /// collision on one question says nothing about the others.
        var conflict: String?
    }

    /// Keyed by question uuid.
    private(set) var drafts: [String: Draft] = [:]

    /// Pull fresh question rows after a failed write.
    ///
    /// Wired by the owning `PromptPhaseStore` (the only thing that can issue CLARIFY_GET); a
    /// conflict is otherwise unrecoverable, because the user would keep re-sending the same
    /// stale expected version.
    var onNeedsRefresh: (@MainActor () async -> Void)?

    /// The one daemon call this model makes, behind a closure so a test can assert the
    /// request shape without a live socket.
    ///
    /// Production never reassigns it.
    @ObservationIgnored
    var send: @MainActor (ClarifyAnswerRequest) async throws -> ClarificationQuestionRow = {
        try await GMCCDaemonService.shared.clarifyAnswer($0)
    }

    // MARK: - Reads

    /// Returns the draft state for a question.
    ///
    /// - Parameter questionUuid: The question UUID.
    /// - Returns: The draft state, or `nil` if the question is not yet loaded.
    func draft(for questionUuid: String) -> Draft? { drafts[questionUuid] }

    /// Returns whether a question can be saved without wasting a version.
    ///
    /// Mirrors the daemon's `badRequest` guard. `dirty` is part of the gate:
    /// `StoreCore.updateBase` bumps the version on every successful update, so a Save
    /// with no pending edit burns a question-row version and widens the VERSION_CONFLICT
    /// window. No save is allowed while a request is in flight.
    ///
    /// - Parameter questionUuid: The question UUID.
    /// - Returns: `true` if the question has pending edits and no request is in flight.
    func canSave(_ questionUuid: String) -> Bool {
        guard let draft = drafts[questionUuid], !draft.inFlight, draft.dirty else { return false }
        return !trimmed(draft.text).isEmpty || !draft.selected.isEmpty
    }

    // MARK: - Reconciliation

    /// Reconciles drafts against fresh server state.
    ///
    /// The server version always wins, which is what makes the next Save legal after another
    /// writer touched the row. A dirty draft keeps the user's text and selection while adopting
    /// the new version. A conflict banner survives the refresh it triggered so the user can
    /// read it. Drafts for questions the server stopped serving are dropped.
    ///
    /// - Parameter questions: Fresh question rows from the server.
    func adopt(_ questions: [ClarificationQuestionRow]) {
        var next: [String: Draft] = [:]
        for question in questions {
            let serverText = question.answerText ?? ""
            let serverSelection = Set(question.selectedOptionUuids)
            guard var draft = drafts[question.uuid] else {
                next[question.uuid] = Draft(
                    text: serverText,
                    selected: serverSelection,
                    version: question.version,
                    dirty: false,
                    inFlight: false,
                    conflict: nil
                )
                continue
            }
            draft.version = question.version
            if !draft.dirty {
                draft.text = serverText
                draft.selected = serverSelection
                draft.conflict = nil
            }
            next[question.uuid] = draft
        }
        if drafts != next { drafts = next }
    }

    // MARK: - Local edits

    /// Updates the text answer for a question and marks it as dirty.
    ///
    /// Does nothing if the draft does not exist, a request is in flight, or the
    /// text has not changed.
    ///
    /// - Parameters:
    ///   - text: The new answer text.
    ///   - questionUuid: The question UUID.
    func setText(_ text: String, for questionUuid: String) {
        guard var draft = drafts[questionUuid], !draft.inFlight, draft.text != text else { return }
        draft.text = text
        draft.dirty = true
        drafts[questionUuid] = draft
    }

    /// Toggles an option's selection for a question and marks it as dirty.
    ///
    /// Does nothing if the draft does not exist or a request is in flight.
    ///
    /// - Parameters:
    ///   - optionUuid: The option UUID to toggle.
    ///   - questionUuid: The question UUID.
    func toggle(option optionUuid: String, for questionUuid: String) {
        guard var draft = drafts[questionUuid], !draft.inFlight else { return }
        if draft.selected.contains(optionUuid) {
            draft.selected.remove(optionUuid)
        } else {
            draft.selected.insert(optionUuid)
        }
        draft.dirty = true
        drafts[questionUuid] = draft
    }

    // MARK: - Writes

    /// Sends both answer axes (text and selection) in one request.
    ///
    /// See the type documentation for why full transmission is not optional.
    /// Does nothing if the draft does not exist or a request is already in flight.
    ///
    /// - Parameter questionUuid: The question UUID to save.
    func save(questionUuid: String) async {
        guard let draft = drafts[questionUuid], !draft.inFlight else { return }
        let text = trimmed(draft.text)
        // The daemon rejects an answer with neither axis; the UI disables Save
        // in that state, so reaching here means a race — decline silently
        // rather than banner a server error the user cannot act on.
        guard !text.isEmpty || !draft.selected.isEmpty else { return }
        await perform(
            questionUuid: questionUuid,
            request: ClarifyAnswerRequest(
                questionUuid: questionUuid,
                expectedVersion: draft.version,
                answerText: text.isEmpty ? nil : text,
                // ALWAYS sent, even when empty: an empty array is the real value
                // "no options selected", and omitting it would leave the daemon's
                // wholesale rewrite to decide — which it does by clearing anyway.
                selectedOptionUuids: Array(draft.selected),
                skip: false
            )
        )
    }

    /// Skips a question by sending both axes as empty.
    ///
    /// Setting `skip: true` clears both axes daemon-side. Adopting the returned row
    /// clears them locally, so the two can never disagree. Does nothing if the draft does
    /// not exist or a request is already in flight.
    ///
    /// - Parameter questionUuid: The question UUID to skip.
    func skip(questionUuid: String) async {
        guard let draft = drafts[questionUuid], !draft.inFlight else { return }
        await perform(
            questionUuid: questionUuid,
            request: ClarifyAnswerRequest(
                questionUuid: questionUuid,
                expectedVersion: draft.version,
                answerText: nil,
                selectedOptionUuids: nil,
                skip: true
            )
        )
    }

    /// Sends a request and handles the response or error.
    ///
    /// Adopts the returned version immediately to allow the next save. On version conflict,
    /// fetches fresh state. On invalid transition, reports the reason. Other errors are
    /// reported as strings.
    ///
    /// - Parameters:
    ///   - questionUuid: The question UUID.
    ///   - request: The request to send.
    private func perform(questionUuid: String, request: ClarifyAnswerRequest) async {
        setInFlight(true, for: questionUuid)
        do {
            let row = try await send(request)
            // Adopt the returned version IMMEDIATELY — waiting for the
            // CLARIFICATION_CHANGE round trip would make a second quick save
            // conflict against a version we already hold.
            applyServerRow(row)
        } catch DaemonError.versionConflict {
            finish(
                questionUuid,
                conflict:
                    "Answered elsewhere while you were editing. Your text was kept and the "
                    + "question refreshed — review it, then save again."
            )
            // Without this the user would keep re-sending the same stale
            // expected version and conflict forever.
            await onNeedsRefresh?()
        } catch DaemonError.invalidTransition(let reason) {
            // The summary left `answering` under us (a bot sealed it). The UI
            // gate closes on the next refresh; say why in the meantime.
            finish(
                questionUuid,
                conflict: reason
                    ?? "Clarification is no longer accepting answers."
            )
            await onNeedsRefresh?()
        } catch let error as DaemonError {
            finish(questionUuid, conflict: error.userMessage)
        } catch {
            finish(questionUuid, conflict: String(describing: error))
        }
    }

    // MARK: - Draft bookkeeping

    /// Updates draft state from a server row, clearing all dirty and error flags.
    ///
    /// Creates a new draft if one does not exist. Preserves only version and content.
    ///
    /// - Parameter row: The server question row.
    private func applyServerRow(_ row: ClarificationQuestionRow) {
        var draft =
            drafts[row.uuid]
            ?? Draft(
                text: "",
                selected: [],
                version: row.version,
                dirty: false,
                inFlight: false,
                conflict: nil
            )
        draft.version = row.version
        draft.text = row.answerText ?? ""
        draft.selected = Set(row.selectedOptionUuids)
        draft.dirty = false
        draft.inFlight = false
        draft.conflict = nil
        drafts[row.uuid] = draft
    }

    /// Updates the in-flight state of a draft.
    ///
    /// Does nothing if the draft does not exist.
    ///
    /// - Parameters:
    ///   - value: Whether a request is in flight.
    ///   - questionUuid: The question UUID.
    private func setInFlight(_ value: Bool, for questionUuid: String) {
        guard var draft = drafts[questionUuid] else { return }
        draft.inFlight = value
        drafts[questionUuid] = draft
    }

    /// Settles a draft after a request completes or fails.
    ///
    /// Clears the in-flight flag before any refresh is triggered, so the `adopt` call
    /// that refresh runs sees a quiesced row. Stores the error message if provided.
    ///
    /// - Parameters:
    ///   - questionUuid: The question UUID.
    ///   - conflict: An error message, or `nil` if the request succeeded.
    private func finish(_ questionUuid: String, conflict: String?) {
        guard var draft = drafts[questionUuid] else { return }
        draft.inFlight = false
        draft.conflict = conflict
        drafts[questionUuid] = draft
    }

    /// Returns text with leading and trailing whitespace and newlines removed.
    ///
    /// - Parameter text: The text to trim.
    /// - Returns: Trimmed text.
    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
