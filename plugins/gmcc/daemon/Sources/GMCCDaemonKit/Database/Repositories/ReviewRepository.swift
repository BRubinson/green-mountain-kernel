import Foundation
import GRDB

/// REVIEW_* data access — the db-native review report machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct ReviewRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent; called ONLY by REVIEW_OPEN — never by setPromptStatus.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM review_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "review_summary", extra: [
            "prompt_uuid": promptUuid,
            "status": ReviewSummaryStatus.reviewing.rawValue,
            "verdict": nil,
            "overview": "",
        ])
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: promptUuid)
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "review_summary", key: uuid)
        }
        return ReviewSummaryResponse(summary: summary, created: created)
    }

    func findingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid, at: .reviewing, verb: "finding-add")
        let (title, body, agentName) = try Store.validatedFindingText(
            title: req.title, body: req.body, agentName: req.agentName)
        try Store.validateRating(req.rating)
        var path: String?
        if let rawPath = req.filePath {
            path = try Store.normalizeRepoRelativePath(
                rawPath, repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid))
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
        let uuid = try core.insertBase(db, table: "review_finding", extra: [
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
        ])
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "finding_add", "kind": req.kind.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchFindings(where: "uuid = ?", arguments: [uuid]).first else {
            throw StoreError.notFound(entity: "review_finding", key: uuid)
        }
        return ReviewFindingRowResponse(finding: row)
    }

    /// Batch rank — same contract and rationale as exploreRank.
    func rank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .reviewing, verb: "rank")
        try findingRank.applyRankBatch(
            table: "review_finding", parentColumn: "review_summary_uuid",
            summaryUuid: req.summaryUuid, ratings: req.ratings)
        let unranked = try findingRank.unrankedCount(
            table: "review_finding", parentColumn: "review_summary_uuid",
            summaryUuid: req.summaryUuid)
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "rank", "count": req.ratings.count,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewRankResponse(
            summary: updated, updatedCount: req.ratings.count, unrankedCount: unranked)
    }

    /// Record one finding's resolution. Pure child-row update (expectedVersion
    /// targets the FINDING) and deliberately UNGATED on summary status — see
    /// the facade header. Edges: open → fixed | accepted | wont_fix, plus
    /// lateral corrections among the resolved values; never back to open.
    func resolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        guard let row = try fetchFindings(
            where: "uuid = ?", arguments: [req.findingUuid]
        ).first else {
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
                entity: "review_finding", from: from.rawValue, to: req.status.rawValue,
                reason: from == .open
                    ? "resolve targets fixed, accepted, or wont_fix"
                    : "a resolved finding can only move laterally (never back to open)")
        }
        try core.updateBase(
            db, table: "review_finding", uuid: req.findingUuid,
            expectedVersion: req.expectedVersion, set: ["status": req.status.rawValue])
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: row.reviewSummaryUuid,
            payload: Store.jsonPayload([
                "action": "resolve", "finding_uuid": req.findingUuid,
                "to": req.status.rawValue,
            ]))
        if let summary = try fetchSummary(uuid: row.reviewSummaryUuid) {
            try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        }
        guard let updated = try fetchFindings(
            where: "uuid = ?", arguments: [req.findingUuid]
        ).first else {
            throw StoreError.notFound(entity: "review_finding", key: req.findingUuid)
        }
        return ReviewFindingRowResponse(finding: updated)
    }

    /// reviewing → complete. Refuses while any finding is unranked; requires a
    /// verdict (validated in Swift ahead of the SQL CHECK for a clean
    /// message). overview + verdict are carried only here.
    func complete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .reviewing, verb: "complete")
        let unranked = try findingRank.unrankedCount(
            table: "review_finding", parentColumn: "review_summary_uuid",
            summaryUuid: req.summaryUuid)
        guard unranked == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "review", from: summary.status,
                to: ReviewSummaryStatus.complete.rawValue,
                reason: "\(unranked) finding(s) unranked — run the review rank pass "
                    + "(mcp__plugin_gmcc_pen__review_rank) first")
        }
        let overview = try Store.validatedOverview(req.overview, entity: "review")
        try core.updateBase(
            db, table: "review_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": ReviewSummaryStatus.complete.rawValue,
                "overview": overview,
                "verdict": req.verdict.rawValue,
            ])
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "complete", "verdict": req.verdict.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewSummaryResponse(summary: updated)
    }

    /// complete → reviewing: the revision edge (same preservation contract as
    /// exploreReopen; the persisted verdict survives until re-complete).
    func reopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        guard summary.reviewStatus == .complete else {
            throw StoreError.invalidEntityTransition(
                entity: "review", from: summary.status,
                to: ReviewSummaryStatus.reviewing.rawValue,
                reason: "reopen runs from complete — this summary is \(summary.status)")
        }
        try core.updateBase(
            db, table: "review_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ReviewSummaryStatus.reviewing.rawValue])
        try core.appendEvent(
            db, kind: .reviewChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "reopen", "prompt_uuid": summary.promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "review_summary", key: req.summaryUuid)
        }
        return ReviewSummaryResponse(summary: updated)
    }

    func get(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            throw StoreError.summaryAbsent(
                entity: "review", promptUuid: req.promptUuid)
        }
        let window = try Store.ratingWindow(full: req.full, min: req.ratingMin, max: req.ratingMax)
        let all = try fetchFindings(
            where: "review_summary_uuid = ?", arguments: [summary.uuid])
        var full: [ReviewFindingRow] = []
        var stubs: [ReviewFindingStub] = []
        for row in all {
            if Store.ratingInWindow(row.findingRating, window: window) {
                full.append(row)
            } else {
                stubs.append(ReviewFindingStub(
                    uuid: row.uuid, kind: row.kind, title: row.title,
                    findingRating: row.findingRating, agentName: row.agentName,
                    status: row.status))
            }
        }
        return ReviewGetResponse(summary: summary, findings: full, findingStubs: stubs)
    }

    // MARK: - Transition + fetch helpers

    private func requireSummary(
        uuid: String, at required: ReviewSummaryStatus, verb: String
    ) throws -> ReviewSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "review_summary", key: uuid)
        }
        guard summary.reviewStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "review", from: summary.status, to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)")
        }
        return summary
    }

    func fetchSummary(uuid: String) throws -> ReviewSummaryRow? {
        try fetchSummary(where: "uuid = ?", key: uuid)
    }

    func fetchSummary(byPrompt promptUuid: String) throws -> ReviewSummaryRow? {
        try fetchSummary(where: "prompt_uuid = ?", key: promptUuid)
    }

    private func fetchSummary(
        where condition: String, key: String
    ) throws -> ReviewSummaryRow? {
        try ReviewSummaryRecord.fetchAll(
            db, where: condition, arguments: [key]
        ).first?.wireRow()
    }

    /// Same explicit ordering contract as ExplorationRepository.fetchFindings:
    /// unranked first, then rating ascending, then id.
    private func fetchFindings(
        where condition: String, arguments: StatementArguments
    ) throws -> [ReviewFindingRow] {
        try ReviewFindingRecord.fetchAll(
            db, where: condition, arguments: arguments,
            orderBy: "finding_rating IS NOT NULL, finding_rating, id"
        ).map { $0.wireRow() }
    }
}
