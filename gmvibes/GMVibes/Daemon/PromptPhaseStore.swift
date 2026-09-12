import Foundation
import Observation
import GMCCDaemonKit

/// Per-prompt read model over CLARIFY_GET + ARCH_GET + EXPLORE_GET +
/// REVIEW_GET — the app's only surface onto the db-native report subsystem
/// (read-only by clarified scope; every write verb stays bot/CLI-side).
///
/// Memoized on `SessionScope` beside the save actors so N panes on one prompt
/// cost one fetch. SUMMARY_ABSENT is a NORMAL state (the summary was never
/// opened) — it publishes `.absent`, never an error banner. Plain NOT_FOUND
/// means the prompt uuid itself is unknown — a real failure, never absence.
///
/// Live refresh needs no registration: as of wire v8 every phase-change
/// payload (CLARIFICATION/ARCHITECTURE/EXPLORATION/REVIEW_CHANGE) carries
/// prompt_uuid, so the connection model routes them to the `.prompt` domain
/// directly.
@Observable
@MainActor
final class PromptPhaseStore {
    enum Phase<T: Equatable>: Equatable {
        case idle
        /// No summary row exists (SUMMARY_ABSENT) — the summary was simply
        /// never opened.
        case absent
        case loaded(T)
        case failed(String)
    }

    /// One briefing row paired with its read-time staleness report. Staleness
    /// is computed by the daemon at every BRIEFING_GET (never stored), which
    /// is why the fetch is LIST + per-row GET rather than LIST alone.
    struct BriefingItem: Equatable {
        let briefing: AgentBriefingRow
        let staleness: BriefingStaleness
    }

    let promptUuid: String
    private(set) var clarification: Phase<ClarifyGetResponse> = .idle
    private(set) var architecture: Phase<ArchGetResponse> = .idle
    private(set) var exploration: Phase<ExploreGetResponse> = .idle
    private(set) var review: Phase<ReviewGetResponse> = .idle
    private(set) var briefings: Phase<[BriefingItem]> = .idle
    /// BOT_NEXT's derived view of the prompt's `bot_workflow` — the phase the
    /// strip renders. `.absent` covers BOTH never-started and `/gm_task`
    /// (where absence is permanent); they are deliberately one arm.
    private(set) var workflow: Phase<BotNextResponse> = .idle
    private(set) var hasLoaded = false

    /// Feature 2's per-question draft/version cells. OWNED here (one instance
    /// per prompt, reached through `SessionScope.answers(forPrompt:)`) because
    /// this store is where CLARIFY_GET lands — every fetch feeds `adopt`, so
    /// the version cells can never fall behind the rows the UI is editing.
    let answers = ClarificationAnswerModel()

    /// USER INTENT, not payload state: while true every refresh re-fetches
    /// that report with full:true. A pane's "show all findings" control sets
    /// it; it survives change events so an expanded pane isn't silently
    /// truncated by the next EXPLORATION_CHANGE — still exactly ONE full
    /// fetch per change generation, never a burst.
    private(set) var wantsFullExploration = false
    private(set) var wantsFullReview = false

    private let service = GMCCDaemonService.shared
    // Scope-aware single flight: a narrower in-flight pass cannot satisfy a
    // wider request — wider requests CHAIN after it (never race it), and the
    // slot is cleared by token so a finished predecessor can't clobber a
    // chained successor's bookkeeping.
    private var inFlight: (task: Task<Void, Never>, lifecyclePhases: Bool, reports: Bool, workflow: Bool, token: UUID)?

    init(promptUuid: String) {
        self.promptUuid = promptUuid
        // A conflicted CLARIFY_ANSWER needs fresh question rows to be
        // recoverable — without them the user would keep re-sending the same
        // stale expected version. This store is the only thing that can issue
        // CLARIFY_GET, so it hands the model the pull. Lifecycle phases only:
        // a write collision on one question is no reason to re-fetch the
        // reports or spend a BOT_NEXT.
        answers.onNeedsRefresh = { [weak self] in
            await self?.refresh(lifecyclePhases: true, reports: false, workflow: false)
        }
    }

    // MARK: - Derived

