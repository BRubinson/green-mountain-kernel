import Foundation
import Observation
import GMCCDaemonKit

/// Feature 2's write path: per-question answer drafts over CLARIFY_ANSWER —
/// the ONLY report-subsystem write the app performs, and the only place in
/// this prompt where a bug destroys user data.
///
/// ## The wholesale-replace trap
///
/// `ClarificationRepository.answer()` DELETEs every `user_clarification_answer`
/// row for the question and rewrites `answer_text` WHOLESALE on every non-skip
/// call. Sending only the axis the user just touched therefore *destroys the
/// other one*: toggling a checkbox with `answerText: nil` wipes typed text, and
/// saving text with `selectedOptionUuids: nil` wipes every selection. So
/// `save()` ALWAYS sends BOTH axes in full — including an EMPTY selection array,
/// which is a real value ("nothing selected"), never an omission. `skip()` sends
/// `skip: true`, which is the daemon's symmetric clear of both axes.
///
/// ## Versioning
///
/// `expectedVersion` targets the QUESTION row, never the summary — so version
/// cells are tracked per question uuid and a conflict banners on that one
/// question while every other draft survives untouched. On success the returned
/// row's version is adopted IMMEDIATELY rather than waiting for the
/// CLARIFICATION_CHANGE round trip, so two quick saves in a row both succeed.
///
/// This is a DELIBERATE divergence from `PromptSaveActor`, whose
/// one-version-per-prompt shape cannot express per-question concurrency. Its
/// vocabulary (saved / conflict / locked / failed) is borrowed; the component
/// is not reused.
///
/// ## Deliberately NOT an actor
///
/// There is no debounce and no autosave — an explicit per-question Save is the
/// settled rhythm — and the daemon already serializes writes on one queue, so
/// actor isolation would buy nothing while costing a hop off the main actor for
/// state SwiftUI must read SYNCHRONOUSLY during `body`. Turning this into an
/// actor would deadlock the bindings; leave it `@MainActor @Observable`.
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
        /// Banners on THIS question only. Carries the version-conflict message
        /// and any other per-question write failure (an illegal transition, a
        /// transport error) — never a whole-pane banner, because a collision on
        /// one question says nothing about the others.
        var conflict: String?
    }

    /// Keyed by question uuid.
    private(set) var drafts: [String: Draft] = [:]

    /// Pull fresh question rows after a failed write. Wired by the owning
    /// `PromptPhaseStore` (the only thing that can issue CLARIFY_GET); a
    /// conflict is otherwise unrecoverable, because the user would keep
    /// re-sending the same stale expected version.
    var onNeedsRefresh: (@MainActor () async -> Void)?

    /// The ONE daemon call this model makes, behind a replaceable closure so
    /// `ClarificationAnswerModelTests` can assert the request SHAPE — both axes,
    /// always, in full — without a live socket. Production never reassigns it;
    /// this is a test seam, not a dependency-injection point, and nothing else
    /// about the model's shape changed to accommodate it.
    @ObservationIgnored
    var send: (ClarifyAnswerRequest) async throws -> ClarificationQuestionRow = {
        try await GMCCDaemonService.shared.clarifyAnswer($0)
    }

    // MARK: - Reads

    func draft(for questionUuid: String) -> Draft? { drafts[questionUuid] }

    /// Mirrors the daemon's `badRequest` guard exactly (it trims the text and
    /// treats empty as absent), so the user never eats a server error for
    /// pressing Save on an empty answer.
    ///
    /// `dirty` is part of the gate, not a nicety. `StoreCore.updateBase` bumps
    /// `version = version + 1` on EVERY successful update, so a Save with no
    /// pending edit is not a harmless no-op: it burns a version on the question
    /// row and widens the VERSION_CONFLICT window that the whole per-question
    /// version design exists to narrow. `applyServerRow` clears `dirty` the
    /// moment a write lands, so the gate reopens on the next real edit.
    func canSave(_ questionUuid: String) -> Bool {
        guard let draft = drafts[questionUuid], !draft.inFlight, draft.dirty else { return false }
        return !trimmed(draft.text).isEmpty || !draft.selected.isEmpty
    }

    // MARK: - Reconciliation

    /// Reconcile against every CLARIFY_GET and every event-triggered refetch.
    ///
    /// The server version ALWAYS wins — that is what makes the next Save legal
    /// after someone else (a bot run, the CLI, another window) touched the row.
    /// A dirty draft keeps the user's text and selection while adopting the new
    /// version cell; a clean draft simply mirrors the server. A conflict banner
    /// survives the refresh it triggered (otherwise it would flash and vanish
    /// before the user could read it) but is dropped once the draft is clean,
    /// where it no longer describes anything.
    ///
    /// Drafts for questions that are no longer served are dropped: a question
    /// that does not exist cannot be answered.
    func adopt(_ questions: [ClarificationQuestionRow]) {
        var next: [String: Draft] = [:]
        for question in questions {
            let serverText = question.answerText ?? ""
            let serverSelection = Set(question.selectedOptionUuids)
            guard var draft = drafts[question.uuid] else {
                next[question.uuid] = Draft(
                    text: serverText, selected: serverSelection, version: question.version,
                    dirty: false, inFlight: false, conflict: nil)
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

    func setText(_ text: String, for questionUuid: String) {
        guard var draft = drafts[questionUuid], !draft.inFlight, draft.text != text else { return }
        draft.text = text
        draft.dirty = true
        drafts[questionUuid] = draft
    }

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

    /// One round trip, both axes, full. See the type doc for why "full" is not
    /// optional here.
    func save(questionUuid: String) async {
        guard let draft = drafts[questionUuid], !draft.inFlight else { return }
        let text = trimmed(draft.text)
        // The daemon rejects an answer with neither axis; the UI disables Save
        // in that state, so reaching here means a race — decline silently
        // rather than banner a server error the user cannot act on.
        guard !text.isEmpty || !draft.selected.isEmpty else { return }
        await perform(questionUuid: questionUuid, request: ClarifyAnswerRequest(
            questionUuid: questionUuid,
            expectedVersion: draft.version,
            answerText: text.isEmpty ? nil : text,
            // ALWAYS sent, even when empty: an empty array is the real value
            // "no options selected", and omitting it would leave the daemon's
            // wholesale rewrite to decide — which it does by clearing anyway.
            selectedOptionUuids: Array(draft.selected),
            skip: false))
    }

    /// `skip: true` clears BOTH axes daemon-side; adopting the returned row
    /// clears them locally, so the two can never disagree.
    func skip(questionUuid: String) async {
        guard let draft = drafts[questionUuid], !draft.inFlight else { return }
        await perform(questionUuid: questionUuid, request: ClarifyAnswerRequest(
            questionUuid: questionUuid,
            expectedVersion: draft.version,
            answerText: nil,
            selectedOptionUuids: nil,
            skip: true))
    }

    private func perform(questionUuid: String, request: ClarifyAnswerRequest) async {
        setInFlight(true, for: questionUuid)
        do {
            let row = try await send(request)
            // Adopt the returned version IMMEDIATELY — waiting for the
            // CLARIFICATION_CHANGE round trip would make a second quick save
            // conflict against a version we already hold.
            applyServerRow(row)
        } catch DaemonError.versionConflict {
            finish(questionUuid, conflict:
                "Answered elsewhere while you were editing. Your text was kept and the "
                + "question refreshed — review it, then save again.")
            // Without this the user would keep re-sending the same stale
            // expected version and conflict forever.
            await onNeedsRefresh?()
        } catch DaemonError.invalidTransition(let reason) {
            // The summary left `answering` under us (a bot sealed it). The UI
            // gate closes on the next refresh; say why in the meantime.
            finish(questionUuid, conflict: reason
                ?? "Clarification is no longer accepting answers.")
            await onNeedsRefresh?()
        } catch let error as DaemonError {
            finish(questionUuid, conflict: error.userMessage)
        } catch {
            finish(questionUuid, conflict: String(describing: error))
        }
    }

    // MARK: - Draft bookkeeping

    private func applyServerRow(_ row: ClarificationQuestionRow) {
        var draft = drafts[row.uuid] ?? Draft(
            text: "", selected: [], version: row.version,
            dirty: false, inFlight: false, conflict: nil)
        draft.version = row.version
        draft.text = row.answerText ?? ""
        draft.selected = Set(row.selectedOptionUuids)
        draft.dirty = false
        draft.inFlight = false
        draft.conflict = nil
        drafts[row.uuid] = draft
    }

    private func setInFlight(_ value: Bool, for questionUuid: String) {
        guard var draft = drafts[questionUuid] else { return }
        draft.inFlight = value
        drafts[questionUuid] = draft
    }

    /// Settle the draft BEFORE any refresh is kicked off, so the `adopt` that
    /// refresh triggers sees a quiesced row rather than one still marked
    /// in-flight.
    private func finish(_ questionUuid: String, conflict: String?) {
        guard var draft = drafts[questionUuid] else { return }
        draft.inFlight = false
        draft.conflict = conflict
        drafts[questionUuid] = draft
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
