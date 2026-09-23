import Foundation
import GRDB

/// EXPLORE_* data access — the db-native exploration report machine.
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. The shared rank/validation statics stay on Store, serving
/// Store+Review too. Summaries are per-agent rows keyed UNIQUE(prompt_uuid,
/// agent_type), and each agent completes its OWN. The `synthesis`-type row is
/// the prompt-level seal: its complete refuses while any finding across the
/// prompt is unranked. Key files are findings of kind 'key_file'.
struct ExplorationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Returns the existing summary or creates one for a prompt and agent type.
    ///
    /// Idempotent per (prompt, agentType). Called only by EXPLORE_OPEN, never by
    /// setPromptStatus (which does explicit-open only).
    ///
    /// - Parameters:
    ///   - promptUuid: The prompt identifier.
    ///   - agentType: The exploration agent type.
    ///   - agentId: Optional agent instance identifier.
    /// - Returns: A tuple of the summary UUID and a boolean indicating whether it was created.
    /// - Throws: `StoreError` on prompt not found, unknown agent type, or invalid workflow variant.
    @discardableResult
    func ensureSummary(
        promptUuid: String,
        agentType: String,
        agentId: String?
    ) throws -> (uuid: String, created: Bool) {
        guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        guard let agent = ExplorationAgentType(rawValue: agentType) else {
            throw StoreError.badRequest(
                detail: "unknown exploration agent type '\(agentType)' — one of "
                    + ExplorationAgentType.allCases.map(\.rawValue).joined(separator: "|")
            )
        }
        // The enum check alone is not the gate: `general` is a legal
        // ExplorationAgentType under every variant, so without the variant
        // check a briefer can open a stray sealed `general` summary on a
        // TEAM-variant prompt, and explore_get returns it as the clarifier's
        // input. The variant is resolved IN-TRANSACTION.
        // NO ACTIVE WORKFLOW FALLS THROUGH PERMISSIVELY, deliberately: a
        // /gm_task run and an adopted prompt carry no variant and must not be
        // stranded, and migrated prompts hold synthesis-only rows.
        if let workflow = try BotWorkflowRepository(db: db, core: core)
            .fetchActive(promptUuid: promptUuid),
            let variant = BotVariant(rawValue: workflow.variant)
        {
            // `.synthesis` is legal under every variant — it is the
            // prompt-level seal, not a methodology.
            let allowed = WorkflowSpec.expectedExplorationAgents(for: variant) + [.synthesis]
            guard allowed.contains(agent) else {
                throw StoreError.badRequest(
                    detail: "exploration agent type '\(agentType)' is not part of the "
                        + "\(variant.rawValue) workflow on prompt \(promptUuid) — expected one "
                        + "of \(allowed.map(\.rawValue).joined(separator: "|")). A summary "
                        + "outside the variant's agent set is read back by explore get as if "
                        + "it belonged to the run."
                )
            }
        }
        if let existing =
            try Self.newestFirst
            .filter(ExplorationSummaryRecord.Columns.promptUuid == promptUuid)
            .filter(ExplorationSummaryRecord.Columns.agentType == agentType)
            .select(ExplorationSummaryRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "exploration_summary",
            extra: [
                "prompt_uuid": promptUuid,
                "agent_type": agentType,
                "agent_id": agentId,
                "status": ExplorationStatus.exploring.rawValue,
                "overview": "",
            ]
        )
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "open", "prompt_uuid": promptUuid, "agent_type": agentType,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: promptUuid)
        return (uuid, true)
    }

    // MARK: - Verbs

    /// Opens an exploration summary, creating one if needed.
    ///
    /// - Parameter req: The open request.
    /// - Returns: The opened summary and creation status.
    /// - Throws: `StoreError` on prompt, agent type, or workflow variant errors.
    func open(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        let agentType = req.agentType ?? ExplorationAgentType.general.rawValue
        let (uuid, created) = try ensureSummary(
            promptUuid: req.promptUuid,
            agentType: agentType,
            agentId: req.agentId
        )
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        return ExploreSummaryResponse(summary: summary, created: created)
    }

    /// Adds a key file to an exploration summary.
    ///
    /// Key files are findings of kind `key_file` since m0025. A duplicate path
    /// is an idempotent upsert-ignore returning the existing row (dedupe is a Swift
    /// guard, not a UNIQUE constraint; ordinary findings may repeat paths).
    ///
    /// - Parameter req: The key file add request.
    /// - Returns: The added key file and creation status.
    /// - Throws: `StoreError` on summary not found, invalid status, or path normalization error.
    func keyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid,
            at: .exploring,
            verb: "key-file-add"
        )
        let path = try Store.normalizeRepoRelativePath(
            req.filePath,
            repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid)
        )
        if let existing = try fetchFindings(
            matching: ExplorationFindingRecord.Columns.explorationSummaryUuid == req.summaryUuid
                && ExplorationFindingRecord.Columns.kind == ExplorationFindingKind.keyFile.rawValue
                && ExplorationFindingRecord.Columns.filePath == path
        )
        .first {
            return ExploreKeyFileAddResponse(keyFile: keyFileView(existing), created: false)
        }
        let uuid = try core.insertBase(
            db,
            table: "exploration_finding",
            extra: [
                "exploration_summary_uuid": req.summaryUuid,
                "kind": ExplorationFindingKind.keyFile.rawValue,
                "title": path,
                "body": "",
                "file_path": path,
                "agent_name": summary.agentType,
                "agent_id": summary.agentId,
            ]
        )
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "key_file_add", "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard
            let row = try fetchFindings(matching: ExplorationFindingRecord.Columns.uuid == uuid)
                .first
        else {
            throw StoreError.notFound(entity: "exploration_finding", key: uuid)
        }
        return ExploreKeyFileAddResponse(keyFile: keyFileView(row), created: true)
    }

    /// Adds a finding to an exploration summary.
    ///
    /// - Parameter req: The finding add request.
    /// - Returns: The added finding.
    /// - Throws: `StoreError` on summary not found, invalid status, or validation error.
    func findingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid,
            at: .exploring,
            verb: "finding-add"
        )
        let (title, body, agentName) = try Store.validatedFindingText(
            title: req.title,
            body: req.body,
            agentName: req.agentName,
            allowEmptyBody: req.kind == .keyFile
        )
        try Store.validateRating(req.rating)
        var path: String?
        if let raw = req.filePath, !raw.isEmpty {
            path = try Store.normalizeRepoRelativePath(
                raw,
                repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid)
            )
        }
        let uuid = try core.insertBase(
            db,
            table: "exploration_finding",
            extra: [
                "exploration_summary_uuid": req.summaryUuid,
                "kind": req.kind.rawValue,
                "title": title,
                "body": body,
                "file_path": path,
                "agent_name": agentName,
                "agent_id": req.agentId,
                "finding_rating": req.rating,
            ]
        )
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "finding_add", "kind": req.kind.rawValue,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard
            let row = try fetchFindings(matching: ExplorationFindingRecord.Columns.uuid == uuid)
                .first
        else {
            throw StoreError.notFound(entity: "exploration_finding", key: uuid)
        }
        return ExploreFindingRowResponse(finding: row)
    }

    /// Ranks findings across all summaries of a prompt.
    ///
    /// Batch rank: atomic all-or-nothing, deliberately version-less, prompt-scoped since m0025.
    /// One calibrated batch across every summary (cross-persona duplicate collapse needs the whole set).
    /// Refused once the synthesis row is complete — ranking a sealed set would shift the sub-100 contract;
    /// reopen the synthesis first.
    ///
    /// - Parameter req: The rank request with ratings.
    /// - Returns: The number of updated findings and remaining unranked count.
    /// - Throws: `StoreError` on prompt not found or synthesis complete.
    func rank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        if let synthesis = try fetchSummary(
            byPrompt: req.promptUuid,
            agentType: ExplorationAgentType.synthesis.rawValue
        ),
            synthesis.explorationStatus == .complete
        {
            throw StoreError.invalidEntityTransition(
                entity: "exploration",
                from: synthesis.status,
                to: "rank",
                reason: "the synthesis summary is complete — EXPLORE_REOPEN it before re-ranking"
            )
        }
        try findingRank.applyPromptRankBatch(promptUuid: req.promptUuid, ratings: req.ratings)
        let unranked = try findingRank.promptUnrankedCount(promptUuid: req.promptUuid)
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: req.promptUuid,
            payload: Store.jsonPayload([
                "action": "rank", "count": req.ratings.count,
                "prompt_uuid": req.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: req.promptUuid)
        return ExploreRankResponse(
            promptUuid: req.promptUuid,
            updatedCount: req.ratings.count,
            unrankedCount: unranked
        )
    }

    /// Seals an exploration summary as complete.
    ///
    /// An agent seals its own summary with just the overview; the `synthesis`
    /// summary is the prompt-level seal—it alone carries the unranked-findings gate
    /// (promoted from the old per-summary complete).
    ///
    /// - Parameter req: The complete request with expected version and overview.
    /// - Returns: The completed summary.
    /// - Throws: `StoreError` on summary not found, invalid status, or unranked findings.
    func complete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .exploring, verb: "complete")
        if summary.agentType == ExplorationAgentType.synthesis.rawValue {
            let unranked = try findingRank.promptUnrankedCount(promptUuid: summary.promptUuid)
            guard unranked == 0 else {
                throw StoreError.invalidEntityTransition(
                    entity: "exploration",
                    from: summary.status,
                    to: ExplorationStatus.complete.rawValue,
                    reason: "\(unranked) finding(s) unranked across the prompt — run "
                        + "\(CdeToolSpec.qualifiedName("cde_rpir_explore")) op rank first"
                )
            }
        }
        let overview = try Store.validatedOverview(req.overview, entity: "exploration")
        try core.updateBase(
            db,
            table: "exploration_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.complete.rawValue, "overview": overview]
        )
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "complete", "prompt_uuid": summary.promptUuid,
                "agent_type": summary.agentType,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    /// Reopens a completed exploration summary for editing.
    ///
    /// Transitions from complete to exploring. Preserves all findings, ratings, and
    /// overview (nulling would make a mistaken reopen unrecoverable in an append-only db);
    /// the next complete must re-carry the overview.
    ///
    /// - Parameter req: The reopen request with expected version.
    /// - Returns: The reopened summary.
    /// - Throws: `StoreError` on summary not found or invalid status.
    func reopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        guard summary.explorationStatus == .complete else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration",
                from: summary.status,
                to: ExplorationStatus.exploring.rawValue,
                reason: "reopen runs from complete — this summary is \(summary.status)"
            )
        }
        try core.updateBase(
            db,
            table: "exploration_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.exploring.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .explorationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "reopen", "prompt_uuid": summary.promptUuid])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    /// Fetches exploration data for a prompt.
    ///
    /// - Parameter req: The get request with optional agent type and rating filters.
    /// - Returns: Summaries, key files, findings, and stubs filtered by rating window.
    /// - Throws: `StoreError` on prompt not found or no summaries found.
    func get(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        var request = Self.synthesisFirst
            .filter(ExplorationSummaryRecord.Columns.promptUuid == req.promptUuid)
        if let agentType = req.agentType {
            request = request.filter(ExplorationSummaryRecord.Columns.agentType == agentType)
        }
        let summaries = try request.fetchAll(db).map { $0.dto() }
        guard !summaries.isEmpty else {
            throw StoreError.summaryAbsent(
                entity: "exploration",
                promptUuid: req.promptUuid
            )
        }
        let summaryUuids = summaries.map(\.uuid)
        let all = try fetchFindings(
            matching:
                summaryUuids
                .contains(ExplorationFindingRecord.Columns.explorationSummaryUuid)
        )
        let window = try Store.ratingWindow(full: req.full, min: req.ratingMin, max: req.ratingMax)
        var keyFiles: [ExplorationKeyFileRow] = []
        var full: [ExplorationFindingRow] = []
        var stubs: [ExplorationFindingStub] = []
        for row in all {
            if row.kind == ExplorationFindingKind.keyFile.rawValue {
                keyFiles.append(keyFileView(row))
                continue
            }
            if Store.ratingInWindow(row.findingRating, window: window) {
                full.append(row)
            } else {
                stubs.append(
                    ExplorationFindingStub(
                        uuid: row.uuid,
                        kind: row.kind,
                        title: row.title,
                        findingRating: row.findingRating,
                        agentName: row.agentName
                    )
                )
            }
        }
        keyFiles.sort { ($0.filePath, $0.uuid) < ($1.filePath, $1.uuid) }
        return ExploreGetResponse(
            summaries: summaries,
            keyFiles: keyFiles,
            findings: full,
            findingStubs: stubs
        )
    }

    // MARK: - Transition + fetch helpers

    /// Extracts a key file view from a key_file finding.
    ///
    /// Computes the stable key-file wire surface from a `kind='key_file'` finding
    /// since m0025.
    ///
    /// - Parameter finding: The exploration finding row.
    /// - Returns: The key file view.
    private func keyFileView(_ finding: ExplorationFindingRow) -> ExplorationKeyFileRow {
        ExplorationKeyFileRow(
            uuid: finding.uuid,
            version: finding.version,
            explorationSummaryUuid: finding.explorationSummaryUuid,
            filePath: finding.filePath ?? finding.title
        )
    }

    /// Fetches a summary and asserts it has a required status.
    ///
    /// - Parameters:
    ///   - uuid: The summary identifier.
    ///   - required: The expected status.
    ///   - verb: The operation name for error messages.
    /// - Returns: The summary row.
    /// - Throws: `StoreError.notFound` if not found, or `invalidEntityTransition` if status doesn't match.
    private func requireSummary(
        uuid: String,
        at required: ExplorationStatus,
        verb: String
    ) throws -> ExplorationSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        guard summary.explorationStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration",
                from: summary.status,
                to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)"
            )
        }
        return summary
    }

    /// exploration_summary newest first — the create-or-return and the
    /// (prompt, agent type) point fetch both take the most recent row.
    private static var newestFirst: QueryInterfaceRequest<ExplorationSummaryRecord> {
        ExplorationSummaryRecord
            .all()
            .order(ExplorationSummaryRecord.Columns.createdAt.desc, Column("id").desc)
    }

    /// The render order: the synthesis seal row leads, then alphabetical.
    private static var synthesisFirst: QueryInterfaceRequest<ExplorationSummaryRecord> {
        ExplorationSummaryRecord
            .all()
            .order(
                ExplorationSummaryRecord.Columns.agentType
                    != ExplorationAgentType.synthesis.rawValue,
                ExplorationSummaryRecord.Columns.agentType
            )
    }

    /// Fetches a summary by UUID.
    ///
    /// - Parameter uuid: The summary identifier.
    /// - Returns: The summary row, or nil if not found.
    /// - Throws: Database errors.
    func fetchSummary(uuid: String) throws -> ExplorationSummaryRow? {
        try ExplorationSummaryRecord.all().withUuid(uuid).fetchOne(db)?.dto()
    }

    /// Fetches the most recent summary for a prompt and agent type.
    ///
    /// - Parameters:
    ///   - promptUuid: The prompt identifier.
    ///   - agentType: The exploration agent type.
    /// - Returns: The most recent summary row, or nil if not found.
    /// - Throws: Database errors.
    func fetchSummary(byPrompt promptUuid: String, agentType: String) throws -> ExplorationSummaryRow? {
        try Self.newestFirst
            .filter(ExplorationSummaryRecord.Columns.promptUuid == promptUuid)
            .filter(ExplorationSummaryRecord.Columns.agentType == agentType)
            .fetchOne(db)?
            .dto()
    }

    /// Fetches all summaries for a prompt in render order.
    ///
    /// Synthesis summary leads, then alphabetical by agent type.
    ///
    /// - Parameter promptUuid: The prompt identifier.
    /// - Returns: An array of summary rows in render order.
    /// - Throws: Database errors.
    func fetchSummaries(byPrompt promptUuid: String) throws -> [ExplorationSummaryRow] {
        try Self.synthesisFirst
            .filter(ExplorationSummaryRecord.Columns.promptUuid == promptUuid)
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches findings matching a predicate in priority order.
    ///
    /// Unranked (NULL rating) rows sort first (resume work-queue can't be missed),
    /// then by rating ascending, then by id.
    ///
    /// - Parameter predicate: Filter expression for findings.
    /// - Returns: An array of finding rows in priority order.
    /// - Throws: Database errors.
    private func fetchFindings(matching predicate: SQLExpression) throws -> [ExplorationFindingRow] {
        try ExplorationFindingRecord
            .all()
            .filter(predicate)
            .order(
                ExplorationFindingRecord.Columns.findingRating != nil,
                ExplorationFindingRecord.Columns.findingRating,
                Column("id")
            )
            .fetchAll(db)
            .map { $0.dto() }
    }
}
