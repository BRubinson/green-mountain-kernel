import Foundation
import GRDB

/// BOT_* / PROMPT_START / PROMPT_RESUME data access — the daemon-held
/// workflow state machine (m0025). Runs INSIDE a Store-owned transaction.
///
/// The row is deliberately thin: variant + status + claim + observability.
/// The CURRENT PHASE IS DERIVED from db evidence on every NEXT — there is
/// no stored cursor to drift, so resume is literally the first-run code
/// path. Gates that move the PROMPT still go through PROMPT_SET_STATUS
/// (the single door); NEXT only reports and refuses.
struct BotWorkflowRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Verbs

    /// Enter the machine from `draft`: creates the active workflow row and
    /// claims the prompt activation for the calling instance. No status
    /// change — the briefing/explore phases run while the prompt is draft,
    /// exactly as the manual flow always has.
    func start(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        let prompt = try PromptRecord.require(db, uuid: req.promptUuid)
        guard prompt.status == "draft" else {
            throw StoreError.invalidEntityTransition(
                entity: "bot_workflow",
                from: prompt.status,
                to: "start",
                reason: "PROMPT_START runs on a draft prompt — use PROMPT_RESUME"
            )
        }
        if try fetchActive(promptUuid: req.promptUuid) != nil {
            throw StoreError.badRequest(
                detail: "prompt \(req.promptUuid) already has an active workflow — PROMPT_RESUME it"
            )
        }
        let sessionUuid = prompt.sessionUuid
        // Moving to a new prompt releases the caller's previous hold —
        // without this, the partial UNIQUE(client_key) WHERE active turns
        // the mainline abandon-A-start-B flow into a raw constraint failure.
        if let clientKey = req.clientKey {
            try releaseClientClaim(clientKey: clientKey, except: nil)
        }
        let uuid = try core.insertBase(
            db,
            table: "bot_workflow",
            extra: [
                "session_uuid": sessionUuid,
                "prompt_uuid": req.promptUuid,
                "variant": req.variant.rawValue,
                "status": "active",
                "client_key": req.clientKey,
            ]
        )
        if let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core)
                .claimActivation(
                    sessionUuid: sessionUuid,
                    promptUuid: req.promptUuid,
                    clientKey: clientKey
                )
        }
        try core.appendEvent(
            db,
            kind: .workflowChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "start", "variant": req.variant.rawValue,
                "prompt_uuid": req.promptUuid,
            ])
        )
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "bot_workflow", key: uuid)
        }
        return BotWorkflowResponse(workflow: row, created: true)
    }

    /// Adopt whatever evidence exists: fetch-or-create, re-stamp the client
    /// key, change nothing else. Phase is recomputed at every NEXT.
    func resume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        let prompt = try PromptRecord.require(db, uuid: req.promptUuid)
        // A done prompt is finished work: new work = a new prompt. Without
        // this guard resume would mint a second, permanently-unclosable
        // active workflow on a closed prompt.
        guard prompt.status != "done" else {
            throw StoreError.invalidEntityTransition(
                entity: "bot_workflow",
                from: "done",
                to: "resume",
                reason: "prompt is done — its workflow is closed; new work is a new prompt"
            )
        }
        let sessionUuid = prompt.sessionUuid
        if let existing = try fetchActive(promptUuid: req.promptUuid) {
            // Steal the claim honestly: a different instance resuming a
            // stranded run is the normal recovery path.
            if let clientKey = req.clientKey, clientKey != existing.clientKey {
                try releaseClientClaim(clientKey: clientKey, except: existing.uuid)
                try core.updateBase(
                    db,
                    table: "bot_workflow",
                    uuid: existing.uuid,
                    expectedVersion: existing.version,
                    set: ["client_key": clientKey]
                )
                try SessionRepository(db: db, core: core)
                    .claimActivation(
                        sessionUuid: sessionUuid,
                        promptUuid: req.promptUuid,
                        clientKey: clientKey
                    )
            }
            guard let row = try fetchRow(uuid: existing.uuid) else {
                throw StoreError.notFound(entity: "bot_workflow", key: existing.uuid)
            }
            return BotWorkflowResponse(workflow: row, created: false)
        }
        guard let variant = req.variant else {
            throw StoreError.badRequest(
                detail: "prompt \(req.promptUuid) has no workflow — pass --variant bot|rpi|team to adopt it"
            )
        }
        if let clientKey = req.clientKey {
            try releaseClientClaim(clientKey: clientKey, except: nil)
        }
        let uuid = try core.insertBase(
            db,
            table: "bot_workflow",
            extra: [
                "session_uuid": sessionUuid,
                "prompt_uuid": req.promptUuid,
                "variant": variant.rawValue,
                "status": "active",
                "client_key": req.clientKey,
            ]
        )
        if let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core)
                .claimActivation(
                    sessionUuid: sessionUuid,
                    promptUuid: req.promptUuid,
                    clientKey: clientKey
                )
        }
        try core.appendEvent(
            db,
            kind: .workflowChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "resume_create", "variant": variant.rawValue,
                "prompt_uuid": req.promptUuid,
            ])
        )
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "bot_workflow", key: uuid)
        }
        return BotWorkflowResponse(workflow: row, created: true)
    }

    /// The machine's read: derive the current phase, serve its instructions
    /// + uuid bundle, and note what still blocks the next phase.
    /// last_served_phase is stamped for observability only.
    func next(_ req: BotNextRequest) throws -> BotNextResponse {
        let workflow = try resolve(
            promptUuid: req.promptUuid,
            clientKey: req.clientKey,
            sessionUuid: req.sessionUuid
        )
        guard let variant = BotVariant(rawValue: workflow.variant) else {
            throw StoreError.corruptState(
                entity: "bot_workflow",
                detail: "variant '\(workflow.variant)'"
            )
        }
        let (current, blockers) = try derivePhase(
            workflow: workflow,
            variant: variant,
            includeAdvisory: true
        )
        if workflow.lastServedPhase != current.rawValue {
            try core.updateBase(
                db,
                table: "bot_workflow",
                uuid: workflow.uuid,
                expectedVersion: workflow.version,
                set: ["last_served_phase": current.rawValue]
            )
            try core.appendEvent(
                db,
                kind: .workflowChange,
                subjectUuid: workflow.uuid,
                payload: Store.jsonPayload([
                    "action": "phase", "phase": current.rawValue,
                    "prompt_uuid": workflow.promptUuid,
                ])
            )
        }
        guard let updated = try fetchRow(uuid: workflow.uuid) else {
            throw StoreError.notFound(entity: "bot_workflow", key: workflow.uuid)
        }
        return BotNextResponse(
            workflow: updated,
            phase: current.rawValue,
            instructions: WorkflowSpec.instructions(variant: variant, phase: current),
            gateBlockers: blockers,
            uuids: try phaseUuids(workflow: updated)
        )
    }

    func get(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        let workflow = try resolve(
            promptUuid: req.promptUuid,
            clientKey: req.clientKey,
            sessionUuid: req.sessionUuid
        )
        return BotWorkflowResponse(workflow: workflow)
    }

    /// The derivation: the FURTHEST phase whose entry gate passes wins, walked
    /// from the back so evidence need not be monotonic. An adopted prompt can
    /// carry architecture evidence while failing the per-agent exploration gate,
    /// which a forward walk would strand at explore. Reported blockers are the
    /// NEXT phase's unmet gate.
    /// `includeAdvisory` defaults OFF because this is also on
    /// `FileChangeRepository.add`'s hot path, where one sweep would pay the
    /// advisory SQL per row and discard the blockers. BOT_NEXT opts in.
    func derivePhase(
        workflow: BotWorkflowRow,
        variant: BotVariant,
        includeAdvisory: Bool = false
    ) throws -> (WorkflowSpec.Phase, [String]) {
        let phases = WorkflowSpec.phases(for: variant)
        var current = phases[0]
        for phase in phases.reversed() {
            let unmet = try entryBlockers(phase: phase, workflow: workflow, variant: variant)
            if unmet.isEmpty {
                current = phase
                break
            }
        }
        var blockers: [String] = []
        if let index = phases.firstIndex(of: current), index + 1 < phases.count {
            blockers = try entryBlockers(
                phase: phases[index + 1],
                workflow: workflow,
                variant: variant
            )
        }
        if includeAdvisory {
            blockers += try advisoryBlockers(current: current, promptUuid: workflow.promptUuid)
        }
        return (current, blockers)
    }

    /// The phase-EXIT contracts in WorkflowGates, reported and never enforced.
    /// Appended to derivePhase's reporting half AFTER `current` is fixed;
    /// `entryBlockers` must stay untouched, because an entry blocker on `.done`
    /// would derive an already-done prompt with open findings backwards to
    /// `.reviewFix`. Read WorkflowGates' header before moving these.
    /// Evaluated only for the two phases whose exit they describe, and status
    /// scoped on top of that, which suppresses false advisories on closed
    /// prompts. That scoping is not what makes derivation safe.
    private func advisoryBlockers(
        current: WorkflowSpec.Phase,
        promptUuid: String
    ) throws -> [String] {
        guard current == .implement || current == .reviewFix else { return [] }
        let status = try promptStatus(promptUuid: promptUuid)
        let unmet: [String]
        switch current {
        // m0028: `implementing` is gone, so the scoping that suppressed this
        // advisory on closed and historical prompts is now "started but not
        // finished". Same intent, three-state vocabulary.
        case .implement where status == "initiated":
            unmet = try WorkflowGates.implementExitUnmet(db, promptUuid: promptUuid)
        case .reviewFix where status != "done":
            unmet = try WorkflowGates.reviewFixExitUnmet(db, promptUuid: promptUuid)
        default:
            unmet = []
        }
        return unmet.map { "advisory: \($0)" }
    }

    /// set-status done closes the workflow (called by PromptRepository).
    func closeForPrompt(promptUuid: String) throws {
        guard let workflow = try fetchActive(promptUuid: promptUuid) else { return }
        try core.updateBase(
            db,
            table: "bot_workflow",
            uuid: workflow.uuid,
            expectedVersion: workflow.version,
            set: ["status": "done"]
        )
        try core.appendEvent(
            db,
            kind: .workflowChange,
            subjectUuid: workflow.uuid,
            payload: Store.jsonPayload(["action": "done", "prompt_uuid": promptUuid])
        )
    }

    // MARK: - Phase derivation

    /// Empty = the phase's entry gate is satisfied.
    private func entryBlockers(
        phase: WorkflowSpec.Phase,
        workflow: BotWorkflowRow,
        variant: BotVariant
    ) throws -> [String] {
        let promptUuid = workflow.promptUuid
        switch phase {
        case .briefing:
            return []
        case .explore:
            let ready =
                try AgentBriefingRecord
                .filter(AgentBriefingRecord.Columns.promptUuid == promptUuid)
                .filter(AgentBriefingRecord.Columns.briefingForStep == "initial")
                .filter(AgentBriefingRecord.Columns.status == "ready")
                .fetchCount(db) > 0
            return ready ? [] : ["initial briefing not ready"]
        case .clarifyOpen:
            var unmet: [String] = []
            for agent in WorkflowSpec.expectedExplorationAgents(for: variant) {
                if try explorationComplete(promptUuid: promptUuid, agentType: agent.rawValue) == false {
                    unmet.append("exploration summary '\(agent.rawValue)' incomplete")
                }
            }
            if try explorationComplete(promptUuid: promptUuid, agentType: "synthesis") == false {
                unmet.append("synthesis summary (the prompt-level seal) incomplete")
            }
            return unmet
        case .clarifyUser:
            let status = try clarificationStatus(promptUuid: promptUuid)
            return status == "answering" || status == "complete"
                ? [] : ["clarification suite not sealed (status: \(status ?? "absent"))"]
        case .carePackage:
            guard let status = try clarificationStatus(promptUuid: promptUuid),
                status == "answering" || status == "complete"
            else {
                return ["clarification suite not sealed"]
            }
            let open =
                try UserClarificationQuestionRecord
                .filter(UserClarificationQuestionRecord.Columns.status == "open")
                .joining(
                    required: UserClarificationQuestionRecord.summary
                        .filter(ClarificationSummaryRecord.Columns.promptUuid == promptUuid)
                )
                .fetchCount(db)
            return open == 0 ? [] : ["\(open) question(s) still open"]
        case .archOptions, .architecture:
            if phase == .architecture && variant == .team {
                let options =
                    try ArchitectureOptionRecord
                    .joining(
                        required: ArchitectureOptionRecord.summary
                            .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
                    )
                    .fetchCount(db)
                return options > 0 ? [] : ["no architecture options written yet"]
            }
            let clarifyDone = try clarificationStatus(promptUuid: promptUuid) == "complete"
            let promptStatus = try promptStatus(promptUuid: promptUuid)
            var unmet: [String] = []
            if !clarifyDone { unmet.append("clarification not finalized") }
            if promptStatus == "draft" || promptStatus == "clarifying" {
                unmet.append("prompt not yet architecting (\(CdeToolSpec.qualifiedName("cde_prompt")) op set_status)")
            }
            return unmet
        case .planGate:
            let body =
                try ArchitectureSummaryRecord
                .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
                .select(ArchitectureSummaryRecord.Columns.body, as: String.self)
                .fetchOne(db) ?? ""
            return body.isEmpty ? ["architecture summary body not written"] : []
        case .implement:
            // ARCHITECTURE APPROVAL IS THE WHOLE GATE. Derivation reads no
            // prompt status here: with three states, "initiated" means only
            // that the prompt started, which every prompt reaching this phase
            // necessarily did, so a status condition would be true whenever the
            // phase is reachable. The rule being enforced is that a human
            // approved the plan before anyone writes code, and the approval
            // check below says exactly that without a weaker second proxy.
            let approved =
                try ArchitectureSummaryRecord
                .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
                .filter(ArchitectureSummaryRecord.Columns.status == "approved")
                .fetchCount(db) > 0
            return approved ? [] : ["architecture not approved"]
        case .review:
            let opened =
                try ReviewSummaryRecord
                .filter(ReviewSummaryRecord.Columns.promptUuid == promptUuid)
                .fetchCount(db) > 0
            return opened ? [] : ["review summary not opened"]
        case .reviewFix:
            let complete =
                try ReviewSummaryRecord
                .filter(ReviewSummaryRecord.Columns.promptUuid == promptUuid)
                .filter(ReviewSummaryRecord.Columns.status == "complete")
                .fetchCount(db) > 0
            return complete ? [] : ["review not complete"]
        case .done:
            return try promptStatus(promptUuid: promptUuid) == "done"
                ? [] : ["prompt not done (\(CdeToolSpec.qualifiedName("cde_prompt")) op set_status status: done)"]
        }
    }

    private func phaseUuids(workflow: BotWorkflowRow) throws -> BotPhaseUuids {
        let promptUuid = workflow.promptUuid
        let briefing = try newestUuid(
            AgentBriefingRecord
                .filter(AgentBriefingRecord.Columns.promptUuid == promptUuid)
                .filter(AgentBriefingRecord.Columns.briefingForStep == "initial")
        )
        let clarification = try newestUuid(
            ClarificationSummaryRecord
                .filter(ClarificationSummaryRecord.Columns.promptUuid == promptUuid)
        )
        var package: String?
        if let clarification {
            package = try newestUuid(
                CarePackageRecord
                    .filter(CarePackageRecord.Columns.clarificationSummaryUuid == clarification)
            )
        }
        let architecture = try newestUuid(
            ArchitectureSummaryRecord
                .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
        )
        let review = try newestUuid(
            ReviewSummaryRecord
                .filter(ReviewSummaryRecord.Columns.promptUuid == promptUuid)
        )
        var exploration: [String: String] = [:]
        // Ascending so the dictionary's last-write-wins lands on the newest
        // summary per agent_type.
        for summary
            in try ExplorationSummaryRecord
            .filter(ExplorationSummaryRecord.Columns.promptUuid == promptUuid)
            .order(Column("created_at"), Column("id"))
            .fetchAll(db)
        {
            exploration[summary.agentType] = summary.uuid
        }
        return BotPhaseUuids(
            promptUuid: promptUuid,
            sessionUuid: workflow.sessionUuid,
            briefingUuid: briefing,
            clarificationSummaryUuid: clarification,
            carePackageUuid: package,
            architectureSummaryUuid: architecture,
            reviewSummaryUuid: review,
            explorationSummaryUuids: exploration
        )
    }

    private func explorationComplete(promptUuid: String, agentType: String) throws -> Bool {
        try ExplorationSummaryRecord
            .filter(ExplorationSummaryRecord.Columns.promptUuid == promptUuid)
            .filter(ExplorationSummaryRecord.Columns.agentType == agentType)
            .filter(ExplorationSummaryRecord.Columns.status == "complete")
            .fetchCount(db) > 0
    }

    /// Newest first by `created_at` then rowid — the tie-break every uuid
    /// lookup in this file reads with.
    private func newestUuid<T: BaseRecordFields>(
        _ request: QueryInterfaceRequest<T>
    ) throws -> String? {
        try request
            .order(Column("created_at").desc, Column("id").desc)
            .select(Column("uuid"), as: String.self)
            .fetchOne(db)
    }

    private func clarificationStatus(promptUuid: String) throws -> String? {
        try ClarificationSummaryRecord
            .filter(ClarificationSummaryRecord.Columns.promptUuid == promptUuid)
            .order(Column("created_at").desc, Column("id").desc)
            .select(ClarificationSummaryRecord.Columns.status, as: String.self)
            .fetchOne(db)
    }

    private func promptStatus(promptUuid: String) throws -> String? {
        try PromptRecord
            .all()
            .withUuid(promptUuid)
            .select(PromptRecord.Columns.status, as: String.self)
            .fetchOne(db)
    }

    // MARK: - Resolution + fetch

    /// Explicit prompt uuid → the caller's own active workflow (client key)
    /// → the activation-resolved prompt's workflow → the session's single
    /// active workflow. The task-tier shadowing hazard applies — every bot
    /// verb keeps an explicit prompt_uuid escape hatch. Read verbs fall
    /// back to the prompt's most recent CLOSED workflow so a completed run
    /// renders as done instead of erroring SUMMARY_ABSENT.
    private func resolve(
        promptUuid: String?,
        clientKey: String?,
        sessionUuid: String?
    ) throws -> BotWorkflowRow {
        if let promptUuid {
            if let row = try fetchActive(promptUuid: promptUuid) { return row }
            if let closed =
                try workflows
                .filter(BotWorkflowRecord.Columns.promptUuid == promptUuid)
                .fetchAll(db)
                .last
            {
                return closed.dto()
            }
            throw StoreError.summaryAbsent(entity: "bot_workflow", promptUuid: promptUuid)
        }
        if let clientKey,
            let row =
                try activeWorkflows
                .filter(BotWorkflowRecord.Columns.clientKey == clientKey)
                .fetchOne(db)
        {
            return row.dto()
        }
        if let sessionUuid {
            if let active = try SessionRepository(db: db, core: core)
                .resolveActivePrompt(
                    sessionUuid: sessionUuid,
                    clientKey: clientKey
                ),
                let row = try fetchActive(promptUuid: active)
            {
                return row
            }
            let rows =
                try activeWorkflows
                .filter(BotWorkflowRecord.Columns.sessionUuid == sessionUuid)
                .fetchAll(db)
            if rows.count == 1 { return rows[0].dto() }
            if rows.count > 1 {
                throw StoreError.badRequest(
                    detail: "session has \(rows.count) active workflows — pass prompt_uuid"
                )
            }
        }
        throw StoreError.badRequest(
            detail: "no workflow resolvable — pass prompt_uuid "
                + "(or start one with \(CdeToolSpec.qualifiedName("cde_init")) op run)"
        )
    }

    /// Every `bot_workflow` row, oldest first — the order every resolution
    /// path below reads in.
    private var workflows: QueryInterfaceRequest<BotWorkflowRecord> {
        BotWorkflowRecord.all().orderedByCreatedAt()
    }

    private var activeWorkflows: QueryInterfaceRequest<BotWorkflowRecord> {
        workflows.filter(BotWorkflowRecord.Columns.status == "active")
    }

    func fetchActive(promptUuid: String) throws -> BotWorkflowRow? {
        try activeWorkflows
            .filter(BotWorkflowRecord.Columns.promptUuid == promptUuid)
            .fetchOne(db)?
            .dto()
    }

    private func fetchRow(uuid: String) throws -> BotWorkflowRow? {
        try BotWorkflowRecord.fetch(db, uuid: uuid)?.dto()
    }

    /// The partial UNIQUE(client_key) WHERE active means one instance drives
    /// one workflow at a time: moving to a new prompt releases the old hold.
    private func releaseClientClaim(clientKey: String, except uuid: String?) throws {
        for row
            in try activeWorkflows
            .filter(BotWorkflowRecord.Columns.clientKey == clientKey)
            .fetchAll(db) where row.uuid != uuid
        {
            try core.updateBase(
                db,
                table: "bot_workflow",
                uuid: row.uuid,
                expectedVersion: row.version,
                set: ["client_key": nil]
            )
        }
    }
}
