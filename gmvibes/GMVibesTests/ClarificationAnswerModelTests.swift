import Testing
import GMCCDaemonKit
@testable import GMVibes

/// `ClarificationAnswerModel` is the app's ONLY report-subsystem write, and the
/// one place in GMVibes where a bug destroys work the user typed. These tests
/// exist to pin the two properties its own type doc warns about, both of which
/// a well-meaning "simplification" would quietly delete:
///
/// 1. **Both axes, always, in full.** `ClarificationRepository.answer()` DELETEs
///    every `user_clarification_answer` row and rewrites `answer_text` WHOLESALE
///    on each non-skip call. A future per-axis save ("only send what changed")
///    would therefore wipe the untouched axis. The shape assertions below fail
///    loudly the moment a request omits one — including the `[]` case, which is
///    the real value "nothing selected" and must never degrade to `nil`.
/// 2. **One version cell per QUESTION.** A conflict must banner on that question
///    and leave every other draft on the pane untouched.
///
/// The daemon call is exercised through `model.send`, the model's test seam.
@MainActor
struct ClarificationAnswerModelTests {

    // MARK: - Fixtures

    private static func options(_ uuids: [String]) -> [ClarificationOptionRow] {
        uuids.enumerated().map {
            ClarificationOptionRow(uuid: $0.element, seq: Int64($0.offset), body: "body of \($0.element)")
        }
    }

