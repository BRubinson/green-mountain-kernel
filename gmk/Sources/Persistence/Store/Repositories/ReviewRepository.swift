import Foundation
import GRDB

/// REVIEW_* data access — the db-native review report machine.
///
/// Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct ReviewRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent; called ONLY by REVIEW_OPEN — never by setPromptStatus.
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: A tuple with the summary uuid and whether it was created.
    /// - Throws: `StoreError.notFound` if the prompt doesn't exist.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing =
            try ReviewSummaryRecord
            .all()
            .newestFirst()
            .filter(ReviewSummaryRecord.Columns.promptUuid == promptUuid)
            .select(ReviewSummaryRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "review_summary",
            extra: [
                "prompt_uuid": promptUuid,
                "status": ReviewSummaryStatus.reviewing.rawValue,
                "verdict": nil,
                "overview": "",
            ]
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid])
        )
        try clarification.touchSessionForPrompt(promptUuid: promptUuid)
        return (uuid, true)
    }

    // MARK: - Verbs

    /// Opens or retrieves a review summary for a prompt.
    /// - Parameter req: The request with the prompt uuid.
    /// - Returns: The review summary and whether it was newly created.
    /// - Throws: `StoreError.notFound` if the prompt doesn't exist.
    func open(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "review_summary", key: uuid)
        }
        return ReviewSummaryResponse(summary: summary, created: created)
    }

    /// Adds a finding to a review summary.
    /// - Parameter req: The request with finding details and the summary uuid.
    /// - Returns: The newly created finding row.
    /// - Throws: `StoreError.invalidEntityTransition` if summary is not in reviewing status.
    func findingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid,
            at: .reviewing,
            verb: "finding-add"
        )
        let (title, body, agentName) = try Store.validatedFindingText(
            title: req.title,
            body: req.body,
            agentName: req.agentName
        )
        try Store.validateRating(req.rating)
        var path: String?
        if let rawPath = req.filePath {
            path = try Store.normalizeRepoRelativePath(
                rawPath,
                repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid)
            )
        }
        // Mirrored in code ahead of the SQL CHECKs for readable errors.
        if let lineStart = req.lineStart, lineStart < 1 {
            throw StoreError.badRequest(detail: "line_start must be >= 1")
        }
        if let lineEnd = req.lineEnd {
            guard let lineStart = req.lineStart else {
                throw StoreError.badRequest(detail: "line_end requires line_start")
            }
            guard lineEnd >= lineStart else {
                throw StoreError.badRequest(detail: "line_end must be >= line_start")
            }
        }
        let uuid = try core.insertBase(
            db,
            table: "review_finding",
            extra: [
                "review_summary_uuid": req.summaryUuid,
                "kind": req.kind.rawValue,
                "title": title,
                "body": body,
                "file_path": path,
                "line_start": req.lineStart,
                "line_end": req.lineEnd,
                "agent_name": agentName,
                "agent_id": req.agentId,
                "finding_rating": req.rating,
                "status": ReviewFindingStatus.open.rawValue,
            ]
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "finding_add", "kind": req.kind.rawValue,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchFindings(matching: ReviewFindingRecord.Columns.uuid == uuid).first else {
            throw StoreError.notFound(entity: "review_finding", key: uuid)
        }
        return ReviewFindingRowResponse(finding: row)
    }

    /// Batch rank — same contract and rationale as exploreRank.
    /// - Parameter req: The request with the summary uuid and rating updates.
    /// - Returns: The updated summary, count of updated ratings, and unranked count.
    /// - Throws: `StoreError.invalidEntityTransition` if summary is not in reviewing status.
    func rank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .reviewing, verb: "rank")
        try findingRank.applyRankBatch(
            ReviewFindingRecord.self,
            summaryUuid: req.summaryUuid,
            ratings: req.ratings
        )
        let unranked = try findingRank.unrankedCount(
            ReviewFindingRecord.self,
            summaryUuid: req.summaryUuid
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "rank", "count": req.ratings.count,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewRankResponse(
            summary: updated,
            updatedCount: req.ratings.count,
            unrankedCount: unranked
        )
    }

    /// Record one finding's resolution.
    ///
    /// Pure child-row update (expectedVersion targets the FINDING) and
    /// deliberately UNGATED on summary status — see the facade header. Edges:
    /// open → fixed | accepted | wont_fix, plus lateral corrections among the
    /// resolved values; never back to open.
    ///
    /// - Parameter req: The request with finding uuid, target status, and expected version.
    /// - Returns: The updated finding row.
    /// - Throws: `StoreError.invalidEntityTransition` if status change is invalid.
    func resolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        guard
            let row = try fetchFindings(
                matching: ReviewFindingRecord.Columns.uuid == req.findingUuid
            )
            .first
        else {
            throw StoreError.notFound(entity: "review_finding", key: req.findingUuid)
        }
        guard let from = ReviewFindingStatus(rawValue: row.status) else {
            throw StoreError.corruptState(entity: "review_finding", detail: "status '\(row.status)'")
        }
        // Same-status retry is an idempotent no-op (fix loops re-run):
        // no version bump, no event, just the current row back.
        if from == req.status {
            return ReviewFindingRowResponse(finding: row)
        }
        guard from.allowedNext.contains(req.status) else {
            throw StoreError.invalidEntityTransition(
                entity: "review_finding",
                from: from.rawValue,
                to: req.status.rawValue,
                reason: from == .open
                    ? "resolve targets fixed, accepted, or wont_fix"
                    : "a resolved finding can only move laterally (never back to open)"
            )
        }
        try core.updateBase(
            db,
            table: "review_finding",
            uuid: req.findingUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": req.status.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: row.reviewSummaryUuid,
            payload: Store.jsonPayload([
                "action": "resolve", "finding_uuid": req.findingUuid,
                "to": req.status.rawValue,
            ])
        )
        if let summary = try fetchSummary(uuid: row.reviewSummaryUuid) {
            try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        }
        guard
            let updated = try fetchFindings(
                matching: ReviewFindingRecord.Columns.uuid == req.findingUuid
            )
            .first
        else {
            throw StoreError.notFound(entity: "review_finding", key: req.findingUuid)
        }
        return ReviewFindingRowResponse(finding: updated)
    }

    /// Marks a review summary as complete.
    ///
    /// Moves state from reviewing → complete. Refuses while any finding is unranked;
    /// requires a verdict (validated in Swift ahead of the SQL CHECK for a clean
    /// message). overview + verdict are carried only here.
    ///
    /// - Parameter req: The request with summary uuid, verdict, overview, and expected version.
    /// - Returns: The completed review summary.
    /// - Throws: `StoreError.invalidEntityTransition` if unranked findings exist.
    func complete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .reviewing, verb: "complete")
        let unranked = try findingRank.unrankedCount(
            ReviewFindingRecord.self,
            summaryUuid: req.summaryUuid
        )
        guard unranked == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "review",
                from: summary.status,
                to: ReviewSummaryStatus.complete.rawValue,
                reason: "\(unranked) finding(s) unranked — run the review rank pass "
                    + "(\(CdeToolSpec.qualifiedName("cde_rpir_review")) op rank) first"
            )
        }
        let overview = try Store.validatedOverview(req.overview, entity: "review")
        try core.updateBase(
            db,
            table: "review_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": ReviewSummaryStatus.complete.rawValue,
                "overview": overview,
                "verdict": req.verdict.rawValue,
            ]
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "complete", "verdict": req.verdict.rawValue,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewSummaryResponse(summary: updated)
    }

    /// Reopens a completed review for revision.
    ///
    /// Moves state from complete → reviewing. Same preservation contract as
    /// exploreReopen; the persisted verdict survives until re-complete.
    ///
    /// - Parameter req: The request with summary uuid and expected version.
    /// - Returns: The reopened review summary.
    /// - Throws: `StoreError.invalidEntityTransition` if summary is not complete.
    func reopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        guard summary.reviewStatus == .complete else {
            throw StoreError.invalidEntityTransition(
                entity: "review",
                from: summary.status,
                to: ReviewSummaryStatus.reviewing.rawValue,
                reason: "reopen runs from complete — this summary is \(summary.status)"
            )
        }
        try core.updateBase(
            db,
            table: "review_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ReviewSummaryStatus.reviewing.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .reviewChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "reopen", "prompt_uuid": summary.promptUuid])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewSummaryResponse(summary: updated)
    }

    /// Fetches a review summary with its findings, filtered by rating window.
    /// - Parameter req: The request with prompt uuid and optional rating filters.
    /// - Returns: The review summary with full findings and stubbed findings outside the window.
    /// - Throws: `StoreError.notFound` if prompt not found; `StoreError.summaryAbsent` if no review.
    func get(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard
            let composed = try ReviewSummaryWithFindings.request()
                .filter(ReviewSummaryRecord.Columns.promptUuid == req.promptUuid)
                .newestFirst()
                .fetchOne(db)
        else {
            throw StoreError.summaryAbsent(
                entity: "review",
                promptUuid: req.promptUuid
            )
        }
        let summary = composed.summary.dto()
        let window = try Store.ratingWindow(full: req.full, min: req.ratingMin, max: req.ratingMax)
        let all = composed.findings.map { $0.dto() }
        var full: [ReviewFindingRow] = []
        var stubs: [ReviewFindingStub] = []
        for row in all {
            if Store.ratingInWindow(row.findingRating, window: window) {
                full.append(row)
            } else {
                stubs.append(
                    ReviewFindingStub(
                        uuid: row.uuid,
                        kind: row.kind,
                        title: row.title,
                        findingRating: row.findingRating,
                        agentName: row.agentName,
                        status: row.status
                    )
                )
            }
        }
        return ReviewGetResponse(summary: summary, findings: full, findingStubs: stubs)
    }

    // MARK: - Transition + fetch helpers

    /// Fetches a review summary and asserts it is in the required status.
    /// - Parameters:
    ///   - uuid: The review summary uuid.
    ///   - required: The required summary status.
    ///   - verb: The operation name for error messages.
    /// - Returns: The review summary row.
    /// - Throws: `StoreError.notFound` if not found; `StoreError.invalidEntityTransition` if status mismatch.
    private func requireSummary(
        uuid: String,
        at required: ReviewSummaryStatus,
        verb: String
    ) throws -> ReviewSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "review_summary", key: uuid)
        }
        guard summary.reviewStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "review",
                from: summary.status,
                to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)"
            )
        }
        return summary
    }

    /// Fetches a review summary by its uuid.
    /// - Parameter uuid: The review summary uuid.
    /// - Returns: The review summary row, or nil if not found.
    /// - Throws: Any database error during the fetch.
    func fetchSummary(uuid: String) throws -> ReviewSummaryRow? {
        try fetchSummary(matching: ReviewSummaryRecord.Columns.uuid == uuid)
    }

    /// Fetches the most recent review summary for a prompt.
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The review summary row, or nil if not found.
    /// - Throws: Any database error during the fetch.
    func fetchSummary(byPrompt promptUuid: String) throws -> ReviewSummaryRow? {
        try fetchSummary(matching: ReviewSummaryRecord.Columns.promptUuid == promptUuid)
    }

    /// Fetches a review summary matching the given predicate.
    /// - Parameter predicate: The SQL filter expression.
    /// - Returns: The most recent matching summary row, or nil if not found.
    /// - Throws: Any database error during the fetch.
    private func fetchSummary(matching predicate: SQLExpression) throws -> ReviewSummaryRow? {
        try ReviewSummaryRecord.all().newestFirst().filter(predicate).fetchOne(db)?.dto()
    }

    /// Fetches findings matching a predicate, ordered by rank status, rating, id.
    ///
    /// Same explicit ordering contract as ExplorationRepository.fetchFindings:
    /// unranked first, then rating ascending, then id.
    ///
    /// - Parameter predicate: The SQL filter expression.
    /// - Returns: The ordered list of finding rows matching the predicate.
    /// - Throws: Any database error during the fetch.
    private func fetchFindings(matching predicate: SQLExpression) throws -> [ReviewFindingRow] {
        try ReviewFindingRecord
            .all()
            .filter(predicate)
            .order(
                ReviewFindingRecord.Columns.findingRating != nil,
                ReviewFindingRecord.Columns.findingRating,
                Column("id")
            )
            .fetchAll(db)
            .map { $0.dto() }
    }
}
