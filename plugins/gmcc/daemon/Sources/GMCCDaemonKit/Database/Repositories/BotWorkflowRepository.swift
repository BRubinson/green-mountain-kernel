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
        guard let prompt = try Row.fetchOne(
            db, sql: "SELECT session_uuid, status FROM prompt WHERE uuid = ?",
            arguments: [req.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        let status: String = prompt["status"]
        guard status == "draft" else {
            throw StoreError.invalidEntityTransition(
                entity: "bot_workflow", from: status, to: "start",
                reason: "PROMPT_START runs on a draft prompt — use PROMPT_RESUME")
        }
        if try fetchActive(promptUuid: req.promptUuid) != nil {
            throw StoreError.badRequest(
                detail: "prompt \(req.promptUuid) already has an active workflow — PROMPT_RESUME it")
        }
        let sessionUuid: String = prompt["session_uuid"]
        // Moving to a new prompt releases the caller's previous hold —
        // without this, the partial UNIQUE(client_key) WHERE active turns
        // the mainline abandon-A-start-B flow into a raw constraint failure.
        if let clientKey = req.clientKey {
            try releaseClientClaim(clientKey: clientKey, except: nil)
        }
        let uuid = try core.insertBase(db, table: "bot_workflow", extra: [
            "session_uuid": sessionUuid,
            "prompt_uuid": req.promptUuid,
            "variant": req.variant.rawValue,
            "status": "active",
            "client_key": req.clientKey,
        ])
        if let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core).claimActivation(
                sessionUuid: sessionUuid, promptUuid: req.promptUuid, clientKey: clientKey)
        }
        try core.appendEvent(
            db, kind: .workflowChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "start", "variant": req.variant.rawValue,
                "prompt_uuid": req.promptUuid,
            ]))
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "bot_workflow", key: uuid)
        }
        return BotWorkflowResponse(workflow: row, created: true)
    }

    /// Adopt whatever evidence exists: fetch-or-create, re-stamp the client
    /// key, change nothing else. Phase is recomputed at every NEXT.
    func resume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        guard let prompt = try Row.fetchOne(
            db, sql: "SELECT session_uuid, status FROM prompt WHERE uuid = ?",
            arguments: [req.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // A done prompt is finished work: new work = a new prompt. Without
        // this guard resume would mint a second, permanently-unclosable
        // active workflow on a closed prompt.
        let promptStatus: String = prompt["status"]
        guard promptStatus != "done" else {
            throw StoreError.invalidEntityTransition(
                entity: "bot_workflow", from: "done", to: "resume",
                reason: "prompt is done — its workflow is closed; new work is a new prompt")
        }
        let sessionUuid: String = prompt["session_uuid"]
        if let existing = try fetchActive(promptUuid: req.promptUuid) {
            // Steal the claim honestly: a different instance resuming a
            // stranded run is the normal recovery path.
            if let clientKey = req.clientKey, clientKey != existing.clientKey {
                try releaseClientClaim(clientKey: clientKey, except: existing.uuid)
                try core.updateBase(
                    db, table: "bot_workflow", uuid: existing.uuid,
                    expectedVersion: existing.version, set: ["client_key": clientKey])
                try SessionRepository(db: db, core: core).claimActivation(
                    sessionUuid: sessionUuid, promptUuid: req.promptUuid, clientKey: clientKey)
            }
            guard let row = try fetchRow(uuid: existing.uuid) else {
                throw StoreError.notFound(entity: "bot_workflow", key: existing.uuid)
            }
            return BotWorkflowResponse(workflow: row, created: false)
        }
        guard let variant = req.variant else {
            throw StoreError.badRequest(
                detail: "prompt \(req.promptUuid) has no workflow — pass --variant bot|rpi|team to adopt it")
        }
        if let clientKey = req.clientKey {
            try releaseClientClaim(clientKey: clientKey, except: nil)
        }
        let uuid = try core.insertBase(db, table: "bot_workflow", extra: [
            "session_uuid": sessionUuid,
            "prompt_uuid": req.promptUuid,
            "variant": variant.rawValue,
            "status": "active",
            "client_key": req.clientKey,
        ])
        if let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core).claimActivation(
                sessionUuid: sessionUuid, promptUuid: req.promptUuid, clientKey: clientKey)
        }
        try core.appendEvent(
            db, kind: .workflowChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "resume_create", "variant": variant.rawValue,
                "prompt_uuid": req.promptUuid,
            ]))
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
            promptUuid: req.promptUuid, clientKey: req.clientKey, sessionUuid: req.sessionUuid)
        guard let variant = BotVariant(rawValue: workflow.variant) else {
            throw StoreError.corruptState(
                entity: "bot_workflow", detail: "variant '\(workflow.variant)'")
        }
        let (current, blockers) = try derivePhase(
            workflow: workflow, variant: variant, includeAdvisory: true)
        if workflow.lastServedPhase != current.rawValue {
            try core.updateBase(
                db, table: "bot_workflow", uuid: workflow.uuid,
                expectedVersion: workflow.version,
                set: ["last_served_phase": current.rawValue])
            try core.appendEvent(
                db, kind: .workflowChange, subjectUuid: workflow.uuid,
                payload: Store.jsonPayload([
                    "action": "phase", "phase": current.rawValue,
                    "prompt_uuid": workflow.promptUuid,
                ]))
        }
        guard let updated = try fetchRow(uuid: workflow.uuid) else {
            throw StoreError.notFound(entity: "bot_workflow", key: workflow.uuid)
        }
        return BotNextResponse(
            workflow: updated,
            phase: current.rawValue,
            instructions: WorkflowSpec.instructions(variant: variant, phase: current),
            gateBlockers: blockers,
            uuids: try phaseUuids(workflow: updated))
    }

    func get(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        let workflow = try resolve(
            promptUuid: req.promptUuid, clientKey: req.clientKey, sessionUuid: req.sessionUuid)
        return BotWorkflowResponse(workflow: workflow)
    }

    /// The derivation: the FURTHEST phase whose entry gate passes wins —
    /// walked from the back so evidence need not be monotonic. Forward-walk
    /// stranded adopted pre-machine prompts at explore (their migrated
    /// synthesis-only exploration rows fail the per-agent gate even though
    /// architecture/implementation evidence exists). Blockers reported are
    /// the NEXT phase's unmet gate.
    ///
    /// `includeAdvisory` adds WorkflowGates' decision-7 advisories to the
    /// REPORTED blockers. It defaults OFF because this function is also on
    /// `FileChangeRepository.add`'s hot path — one sweep writes N rows and
    /// would otherwise pay the advisory SQL N times for a phase string it
    /// then throws the blockers away from. BOT_NEXT, the one caller that
    /// actually renders blockers, opts in.
    func derivePhase(
        workflow: BotWorkflowRow, variant: BotVariant, includeAdvisory: Bool = false
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
                phase: phases[index + 1], workflow: workflow, variant: variant)
        }
        if includeAdvisory {
            blockers += try advisoryBlockers(current: current, promptUuid: workflow.promptUuid)
        }
        return (current, blockers)
    }

    /// Decision 7's phase-EXIT contracts (WorkflowGates), reported and never
    /// enforced. Appended to the reporting half of derivePhase AFTER `current`
    /// is fixed — `entryBlockers` is deliberately untouched, because a new
    /// entry blocker on `.done` would make an already-done prompt with open
    /// sub-100 findings derive backwards to `.reviewFix` across ~116
    /// historical prompts. Read WorkflowGates' header before moving these.
    ///
    /// Evaluated only for the two phases whose exit they describe, and STATUS
    /// SCOPED on top of that: review's contract only while the prompt is
    /// actually implementing, done's only while the prompt is not already
    /// done. That scoping suppresses false advisories on closed and
    /// historical prompts; it is not what makes derivation safe.
    private func advisoryBlockers(
        current: WorkflowSpec.Phase, promptUuid: String
    ) throws -> [String] {
        guard current == .implement || current == .reviewFix else { return [] }
        let status = try promptStatus(promptUuid: promptUuid)
        let unmet: [String]
        switch current {
        case .implement where status == "implementing":
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
            db, table: "bot_workflow", uuid: workflow.uuid,
            expectedVersion: workflow.version, set: ["status": "done"])
        try core.appendEvent(
            db, kind: .workflowChange, subjectUuid: workflow.uuid,
            payload: Store.jsonPayload(["action": "done", "prompt_uuid": promptUuid]))
    }

    // MARK: - Phase derivation

    /// Empty = the phase's entry gate is satisfied.
    private func entryBlockers(
        phase: WorkflowSpec.Phase, workflow: BotWorkflowRow, variant: BotVariant
    ) throws -> [String] {
        let promptUuid = workflow.promptUuid
        switch phase {
        case .briefing:
            return []
        case .explore:
            let ready = try Row.fetchOne(db, sql: """
                SELECT 1 FROM agent_briefing
                WHERE prompt_uuid = ? AND briefing_for_step = 'initial' AND status = 'ready'
                """, arguments: [promptUuid]) != nil
            return ready ? [] : ["initial briefing not ready"]
        case .clarifyOpen:
            var unmet: [String] = []
            for agent in WorkflowSpec.expectedExplorationAgents(for: variant) {
                let complete = try Row.fetchOne(db, sql: """
                    SELECT 1 FROM exploration_summary
                    WHERE prompt_uuid = ? AND agent_type = ? AND status = 'complete'
                    """, arguments: [promptUuid, agent.rawValue]) != nil
                if !complete { unmet.append("exploration summary '\(agent.rawValue)' incomplete") }
            }
            let sealed = try Row.fetchOne(db, sql: """
                SELECT 1 FROM exploration_summary
                WHERE prompt_uuid = ? AND agent_type = 'synthesis' AND status = 'complete'
                """, arguments: [promptUuid]) != nil
            if !sealed { unmet.append("synthesis summary (the prompt-level seal) incomplete") }
            return unmet
        case .clarifyUser:
            let status = try clarificationStatus(promptUuid: promptUuid)
            return status == "answering" || status == "complete"
                ? [] : ["clarification suite not sealed (status: \(status ?? "absent"))"]
        case .carePackage:
            guard let status = try clarificationStatus(promptUuid: promptUuid),
                  status == "answering" || status == "complete" else {
                return ["clarification suite not sealed"]
            }
            let open = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM user_clarification_question q
                JOIN clarification_summary s ON s.uuid = q.clarification_summary_uuid
                WHERE s.prompt_uuid = ? AND q.status = 'open'
                """, arguments: [promptUuid]) ?? 0
            return open == 0 ? [] : ["\(open) question(s) still open"]
        case .archOptions, .architecture:
            if phase == .architecture && variant == .team {
                let options = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM architecture_option o
                    JOIN architecture_summary s ON s.uuid = o.architecture_summary_uuid
                    WHERE s.prompt_uuid = ?
                    """, arguments: [promptUuid]) ?? 0
                return options > 0 ? [] : ["no architecture options written yet"]
            }
            let clarifyDone = try clarificationStatus(promptUuid: promptUuid) == "complete"
            let promptStatus = try promptStatus(promptUuid: promptUuid)
            var unmet: [String] = []
            if !clarifyDone { unmet.append("clarification not finalized") }
            if promptStatus == "draft" || promptStatus == "clarifying" {
                unmet.append("prompt not yet architecting (mcp__plugin_gmcc_pen__prompt_set_status)")
            }
            return unmet
        case .planGate:
            let body = try String.fetchOne(db, sql: """
                SELECT body FROM architecture_summary WHERE prompt_uuid = ?
                """, arguments: [promptUuid]) ?? ""
            return body.isEmpty ? ["architecture summary body not written"] : []
        case .implement:
            let approved = try Row.fetchOne(db, sql: """
                SELECT 1 FROM architecture_summary
                WHERE prompt_uuid = ? AND status = 'approved'
                """, arguments: [promptUuid]) != nil
            let status = try promptStatus(promptUuid: promptUuid)
            var unmet: [String] = []
            if !approved { unmet.append("architecture not approved") }
            if status != "implementing" && status != "reviewing" && status != "done" {
                unmet.append("prompt not implementing (mcp__plugin_gmcc_pen__prompt_set_status)")
            }
            return unmet
        case .review:
            let opened = try Row.fetchOne(db, sql: """
                SELECT 1 FROM review_summary WHERE prompt_uuid = ?
                """, arguments: [promptUuid]) != nil
            return opened ? [] : ["review summary not opened"]
        case .reviewFix:
            let complete = try Row.fetchOne(db, sql: """
                SELECT 1 FROM review_summary WHERE prompt_uuid = ? AND status = 'complete'
                """, arguments: [promptUuid]) != nil
            return complete ? [] : ["review not complete"]
        case .done:
            return try promptStatus(promptUuid: promptUuid) == "done"
                ? [] : ["prompt not done (mcp__plugin_gmcc_pen__prompt_set_status status: done)"]
        }
    }

    private func phaseUuids(workflow: BotWorkflowRow) throws -> BotPhaseUuids {
        let promptUuid = workflow.promptUuid
        let briefing = try String.fetchOne(db, sql: """
            SELECT uuid FROM agent_briefing
            WHERE prompt_uuid = ? AND briefing_for_step = 'initial'
            """, arguments: [promptUuid])
        let clarification = try String.fetchOne(
            db, sql: "SELECT uuid FROM clarification_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid])
        var package: String?
        if let clarification {
            package = try String.fetchOne(
                db, sql: "SELECT uuid FROM care_package WHERE clarification_summary_uuid = ?",
                arguments: [clarification])
        }
        let architecture = try String.fetchOne(
            db, sql: "SELECT uuid FROM architecture_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid])
        let review = try String.fetchOne(
            db, sql: "SELECT uuid FROM review_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid])
        var exploration: [String: String] = [:]
        for row in try Row.fetchAll(
            db, sql: "SELECT agent_type, uuid FROM exploration_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            exploration[row["agent_type"]] = row["uuid"]
        }
        return BotPhaseUuids(
            promptUuid: promptUuid,
            sessionUuid: workflow.sessionUuid,
            briefingUuid: briefing,
            clarificationSummaryUuid: clarification,
            carePackageUuid: package,
            architectureSummaryUuid: architecture,
            reviewSummaryUuid: review,
            explorationSummaryUuids: exploration)
    }

    private func clarificationStatus(promptUuid: String) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT status FROM clarification_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid])
    }

    private func promptStatus(promptUuid: String) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT status FROM prompt WHERE uuid = ?", arguments: [promptUuid])
    }

    // MARK: - Resolution + fetch

    /// Explicit prompt uuid → the caller's own active workflow (client key)
    /// → the activation-resolved prompt's workflow → the session's single
    /// active workflow. The task-tier shadowing hazard applies — every bot
    /// verb keeps an explicit prompt_uuid escape hatch. Read verbs fall
    /// back to the prompt's most recent CLOSED workflow so a completed run
    /// renders as done instead of erroring SUMMARY_ABSENT.
    private func resolve(
        promptUuid: String?, clientKey: String?, sessionUuid: String?
    ) throws -> BotWorkflowRow {
        if let promptUuid {
            if let row = try fetchActive(promptUuid: promptUuid) { return row }
            if let closed = try fetchWorkflows(
                where: "prompt_uuid = ?", arguments: [promptUuid]
            ).last {
                return closed
            }
            throw StoreError.summaryAbsent(entity: "bot_workflow", promptUuid: promptUuid)
        }
        if let clientKey,
           let row = try fetchWorkflows(
               where: "client_key = ? AND status = 'active'", arguments: [clientKey]
           ).first {
            return row
        }
        if let sessionUuid {
            if let active = try SessionRepository(db: db, core: core).resolveActivePrompt(
                   sessionUuid: sessionUuid, clientKey: clientKey),
               let row = try fetchActive(promptUuid: active) {
                return row
            }
            let rows = try fetchWorkflows(
                where: "session_uuid = ? AND status = 'active'", arguments: [sessionUuid])
            if rows.count == 1 { return rows[0] }
            if rows.count > 1 {
                throw StoreError.badRequest(
                    detail: "session has \(rows.count) active workflows — pass prompt_uuid")
            }
        }
        throw StoreError.badRequest(
            detail: "no workflow resolvable — pass prompt_uuid "
                + "(or start one with mcp__plugin_gmcc_pen__prompt_init)")
    }

    func fetchActive(promptUuid: String) throws -> BotWorkflowRow? {
        try fetchWorkflows(
            where: "prompt_uuid = ? AND status = 'active'", arguments: [promptUuid]
        ).first
    }

    private func fetchRow(uuid: String) throws -> BotWorkflowRow? {
        try fetchWorkflows(where: "uuid = ?", arguments: [uuid]).first
    }

    private func fetchWorkflows(
        where condition: String, arguments: StatementArguments
    ) throws -> [BotWorkflowRow] {
        try BotWorkflowRecord.fetchAll(
            db, where: condition, arguments: arguments, orderBy: "created_at"
        ).map { $0.wireRow() }
    }

    /// The partial UNIQUE(client_key) WHERE active means one instance drives
    /// one workflow at a time: moving to a new prompt releases the old hold.
    private func releaseClientClaim(clientKey: String, except uuid: String?) throws {
        for row in try fetchWorkflows(
            where: "client_key = ? AND status = 'active'", arguments: [clientKey]
        ) where row.uuid != uuid {
            try core.updateBase(
                db, table: "bot_workflow", uuid: row.uuid,
                expectedVersion: row.version, set: ["client_key": nil])
        }
    }
}