    private static func question(
        _ uuid: String = "q-1",
        version: Int64 = 1,
        answerText: String? = nil,
        selected: [String] = [],
        options optionUuids: [String] = ["opt-a", "opt-b", "opt-c"]
    ) -> ClarificationQuestionRow {
        ClarificationQuestionRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: "clar-1",
            seq: 1,
            question: "Which way?",
            status: answerText == nil && selected.isEmpty ? "open" : "answered",
            answerText: answerText,
            agentId: nil,
            agentName: nil,
            options: options(optionUuids),
            selectedOptionUuids: selected)
    }

    /// model + attached transport, the shape every test starts from.
    /// `transport` defaults to the echoing double; it is `nil`-defaulted rather
    /// than `= .echoing()` because a default argument is evaluated in a
    /// nonisolated context and `Transport` is main-actor isolated.
    private static func seeded(
        _ questions: [ClarificationQuestionRow],
        transport: Transport? = nil
    ) -> (ClarificationAnswerModel, Transport) {
        let transport = transport ?? Transport.echoing()
        let model = ClarificationAnswerModel()
        transport.attach(to: model)
        model.adopt(questions)
        return (model, transport)
    }

    // MARK: - The wholesale-replace trap: save() sends BOTH axes, in full

    @Test func saveSendsTheFullTextAndTheFullSelectionSet() async throws {
        let (model, transport) = Self.seeded(
            [Self.question(answerText: "seeded", selected: ["opt-a"], options: ["opt-a", "opt-b", "opt-c"])])
        model.setText("seeded, edited", for: "q-1")
        model.toggle(option: "opt-b", for: "q-1")

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(transport.requests.count == 1)
        #expect(request.questionUuid == "q-1")
        // Targets the QUESTION row's version, never the summary's.
        #expect(request.expectedVersion == 1)
        #expect(request.answerText == "seeded, edited")
        #expect(Set(try #require(request.selectedOptionUuids)) == ["opt-a", "opt-b"])
        #expect(request.skip == false)
    }

    @Test func aClearedSelectionTravelsAsAnEmptyArrayNotAsNil() async throws {
        // The regression this whole file exists for: `nil` means "the daemon
        // decides", `[]` means "the user selected nothing". They must not be
        // confused, even though the daemon's wholesale rewrite clears either way.
        let (model, transport) = Self.seeded([Self.question(answerText: "prose", selected: ["opt-a"])])
        model.toggle(option: "opt-a", for: "q-1")   // clears the only selection

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(request.selectedOptionUuids != nil)
        #expect(request.selectedOptionUuids == [])
        #expect(request.answerText == "prose")      // the untouched axis survives
    }

    @Test func aTextOnlyAnswerStillCarriesTheEmptySelectionAxis() async throws {
        let (model, transport) = Self.seeded([Self.question()])
        model.setText("typed, nothing ticked", for: "q-1")

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(request.answerText == "typed, nothing ticked")
        #expect(request.selectedOptionUuids == [])
    }

    @Test func togglingAnOptionPreservesTypedTextThroughTheSave() async throws {
        let (model, transport) = Self.seeded([Self.question()])
        model.setText("my typed answer", for: "q-1")
        model.toggle(option: "opt-c", for: "q-1")   // last touch is the SELECTION axis

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(request.answerText == "my typed answer")   // not wiped by the toggle
        #expect(request.selectedOptionUuids == ["opt-c"])
        #expect(model.draft(for: "q-1")?.text == "my typed answer")
    }

    @Test func editingTextPreservesExistingSelectionsThroughTheSave() async throws {
        let (model, transport) = Self.seeded([Self.question(selected: ["opt-a", "opt-c"])])
        model.setText("now with prose", for: "q-1")     // last touch is the TEXT axis

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(Set(try #require(request.selectedOptionUuids)) == ["opt-a", "opt-c"])  // not wiped
        #expect(request.answerText == "now with prose")
    }

    @Test func whitespaceOnlyTextIsSentAsAbsentWhileTheSelectionStillTravels() async throws {
        // Mirrors the daemon's badRequest guard: it trims and treats empty as
        // absent, so the client must not ship "   " as a real answer.
        let (model, transport) = Self.seeded([Self.question(selected: ["opt-b"])])
        model.setText("   \n ", for: "q-1")

        await model.save(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(request.answerText == nil)
        #expect(request.selectedOptionUuids == ["opt-b"])
    }

    @Test func saveDeclinesSilentlyWhenNeitherAxisHasContent() async {
        let (model, transport) = Self.seeded([Self.question()])
        model.setText("  ", for: "q-1")

        await model.save(questionUuid: "q-1")

        #expect(transport.requests.isEmpty)             // no server error to eat
        #expect(model.draft(for: "q-1")?.conflict == nil)
    }

    // MARK: - skip()

    @Test func skipSendsSkipTrueAndClearsBothAxesLocally() async throws {
        let (model, transport) = Self.seeded(
            [Self.question(version: 4, answerText: "typed", selected: ["opt-a"])])
        model.setText("typed more", for: "q-1")

        await model.skip(questionUuid: "q-1")

        let request = try #require(transport.last)
        #expect(request.skip == true)
        #expect(request.answerText == nil)              // skip is the daemon's symmetric clear
        #expect(request.selectedOptionUuids == nil)
        #expect(request.expectedVersion == 4)

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.text.isEmpty)
        #expect(draft.selected.isEmpty)
        #expect(draft.version == 5)
        #expect(draft.dirty == false)
        #expect(draft.inFlight == false)
        #expect(draft.conflict == nil)
    }

    // MARK: - A successful write settles the draft

    @Test func aSuccessfulSaveClearsInFlightDirtyAndConflict() async throws {
        let (model, _) = Self.seeded([Self.question(version: 6)], transport: .failing(.versionConflict))
        model.setText("first try", for: "q-1")
        await model.save(questionUuid: "q-1")
        #expect(model.draft(for: "q-1")?.conflict != nil)
        #expect(model.draft(for: "q-1")?.dirty == true)

        // Same model, a transport that now succeeds.
        let ok = Transport.echoing()
        ok.attach(to: model)
        await model.save(questionUuid: "q-1")

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.inFlight == false)
        #expect(draft.dirty == false)
        #expect(draft.conflict == nil)
        #expect(draft.text == "first try")
        #expect(draft.version == 7)                     // adopted from the returned row
        #expect(ok.requests.count == 1)
    }

    @Test func twoQuickSavesUseTheAdoptedVersionNotTheStaleOne() async throws {
        // Why applyServerRow adopts immediately instead of waiting for the
        // CLARIFICATION_CHANGE round trip.
        let (model, transport) = Self.seeded([Self.question(version: 7)])
        model.setText("one", for: "q-1")
        await model.save(questionUuid: "q-1")
        model.setText("two", for: "q-1")
        await model.save(questionUuid: "q-1")

        #expect(transport.requests.map(\.expectedVersion) == [7, 8])
        #expect(model.draft(for: "q-1")?.version == 9)
    }

    // MARK: - canSave gates on a PENDING edit

    @Test func canSaveIsShutOnACleanDraftAndReopensOnlyOnAnEdit() async {
        // Regression for the no-op Save: StoreCore.updateBase bumps
        // `version = version + 1` on EVERY successful update, so a Save with
        // nothing pending burns a version on the question row and widens the
        // VERSION_CONFLICT window the per-question design exists to narrow.
        let (model, _) = Self.seeded([Self.question(answerText: "already answered", selected: ["opt-a"])])
        #expect(model.canSave("q-1") == false)          // clean, even though both axes have content

        model.setText("edited", for: "q-1")
        #expect(model.canSave("q-1") == true)

        await model.save(questionUuid: "q-1")
        // The gate must re-close, and must NOT wedge shut: dirty is cleared by
        // applyServerRow, so the next real edit reopens it.
        #expect(model.canSave("q-1") == false)
        model.setText("edited again", for: "q-1")
        #expect(model.canSave("q-1") == true)
    }

    @Test func canSaveIsShutWithNoContentOnEitherAxis() {
        let (model, _) = Self.seeded([Self.question()])
        #expect(model.canSave("q-1") == false)          // untouched
        model.setText("   ", for: "q-1")
        #expect(model.canSave("q-1") == false)          // dirty but trimmed-empty, nothing ticked
        model.toggle(option: "opt-a", for: "q-1")
        #expect(model.canSave("q-1") == true)           // a selection alone is a real answer
    }

    @Test func canSaveIsShutForAnUnknownQuestionAndWhileTheWriteIsInFlight() async {
        let model = ClarificationAnswerModel()
        let probe = Probe()
        let transport = Transport { [unowned model] request in
            probe.canSaveMidFlight = model.canSave("q-1")
            probe.inFlightMidFlight = model.draft(for: "q-1")?.inFlight
            return Self.question(version: request.expectedVersion + 1, answerText: request.answerText)
        }
        transport.attach(to: model)
        #expect(model.canSave("q-1") == false)          // no draft at all

        model.adopt([Self.question()])
        model.setText("in flight please", for: "q-1")
        await model.save(questionUuid: "q-1")

        #expect(probe.inFlightMidFlight == true)
        #expect(probe.canSaveMidFlight == false)        // controls locked for the round trip
    }

    // MARK: - adopt(): the server version always wins

    @Test func adoptSeedsCleanDraftsStraightFromTheServer() throws {
        let (model, _) = Self.seeded([Self.question(version: 3, answerText: "from the bot", selected: ["opt-b"])])
        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.text == "from the bot")
        #expect(draft.selected == ["opt-b"])
        #expect(draft.version == 3)
        #expect(draft.dirty == false)
        #expect(draft.conflict == nil)
    }

    @Test func adoptGivesADirtyDraftTheNewVersionButKeepsTheUsersEdits() throws {
        let (model, _) = Self.seeded([Self.question(version: 3, answerText: "from the bot")])
        model.setText("mine, unsaved", for: "q-1")
        model.toggle(option: "opt-c", for: "q-1")

        // Someone else touched the row: new version, different server content.
        model.adopt([Self.question(version: 9, answerText: "theirs", selected: ["opt-a"])])

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.version == 9)                     // server version ALWAYS wins
        #expect(draft.text == "mine, unsaved")          // the user's work is NOT clobbered
        #expect(draft.selected == ["opt-c"])
        #expect(draft.dirty == true)
    }

    @Test func adoptOverwritesACleanDraftWithServerContent() throws {
        let (model, _) = Self.seeded([Self.question(version: 3, answerText: "from the bot")])
        model.adopt([Self.question(version: 4, answerText: "rewritten by the bot", selected: ["opt-a"])])

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.text == "rewritten by the bot")
        #expect(draft.selected == ["opt-a"])
        #expect(draft.version == 4)
    }

    @Test func adoptDropsDraftsForQuestionsTheServerNoLongerServes() {
        let (model, _) = Self.seeded([Self.question("q-1"), Self.question("q-2")])
        model.setText("typed into a doomed question", for: "q-2")

        model.adopt([Self.question("q-1", version: 2)])

        #expect(model.draft(for: "q-1") != nil)
        #expect(model.draft(for: "q-2") == nil)         // it cannot be answered any more
    }

    // MARK: - Conflicts banner ONE question

    @Test func versionConflictBannersOneQuestionAndRefreshesExactlyOnce() async throws {
        let (model, transport) = Self.seeded(
            [Self.question("q-1", version: 2),
             Self.question("q-2", version: 9, answerText: "untouched neighbour", selected: ["opt-b"])],
            transport: .failing(.versionConflict))
        let refreshes = Probe()
        model.onNeedsRefresh = { refreshes.refreshCount += 1 }
        model.setText("mine", for: "q-1")

        await model.save(questionUuid: "q-1")

        #expect(transport.requests.count == 1)
        #expect(refreshes.refreshCount == 1)            // exactly one, not zero and not per-retry

        let conflicted = try #require(model.draft(for: "q-1"))
        #expect(conflicted.conflict != nil)
        #expect(conflicted.inFlight == false)           // settled BEFORE the refresh fires
        #expect(conflicted.dirty == true)               // the user's text is kept for the retry
        #expect(conflicted.text == "mine")

        let neighbour = try #require(model.draft(for: "q-2"))
        #expect(neighbour.conflict == nil)              // a collision here says nothing about there
        #expect(neighbour.text == "untouched neighbour")
        #expect(neighbour.selected == ["opt-b"])
        #expect(neighbour.version == 9)
    }

    @Test func theConflictBannerSurvivesTheRefreshItTriggered() async throws {
        let (model, _) = Self.seeded([Self.question(version: 2)], transport: .failing(.versionConflict))
        model.setText("mine", for: "q-1")
        await model.save(questionUuid: "q-1")

        // The refresh the conflict kicked off delivers the newer row.
        model.adopt([Self.question(version: 3, answerText: "whoever won the race")])

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.conflict != nil)                  // must not flash and vanish unread
        #expect(draft.text == "mine")
        #expect(draft.version == 3)                     // the retry will target the CURRENT version
        #expect(model.canSave("q-1") == true)
    }

    @Test func anInvalidTransitionBannersTheDaemonsReasonAndClearsOnceClean() async throws {
        let reason = "clarification is no longer accepting answers"
        let (model, _) = Self.seeded(
            [Self.question(version: 1)],
            transport: .failing(.invalidTransition(reason: reason)))
        let refreshes = Probe()
        model.onNeedsRefresh = { refreshes.refreshCount += 1 }

        await model.skip(questionUuid: "q-1")           // legal on a clean draft

        let banner = try #require(model.draft(for: "q-1"))
        #expect(banner.conflict == reason)
        #expect(banner.inFlight == false)
        #expect(banner.dirty == false)
        #expect(refreshes.refreshCount == 1)

        // A clean draft's banner no longer describes anything, so it goes.
        model.adopt([Self.question(version: 2)])
        #expect(model.draft(for: "q-1")?.conflict == nil)
        #expect(model.draft(for: "q-1")?.version == 2)
    }

    @Test func anyOtherDaemonErrorBannersItsUserMessageWithoutARefresh() async throws {
        let (model, _) = Self.seeded(
            [Self.question()],
            transport: .failing(.server(code: "DB_ERROR", message: "disk is on fire")))
        let refreshes = Probe()
        model.onNeedsRefresh = { refreshes.refreshCount += 1 }
        model.setText("mine", for: "q-1")

        await model.save(questionUuid: "q-1")

        let draft = try #require(model.draft(for: "q-1"))
        #expect(draft.conflict == DaemonError.server(code: "DB_ERROR", message: "disk is on fire").userMessage)
        #expect(draft.inFlight == false)
        #expect(draft.dirty == true)                    // still retryable
        #expect(refreshes.refreshCount == 0)            // nothing stale to re-pull
    }
}

