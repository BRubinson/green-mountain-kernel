import Foundation
import GRDB

/// SESSION_GET / SESSION_UPDATE data access, plus the activation registry
/// (v21) and the shared prompt-stub/change-summary aggregations. Runs INSIDE
/// a Store-owned transaction; holds no dbQueue and never self-transacts.
struct SessionRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        guard let session = try fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        let prompts = try fetchPromptStubs(sessionUuid: req.sessionUuid)
        let changeSummary = try changeSummary(sessionUuid: req.sessionUuid)
        let promptChanges = try promptChangeSummaries(sessionUuid: req.sessionUuid)
        return SessionGetResponse(
            session: session,
            prompts: prompts,
            changeSummary: changeSummary,
            promptChanges: promptChanges
        )
    }

    func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let name = req.name { set["name"] = name }
        if let backstory = req.backstory { set["backstory"] = backstory }
        if let goal = req.goal { set["goal"] = goal }
        // Manual override of the activation claim PROMPT_SET_STATUS
        // normally maintains for the calling instance. Exactly one of
        // the pair; the prompt must belong to this session (a Swift
        // guard — CHECK cannot cross tables).
        var activationTouched = false
        if let activePromptUuid = req.activePromptUuid {
            guard req.clearActivePrompt != true else {
                throw StoreError.badRequest(
                    detail: "activePromptUuid and clearActivePrompt are mutually exclusive"
                )
            }
            guard let clientKey = req.clientKey else {
                throw StoreError.badRequest(
                    detail: "activation claims need a client key — run via gm, which resolves it"
                )
            }
            guard
                let owner =
                    try PromptRecord
                    .all()
                    .withUuid(activePromptUuid)
                    .select(PromptRecord.Columns.sessionUuid, as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: "prompt", key: activePromptUuid)
            }
            guard owner == req.sessionUuid else {
                throw StoreError.badRequest(
                    detail: "prompt \(activePromptUuid) belongs to session \(owner), not \(req.sessionUuid)"
                )
            }
            try claimActivation(
                sessionUuid: req.sessionUuid,
                promptUuid: activePromptUuid,
                clientKey: clientKey
            )
            activationTouched = true
        } else if req.clearActivePrompt == true {
            guard let clientKey = req.clientKey else {
                throw StoreError.badRequest(
                    detail: "activation claims need a client key — run via gm, which resolves it"
                )
            }
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE client_key = ?",
                arguments: [clientKey]
            )
            activationTouched = true
        }
        guard !set.isEmpty || activationTouched else {
            throw StoreError.emptyUpdate(entity: "session")
        }
        if !set.isEmpty {
            try core.updateBase(
                db,
                table: "session",
                uuid: req.sessionUuid,
                expectedVersion: req.expectedVersion,
                set: set
            )
        }
        try core.appendEvent(
            db,
            kind: .updateSession,
            subjectUuid: req.sessionUuid,
            payload: Store.jsonPayload(["fields": set.keys.sorted()])
        )
        guard let row = try fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        return row
    }

    // MARK: - Shared fetch helpers

    func fetchRow(uuid: String) throws -> SessionRow? {
        try SessionWithActivations.request()
            .withUuid(uuid)
            .fetchOne(db)?
            .dto()
    }

    // MARK: - Activation registry (v21)

    /// One claim per running Claude instance (client_key) and per prompt:
    /// re-claiming replaces both sides' old rows so the two partial-unique
    /// indexes can never collide on a legitimate re-claim.
    func claimActivation(
        sessionUuid: String,
        promptUuid: String,
        clientKey: String
    ) throws {
        try evictDeadActivations(sessionUuid: sessionUuid)
        try db.execute(
            sql: "DELETE FROM prompt_activation WHERE client_key = ? OR prompt_uuid = ?",
            arguments: [clientKey, promptUuid]
        )
        _ = try core.insertBase(
            db,
            table: "prompt_activation",
            extra: [
                "session_uuid": sessionUuid,
                "prompt_uuid": promptUuid,
                "client_key": clientKey,
            ]
        )
    }

    /// Opportunistic liveness eviction (review finding 033dad8f): only
    /// `done` releases a claim, so a crashed/restarted Claude instance would
    /// otherwise poison the single-claim fallback forever. The key embeds
    /// pid + start time, so liveness is checkable server-side; unknown key
    /// shapes are left alone (they can't lie about liveness we can't check).
    func evictDeadActivations(sessionUuid: String) throws {
        let claims =
            try PromptActivationRecord
            .filter(PromptActivationRecord.Columns.sessionUuid == sessionUuid)
            .fetchAll(db)
        for claim in claims where !Store.clientKeyLooksAlive(claim.clientKey) {
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE uuid = ?",
                arguments: [claim.uuid]
            )
        }
    }

    func fetchActivations(sessionUuid: String) throws -> [PromptActivationRow] {
        try PromptActivationRecord
            .filter(PromptActivationRecord.Columns.sessionUuid == sessionUuid)
            .orderedByCreatedAt()
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// The attribution ladder shared by file-change auto-attribution and the
    /// briefing active resolution: the caller's own claim first, then the
    /// session's single claim when unambiguous, else nil (never a guess
    /// between two concurrent prompts).
    func resolveActivePrompt(
        sessionUuid: String,
        clientKey: String?
    ) throws -> String? {
        // Dead claims are FILTERED here rather than deleted: this runs inside
        // read transactions (briefing get/stub). Deletion happens on the
        // write paths (claimActivation) — filtering keeps read results
        // correct in the meantime.
        let live = try fetchActivations(sessionUuid: sessionUuid)
            .filter { Store.clientKeyLooksAlive($0.clientKey) }
        if let clientKey, let own = live.first(where: { $0.clientKey == clientKey }) {
            return own.promptUuid
        }
        return live.count == 1 ? live[0].promptUuid : nil
    }

    /// nil sessionUuid = every prompt in the db, grouped by session (seq is
    /// only unique per session, hence the two-column ORDER BY). withReports
    /// attaches the per-prompt clarification/architecture/exploration/review
    /// summary stubs via four grouped aggregate queries folded into
    /// dictionaries — one grouped aggregation per machine, never per-row (a
    /// per-prompt fetch here would be the N+1 the enrichment exists to
    /// delete).
    func fetchPromptStubs(
        sessionUuid: String?,
        withReports: Bool = false
    ) throws -> [PromptStub] {
        let clar = withReports ? try clarificationReports(sessionUuid: sessionUuid) : [:]
        let arch = withReports ? try architectureReports(sessionUuid: sessionUuid) : [:]
        let explore = withReports ? try explorationReports(sessionUuid: sessionUuid) : [:]
        let review = withReports ? try reviewReports(sessionUuid: sessionUuid) : [:]
        return try PromptSummary.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .map { summary in
                let uuid = summary.prompt.uuid
                return summary.dto(
                    reports: withReports
                        ? PromptReportsStub(
                            clarification: clar[uuid],
                            architecture: arch[uuid],
                            exploration: explore[uuid],
                            review: review[uuid]
                        )
                        : nil
                )
            }
    }

    /// m0025: questions and notes are the split children; the care package
    /// flag surfaces the clarified-intent artifact. A prompt carrying more
    /// than one summary keeps the last row read, as the retired SQL did.
    private func clarificationReports(
        sessionUuid: String?
    ) throws -> [String: ClarificationReportStub] {
        try ClarificationReport.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .reduce(into: [:]) { $0[$1.summary.promptUuid] = $1.dto() }
    }

    private func architectureReports(
        sessionUuid: String?
    ) throws -> [String: ArchitectureReportStub] {
        try ArchitectureReport.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .reduce(into: [:]) { $0[$1.summary.promptUuid] = $1.dto() }
    }

    /// m0025: summaries are per-agent — the stub aggregates the PROMPT, so
    /// counts span every summary and the representative row is the synthesis
    /// (seal) row when present.
    private func explorationReports(
        sessionUuid: String?
    ) throws -> [String: ExplorationReportStub] {
        try ExplorationReport.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .reduce(into: [:]) { $0[$1.promptUuid] = $1.dto() }
    }

    private func reviewReports(
        sessionUuid: String?
    ) throws -> [String: ReviewReportStub] {
        try ReviewReport.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .reduce(into: [:]) { $0[$1.summary.promptUuid] = $1.dto() }
    }

    /// One session's whole change tally, ranges folded in.
    func changeSummary(sessionUuid: String) throws -> ChangeSummary {
        try ChangeRollup.request(sessionUuid: sessionUuid).fetchOne(db)?.dto() ?? Self.noChanges
    }

    /// One prompt's change tally, the same shape narrowed to its attribution.
    func changeSummary(promptUuid: String) throws -> ChangeSummary {
        try ChangeRollup.request(promptUuid: promptUuid).fetchOne(db)?.dto() ?? Self.noChanges
    }

    func promptChangeSummaries(sessionUuid: String) throws -> [PromptChangeSummary] {
        try PromptChangeRollup.request(sessionUuid: sessionUuid)
            .fetchAll(db)
            .map { $0.dto() }
    }

    private static let noChanges = ChangeSummary(changeCount: 0, distinctFiles: 0, totalLineSpan: 0)
}
