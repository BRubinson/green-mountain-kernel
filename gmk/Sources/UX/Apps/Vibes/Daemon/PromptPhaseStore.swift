import Foundation
import Observation

/// Per-prompt read model over CLARIFY_GET + ARCH_GET + EXPLORE_GET + REVIEW_GET, the app's
/// read-only surface onto the report subsystem; every write verb stays bot/CLI-side.
///
/// Memoized on `SessionScope` beside the save actors so N panes on one prompt cost one fetch.
/// SUMMARY_ABSENT is a NORMAL state and publishes `.absent`, never an error banner; plain
/// NOT_FOUND means the prompt uuid is unknown, which is a real failure. Live refresh needs no
/// registration: every phase-change payload carries prompt_uuid, so the connection model
/// routes them to the `.prompt` domain directly.
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

    /// One briefing row paired with its read-time staleness report.
    ///
    /// Staleness is computed by the daemon at every BRIEFING_GET (never stored),
    /// which is why the fetch is LIST + per-row GET rather than LIST alone.
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

    /// Feature 2's per-question draft/version cells.
    ///
    /// OWNED here (one instance per prompt, reached through
    /// `SessionScope.answers(forPrompt:)`) because this store is where
    /// CLARIFY_GET lands — every fetch feeds `adopt`, so the version cells can
    /// never fall behind the rows the UI is editing.
    let answers = ClarificationAnswerModel()

    /// USER INTENT, not payload state: while true every refresh re-fetches
    /// that report with full:true.
    ///
    /// A pane's "show all findings" control sets it; it survives change events
    /// so an expanded pane isn't silently truncated by the next
    /// EXPLORATION_CHANGE — still exactly ONE full fetch per change generation,
    /// never a burst.
    private(set) var wantsFullExploration = false
    private(set) var wantsFullReview = false

    private let service = GMCCDaemonService.shared
    // Scope-aware single flight: a narrower in-flight pass cannot satisfy a
    // wider request — wider requests CHAIN after it (never race it), and the
    // slot is cleared by token so a finished predecessor can't clobber a
    // chained successor's bookkeeping.
    private var inFlight: (task: Task<Void, Never>, lifecyclePhases: Bool, reports: Bool, workflow: Bool, token: UUID)?

    /// Creates a read model for a prompt's phase summaries.
    /// - Parameter promptUuid: The prompt uuid.
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

    /// Coalesces overlapping refresh requests into a single round trip.
    ///
    /// The pane's event loop and the section's first render share one request. `lifecyclePhases:
    /// false` skips CLARIFY_GET/ARCH_GET (legal on a draft); `reports: false` skips
    /// EXPLORE_GET/REVIEW_GET (legal on a fresh stub); `workflow: false` skips BOT_NEXT.
    ///
    /// - Parameters:
    ///   - lifecyclePhases: Whether to fetch clarification and architecture summaries.
    ///   - reports: Whether to fetch exploration and review summaries.
    ///   - workflow: Whether to fetch the workflow status.
    func refresh(
        lifecyclePhases: Bool = true,
        reports: Bool = true,
        workflow: Bool = true
    ) async {
        // Coalesce only with a run at least as wide on every axis.
        if let running = inFlight,
            running.lifecyclePhases || !lifecyclePhases,
            running.reports || !reports,
            running.workflow || !workflow
        {
            await running.task.value
            return
        }
        await chainedRun(lifecyclePhases: lifecyclePhases, reports: reports, workflow: workflow)
    }

    /// One-shot widen from a pane's stub-expansion control.
    ///
    /// Idempotent — second call while already full issues no request. Runs
    /// through the single flight, chained after any in-flight pass: narrow
    /// fetches publish first, full payload last — never clobbered by stale
    /// windows. `workflow: false`: re-fetching a report window is not a reason
    /// to spend another BOT_NEXT round trip (and BOT_NEXT is a write).
    func requestFullExploration() async {
        guard !wantsFullExploration else { return }
        wantsFullExploration = true
        await chainedRun(lifecyclePhases: false, reports: true, workflow: false)
    }

    /// Requests a full review payload on the next refresh.
    ///
    /// Idempotent; a second call while already full is a no-op. Does not fetch BOT_NEXT.
    func requestFullReview() async {
        guard !wantsFullReview else { return }
        wantsFullReview = true
        await chainedRun(lifecyclePhases: false, reports: true, workflow: false)
    }

    /// Starts a new refresh pass after any in-flight request.
    ///
    /// Chains passes to prevent races: prior writes land first, new ones last. Token-checked
    /// ownership of the `inFlight` slot prevents stale predecessors from clearing it.
    ///
    /// - Parameters:
    ///   - lifecyclePhases: Whether to fetch clarification and architecture summaries.
    ///   - reports: Whether to fetch exploration and review summaries.
    ///   - workflow: Whether to fetch the workflow status.
    private func chainedRun(lifecyclePhases: Bool, reports: Bool, workflow: Bool) async {
        let prior = inFlight?.task
        let token = UUID()
        let task = Task {
            await prior?.value
            await self.performRefresh(
                lifecyclePhases: lifecyclePhases,
                reports: reports,
                workflow: workflow
            )
        }
        inFlight = (task, lifecyclePhases, reports, workflow, token)
        await task.value
        if inFlight?.token == token { inFlight = nil }
    }

    /// Performs the actual fetch requests for enabled phases.
    /// - Parameters:
    ///   - lifecyclePhases: Whether to fetch clarification and architecture.
    ///   - reports: Whether to fetch exploration and review.
    ///   - workflow: Whether to fetch the workflow status.
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

    /// Fetches the clarification summary, adopting question version cells.
    /// - Returns: The clarification response, absent if not yet opened, or failed if an error occurred.
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

    /// Fetches the architecture summary.
    /// - Returns: The architecture response, absent if not yet opened, or failed if an error occurred.
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

    /// Fetches the exploration summary, with optional full payload.
    /// - Parameter full: Whether to fetch the full findings or a truncated view.
    /// - Returns: The exploration response, absent if not yet opened, or failed if an error occurred.
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

    /// Fetches the review summary, with optional full payload.
    /// - Parameter full: Whether to fetch the full findings or a truncated view.
    /// - Returns: The review response, absent if not yet opened, or failed if an error occurred.
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

    /// Fetches the workflow status via BOT_NEXT (a write operation).
    ///
    /// BOT_NEXT stamps `last_served_phase` and emits WORKFLOW_CHANGE, which routes to
    /// `.prompt(uuid)` and triggers a refresh. The loop self-damps: when `lastServedPhase ==
    /// current`, nothing is written. Retries once on version conflict.
    ///
    /// - Returns: The workflow response, absent if no `bot_workflow` row exists, or failed if
    ///   an error occurred.
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

    /// Fetches briefing summaries and their staleness reports.
    /// - Returns: The briefing items, empty if none have been created yet, or failed if an error occurred.
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
            // prompt whose briefer never ran simply lists zero rows.
            return .loaded(items)
        } catch let error as DaemonError {
            return .failed(error.userMessage)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
