import Foundation
import GRDB

/// EXPLORE_* data access — the db-native exploration report machine. Runs
/// INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. The shared rank/validation statics stay on Store (they
/// serve Store+Review too).
///
/// m0025 model: summaries are literal per-agent rows keyed
/// UNIQUE(prompt_uuid, agent_type). Each agent completes its OWN summary;
/// the `synthesis`-type row is the prompt-level seal — its complete refuses
/// while any finding across the prompt is unranked (the old per-summary
/// gate, promoted one level). Key files merged into findings (kind
/// 'key_file').
struct ExplorationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent per (prompt, agentType): returns the existing summary or
    /// creates one at `exploring`. Called ONLY by EXPLORE_OPEN — never by
    /// setPromptStatus (explicit-open only; prompt status has no exploration
    /// coupling).
    @discardableResult
    func ensureSummary(
        promptUuid: String, agentType: String, agentId: String?
    ) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        guard let agent = ExplorationAgentType(rawValue: agentType) else {
            throw StoreError.badRequest(
                detail: "unknown exploration agent type '\(agentType)' — one of "
                    + ExplorationAgentType.allCases.map(\.rawValue).joined(separator: "|"))
        }
        // The enum check ALONE used to be the whole gate, which is how a
        // doper opened a stray sealed `general` summary on a TEAM-variant
        // prompt: `general` is a legal ExplorationAgentType under every
        // variant, so nothing refused it — and a stray summary is returned by
        // explore_get, which is the clarifier's entire input. The variant is
        // the missing half, resolved IN-TRANSACTION (the pattern
        // FileChangeRepository.add already demonstrates).
        //
        // NO ACTIVE WORKFLOW FALLS THROUGH PERMISSIVELY, deliberately and not
        // by omission: a /gm_task run and an adopted pre-machine prompt carry
        // no variant and must not be stranded, and migrated prompts hold
        // synthesis-only rows and must stay reopenable.
        if let workflow = try BotWorkflowRepository(db: db, core: core)
               .fetchActive(promptUuid: promptUuid),
           let variant = BotVariant(rawValue: workflow.variant) {
            // `.synthesis` is legal under every variant — it is the
            // prompt-level seal, not a methodology.
            let allowed = WorkflowSpec.expectedExplorationAgents(for: variant) + [.synthesis]
            guard allowed.contains(agent) else {
                throw StoreError.badRequest(
                    detail: "exploration agent type '\(agentType)' is not part of the "
                        + "\(variant.rawValue) workflow on prompt \(promptUuid) — expected one "
                        + "of \(allowed.map(\.rawValue).joined(separator: "|")). A summary "
                        + "outside the variant's agent set is read back by explore get as if "
                        + "it belonged to the run.")
            }
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM exploration_summary WHERE prompt_uuid = ? AND agent_type = ?",
            arguments: [promptUuid, agentType]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "exploration_summary", extra: [
            "prompt_uuid": promptUuid,
            "agent_type": agentType,
            "agent_id": agentId,
            "status": ExplorationStatus.exploring.rawValue,
            "overview": "",
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "open", "prompt_uuid": promptUuid, "agent_type": agentType,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: promptUuid)
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        let agentType = req.agentType ?? ExplorationAgentType.general.rawValue
        let (uuid, created) = try ensureSummary(
            promptUuid: req.promptUuid, agentType: agentType, agentId: req.agentId)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        return ExploreSummaryResponse(summary: summary, created: created)
    }

    /// Key files are findings of kind 'key_file' since m0025. Still a shared
    /// deduped set per summary: a duplicate path is an idempotent
    /// upsert-ignore returning the existing row (the prompt_artifact
    /// precedent), never an error — the dedupe is a Swift guard now, not a
    /// UNIQUE (ordinary findings may repeat paths).
    func keyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid, at: .exploring, verb: "key-file-add")
        let path = try Store.normalizeRepoRelativePath(
            req.filePath, repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid))
        if let existing = try fetchFindings(
            where: "exploration_summary_uuid = ? AND kind = 'key_file' AND file_path = ?",
            arguments: [req.summaryUuid, path]
        ).first {
            return ExploreKeyFileAddResponse(keyFile: keyFileView(existing), created: false)
        }
        let uuid = try core.insertBase(db, table: "exploration_finding", extra: [
            "exploration_summary_uuid": req.summaryUuid,
            "kind": ExplorationFindingKind.keyFile.rawValue,
            "title": path,
            "body": "",
            "file_path": path,
            "agent_name": summary.agentType,
            "agent_id": summary.agentId,
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "key_file_add", "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchFindings(where: "uuid = ?", arguments: [uuid]).first else {
            throw StoreError.notFound(entity: "exploration_finding", key: uuid)
        }
        return ExploreKeyFileAddResponse(keyFile: keyFileView(row), created: true)
    }

    func findingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        let summary = try requireSummary(
            uuid: req.summaryUuid, at: .exploring, verb: "finding-add")
        let (title, body, agentName) = try Store.validatedFindingText(
            title: req.title, body: req.body, agentName: req.agentName,
            allowEmptyBody: req.kind == .keyFile)
        try Store.validateRating(req.rating)
        var path: String? = nil
        if let raw = req.filePath, !raw.isEmpty {
            path = try Store.normalizeRepoRelativePath(
                raw, repoRoot: try architecture.instanceRoot(promptUuid: summary.promptUuid))
        }
        let uuid = try core.insertBase(db, table: "exploration_finding", extra: [
            "exploration_summary_uuid": req.summaryUuid,
            "kind": req.kind.rawValue,
            "title": title,
            "body": body,
            "file_path": path,
            "agent_name": agentName,
            "agent_id": req.agentId,
            "finding_rating": req.rating,
        ])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "finding_add", "kind": req.kind.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchFindings(where: "uuid = ?", arguments: [uuid]).first else {
            throw StoreError.notFound(entity: "exploration_finding", key: uuid)
        }
        return ExploreFindingRowResponse(finding: row)
    }

    /// Batch rank — atomic all-or-nothing, deliberately version-less, and
    /// PROMPT-scoped since m0025: one calibrated batch across every summary
    /// of the prompt (cross-persona duplicate collapse needs the whole set).
    /// Refused once the synthesis row is complete — ranking a sealed set
    /// would shift the sub-100 contract; reopen the synthesis first.
    func rank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        if let synthesis = try fetchSummary(
            byPrompt: req.promptUuid, agentType: ExplorationAgentType.synthesis.rawValue),
            synthesis.explorationStatus == .complete {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: synthesis.status, to: "rank",
                reason: "the synthesis summary is complete — EXPLORE_REOPEN it before re-ranking")
        }
        try findingRank.applyPromptRankBatch(promptUuid: req.promptUuid, ratings: req.ratings)
        let unranked = try findingRank.promptUnrankedCount(promptUuid: req.promptUuid)
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.promptUuid,
            payload: Store.jsonPayload([
                "action": "rank", "count": req.ratings.count,
                "prompt_uuid": req.promptUuid,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: req.promptUuid)
        return ExploreRankResponse(
            promptUuid: req.promptUuid, updatedCount: req.ratings.count, unrankedCount: unranked)
    }

    /// exploring → complete, per summary. An agent seals its OWN summary with
    /// just the overview; the `synthesis` summary is the prompt-level seal —
    /// it alone carries the unranked-findings gate (promoted from the old
    /// per-summary complete).
    func complete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .exploring, verb: "complete")
        if summary.agentType == ExplorationAgentType.synthesis.rawValue {
            let unranked = try findingRank.promptUnrankedCount(promptUuid: summary.promptUuid)
            guard unranked == 0 else {
                throw StoreError.invalidEntityTransition(
                    entity: "exploration", from: summary.status,
                    to: ExplorationStatus.complete.rawValue,
                    reason: "\(unranked) finding(s) unranked across the prompt — run "
                        + "mcp__plugin_gmcc_pen__explore_rank first")
            }
        }
        let overview = try Store.validatedOverview(req.overview, entity: "exploration")
        try core.updateBase(
            db, table: "exploration_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.complete.rawValue, "overview": overview])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "complete", "prompt_uuid": summary.promptUuid,
                "agent_type": summary.agentType,
            ]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    /// complete → exploring: the revision edge. Preserves everything —
    /// findings, ratings, overview (nulling would make a mistaken reopen
    /// unrecoverable in an append-only db); the next COMPLETE must re-carry
    /// the overview, so staleness cannot survive a re-seal.
    func reopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        guard summary.explorationStatus == .complete else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: summary.status,
                to: ExplorationStatus.exploring.rawValue,
                reason: "reopen runs from complete — this summary is \(summary.status)")
        }
        try core.updateBase(
            db, table: "exploration_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ExplorationStatus.exploring.rawValue])
        try core.appendEvent(
            db, kind: .explorationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "reopen", "prompt_uuid": summary.promptUuid]))
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: req.summaryUuid)
        }
        return ExploreSummaryResponse(summary: updated)
    }

    func get(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        var condition = "prompt_uuid = ?"
        var args: StatementArguments = [req.promptUuid]
        if let agentType = req.agentType {
            condition += " AND agent_type = ?"
            _ = args.append(contentsOf: [agentType])
        }
        // synthesis first, then alphabetical — the seal row leads the render.
        let summaries = try ExplorationSummaryRecord.fetchAll(
            db, where: condition, arguments: args,
            orderBy: "agent_type != 'synthesis', agent_type"
        ).map { $0.wireRow() }
        guard !summaries.isEmpty else {
            throw StoreError.summaryAbsent(
                entity: "exploration", promptUuid: req.promptUuid)
        }
        let summaryUuids = summaries.map(\.uuid)
        let placeholders = summaryUuids.map { _ in "?" }.joined(separator: ",")
        let all = try fetchFindings(
            where: "exploration_summary_uuid IN (\(placeholders))",
            arguments: StatementArguments(summaryUuids))
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
                stubs.append(ExplorationFindingStub(
                    uuid: row.uuid, kind: row.kind, title: row.title,
                    findingRating: row.findingRating, agentName: row.agentName))
            }
        }
        keyFiles.sort { ($0.filePath, $0.uuid) < ($1.filePath, $1.uuid) }
        return ExploreGetResponse(
            summaries: summaries, keyFiles: keyFiles, findings: full, findingStubs: stubs)
    }

    // MARK: - Transition + fetch helpers

    /// The stable key-file wire surface, computed from a kind='key_file'
    /// finding since m0025.
    private func keyFileView(_ finding: ExplorationFindingRow) -> ExplorationKeyFileRow {
        ExplorationKeyFileRow(
            uuid: finding.uuid, version: finding.version,
            explorationSummaryUuid: finding.explorationSummaryUuid,
            filePath: finding.filePath ?? finding.title)
    }

    private func requireSummary(
        uuid: String, at required: ExplorationStatus, verb: String
    ) throws -> ExplorationSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "exploration_summary", key: uuid)
        }
        guard summary.explorationStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "exploration", from: summary.status, to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)")
        }
        return summary
    }

    func fetchSummary(uuid: String) throws -> ExplorationSummaryRow? {
        try ExplorationSummaryRecord.fetchAll(
            db, where: "uuid = ?", arguments: [uuid]
        ).first?.wireRow()
    }

    func fetchSummary(byPrompt promptUuid: String, agentType: String) throws -> ExplorationSummaryRow? {
        try ExplorationSummaryRecord.fetchAll(
            db, where: "prompt_uuid = ? AND agent_type = ?", arguments: [promptUuid, agentType]
        ).first?.wireRow()
    }

    func fetchSummaries(byPrompt promptUuid: String) throws -> [ExplorationSummaryRow] {
        try ExplorationSummaryRecord.fetchAll(
            db, where: "prompt_uuid = ?", arguments: [promptUuid],
            orderBy: "agent_type != 'synthesis', agent_type"
        ).map { $0.wireRow() }
    }

    /// Explicit ordering: unranked (NULL) rows sort FIRST — the resume
    /// work-queue can't be missed — then by rating ascending, then id.
    private func fetchFindings(
        where condition: String, arguments: StatementArguments
    ) throws -> [ExplorationFindingRow] {
        try ExplorationFindingRecord.fetchAll(
            db, where: condition, arguments: arguments,
            orderBy: "finding_rating IS NOT NULL, finding_rating, id"
        ).map { $0.wireRow() }
    }
}