// MARK: - Test doubles

/// Mutable scratch shared with an escaping callback, so counters survive the
/// `await` without capturing a local `var`.
@MainActor
private final class Probe {
    var refreshCount = 0
    var canSaveMidFlight: Bool?
    var inFlightMidFlight: Bool?
}

/// Stands in for `GMCCDaemonService.clarifyAnswer`, recording every request so
/// the tests can assert its SHAPE — which is the whole point of this file.
@MainActor
private final class Transport {
    private(set) var requests: [ClarifyAnswerRequest] = []
    private let handler: (ClarifyAnswerRequest) throws -> ClarificationQuestionRow

    init(_ handler: @escaping (ClarifyAnswerRequest) throws -> ClarificationQuestionRow) {
        self.handler = handler
    }

    var last: ClarifyAnswerRequest? { requests.last }

    func attach(to model: ClarificationAnswerModel) {
        model.send = { [self] request in
            requests.append(request)
            return try handler(request)
        }
    }

    /// The daemon's real success shape: the row echoed back with the version
    /// bumped, which is exactly what `applyServerRow` adopts.
    static func echoing() -> Transport {
        Transport { request in
            ClarificationQuestionRow(
                uuid: request.questionUuid,
                version: request.expectedVersion + 1,
                clarificationSummaryUuid: "clar-1",
                seq: 1,
                question: "Which way?",
                status: request.skip ? "skipped" : "answered",
                answerText: request.skip ? nil : request.answerText,
                agentId: nil,
                agentName: nil,
                options: ["opt-a", "opt-b", "opt-c"].enumerated().map {
                    ClarificationOptionRow(uuid: $0.element, seq: Int64($0.offset), body: "body of \($0.element)")
                },
                selectedOptionUuids: request.skip ? [] : (request.selectedOptionUuids ?? []))
        }
    }

    static func failing(_ error: DaemonError) -> Transport {
        Transport { _ in throw error }
    }
}