    var clarificationStatus: ClarificationStatus? {
        if case .loaded(let response) = clarification {
            return response.summary.clarificationStatus
        }
        return nil
    }

    var architectureStatus: ArchitectureStatus? {
        if case .loaded(let response) = architecture {
            return response.summary.architectureStatus
        }
        return nil
    }

    // MARK: - Refresh

    /// Coalesced single-flight (house idiom) — the pane's event loop and the
    /// section's first render must share one round trip set.
    ///
    /// `lifecyclePhases: false` skips CLARIFY_GET/ARCH_GET — draft prompts
    /// provably have neither (the two-guaranteed-absent round trips the old
    /// all-or-nothing gate existed to prevent). `reports: false` skips
    /// EXPLORE_GET/REVIEW_GET — legal ONLY for evidence-gated event-loop
    /// wakes on a draft whose freshly-listed stub shows no report summaries
    /// (an EXPLORATION_CHANGE re-lists the stub first, so the evidence is
    /// never stale); the first load and every status change fetch reports
    /// unconditionally because EXPLORE_OPEN is explicit-only and legally
    /// runs while the prompt is still draft.
    ///
    /// `workflow: false` skips BOT_NEXT. It is its OWN axis, never folded into
    /// `lifecyclePhases`: `gm prompt start` deliberately creates the
    /// `bot_workflow` row while the prompt is still `draft`, so gating the
    /// strip on the lifecycle axis would blind it on exactly the prompts that
    /// most need it.
    func refresh(lifecyclePhases: Bool = true, reports: Bool = true,
                 workflow: Bool = true) async {
        // Coalesce only with a run at least as wide on every axis.
        if let running = inFlight,
           running.lifecyclePhases || !lifecyclePhases,
           running.reports || !reports,
           running.workflow || !workflow {
            await running.task.value
            return
        }
        await chainedRun(lifecyclePhases: lifecyclePhases, reports: reports, workflow: workflow)
    }

    /// One-shot widen from a pane's stub-expansion control. Idempotent — a
    /// second call while already full issues no request. Runs THROUGH the
    /// single flight, chained after any in-flight pass: a narrow fetch that
    /// captured full:false before the flag flipped publishes first, and the
    /// full payload always publishes last — never clobbered by a stale
    /// window.
    /// `workflow: false` on both widens: re-fetching a report window is not a
    /// reason to spend another BOT_NEXT round trip (and BOT_NEXT is a write).
    func requestFullExploration() async {
        guard !wantsFullExploration else { return }
        wantsFullExploration = true
        await chainedRun(lifecyclePhases: false, reports: true, workflow: false)
    }

    func requestFullReview() async {
        guard !wantsFullReview else { return }
        wantsFullReview = true
        await chainedRun(lifecyclePhases: false, reports: true, workflow: false)
    }

    /// Start a new pass AFTER whatever is in flight (chain, never race — the
    /// prior task's writes land first, ours land last). Ownership of the
    /// `inFlight` slot is token-checked on exit: a predecessor resuming after
    /// a chained successor replaced the slot must not nil it out (that would
    /// let a third caller start a redundant racing pass).
    private func chainedRun(lifecyclePhases: Bool, reports: Bool, workflow: Bool) async {
        let prior = inFlight?.task
        let token = UUID()
        let task = Task {
            await prior?.value
            await self.performRefresh(
                lifecyclePhases: lifecyclePhases, reports: reports, workflow: workflow)
        }
        inFlight = (task, lifecyclePhases, reports, workflow, token)
        await task.value
        if inFlight?.token == token { inFlight = nil }
    }

    private func performRefresh(lifecyclePhases: Bool, reports: Bool, workflow: Bool) async {
        if lifecyclePhases {
            let newClarification = await fetchClarification()
            if clarification != newClarification { clarification = newClarification }
            let newArchitecture = await fetchArchitecture()
            if architecture != newArchitecture { architecture = newArchitecture }
        }
        if reports {
            // Sequential, never concurrent: the daemon has one serial queue.
            // Fullness is read HERE, not captured at schedule time, so a pass
            // chained behind a widen request fetches at the new intent.
            let newExploration = await fetchExploration(full: wantsFullExploration)
            if exploration != newExploration { exploration = newExploration }
            let newReview = await fetchReview(full: wantsFullReview)
            if review != newReview { review = newReview }
            let newBriefings = await fetchBriefings()
            if briefings != newBriefings { briefings = newBriefings }
        }
        if workflow {
            // UNCONDITIONAL with respect to `lifecyclePhases` — see refresh().
            let newWorkflow = await fetchWorkflow()
            if self.workflow != newWorkflow { self.workflow = newWorkflow }
        }
        hasLoaded = true
    }

    private func fetchClarification() async -> Phase<ClarifyGetResponse> {
        do {
            let response = try await service.clarification(promptUuid: promptUuid)
            // Version cells are refreshed on EVERY CLARIFY_GET and every
            // event-triggered refetch — the server version always wins, and a
            // dirty draft keeps the user's text while adopting the new cell so
            // the next Save is legal. One line, no second lifecycle.
            answers.adopt(response.questions)
            return .loaded(response)
        } catch DaemonError.summaryAbsent {
            return .absent
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func fetchArchitecture() async -> Phase<ArchGetResponse> {
        do {
            return .loaded(try await service.architecture(promptUuid: promptUuid))
        } catch DaemonError.summaryAbsent {
            return .absent
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func fetchExploration(full: Bool) async -> Phase<ExploreGetResponse> {
        do {
            return .loaded(try await service.exploration(promptUuid: promptUuid, full: full))
        } catch DaemonError.summaryAbsent {
            return .absent
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func fetchReview(full: Bool) async -> Phase<ReviewGetResponse> {
        do {
            return .loaded(try await service.review(promptUuid: promptUuid, full: full))
        } catch DaemonError.summaryAbsent {
            return .absent
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// BOT_NEXT, honestly a write: it stamps `last_served_phase` and emits
    /// WORKFLOW_CHANGE. Two consequences are handled here and nowhere else.
    ///
    /// THE FEEDBACK LOOP, written down where the next reader will find it:
    /// BOT_NEXT stamps `last_served_phase` and emits WORKFLOW_CHANGE, which
    /// `DaemonConnectionModel` routes to `.prompt(uuid)`, which triggers a
    /// refresh, which issues another BOT_NEXT. The loop SELF-DAMPS — the
    /// second call finds `lastServedPhase == current` and writes nothing, so
    /// no event is emitted and the chain stops. Cost is exactly one extra
    /// round trip per REAL phase change, and the derivation is deterministic
    /// on db state, so it cannot oscillate. To verify: open a prompt pane,
    /// watch the event stream, and confirm it goes quiet.
    ///
    /// SUMMARY_ABSENT is the normal no-`bot_workflow`-row state:
    /// `resolve(promptUuid:)` throws exactly this when no row exists, so
    /// never-started AND permanent `/gm_task` land on ONE `.absent` arm — the
    /// header renders alone, with no distinguishing copy.
    private func fetchWorkflow() async -> Phase<BotNextResponse> {
        do {
            do {
                return .loaded(try await service.botNext(promptUuid: promptUuid))
            } catch DaemonError.versionConflict {
                // ONE silent retry. BOT_NEXT writes last_served_phase through
                // core.updateBase with an expected version, so a live bot run
                // calling BOT_NEXT concurrently can make this call lose the
                // race. A lost race is a STALE READ, not a user-visible
                // failure — retry once; only a second loss surfaces.
                return .loaded(try await service.botNext(promptUuid: promptUuid))
            }
        } catch DaemonError.summaryAbsent {
            return .absent
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func fetchBriefings() async -> Phase<[BriefingItem]> {
        do {
            let list = try await service.briefings(promptUuid: promptUuid).briefings
            var items: [BriefingItem] = []
            // Sequential, never concurrent: the daemon has one serial queue.
            // Two rows today (initial / pre_architecture); the step vocabulary
            // is registry-extensible so we iterate whatever LIST returns.
            for row in list {
                let got = try await service.briefing(uuid: row.uuid)
                items.append(BriefingItem(briefing: got.briefing, staleness: got.staleness))
            }
            // Empty is NORMAL: briefings have no SUMMARY_ABSENT on LIST — a
            // prompt whose doper never ran simply lists zero rows.
            return .loaded(items)
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
