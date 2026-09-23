import Foundation
import GRDB

/// BRIEFING_* data access — the agent-briefing machine.
///
/// Runs inside a Store-owned transaction, no dbQueue or self-transact. Briefing
/// is OPINION-FREE ref pre-selection. Dope children carry dot-path CODES (ghost-
/// legal), kbite/file-change children carry uuid FKs. Completeness rule: omitting
/// a ref class is refused, `[]` accepted. Zero-row class reads as attempted-empty.
enum BriefingCompletenessRule {

    /// Throws when the caller left a ref class out of the payload.
    ///
    /// - Parameter req: The briefing completion request to validate.
    /// - Throws: `StoreError.badRequest` when a ref class is omitted from the payload.
    static func check(_ req: BriefingCompleteRequest) throws {
        let missing = [
            ("dope_refs", req.dopeRefs == nil),
            ("kbite_refs", req.kbiteRefs == nil),
            ("file_change_refs", req.fileChangeRefs == nil),
        ]
        .filter(\.1).map(\.0)
        guard missing.isEmpty else {
            throw StoreError.badRequest(
                detail:
                    "briefing complete omits \(missing.joined(separator: ", ")) entirely — a "
                    + "briefing must record what it LOOKED FOR, not only what it found. Pass an "
                    + "EMPTY ARRAY for a class you searched and came up empty on (that is a real, "
                    + "readable answer); leaving the class out is indistinguishable from never "
                    + "having looked, and this daemon no longer accepts the ambiguity."
            )
        }
    }
}

struct BriefingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Verbs

    /// Reserve (or reset) the briefing row for one (owner, step) pair.
    ///
    /// Exactly one owner flag; session_uuid is ALWAYS stored (derived from
    /// the prompt's owner chain when prompt-owned) so the two columns can
    /// never disagree and task-owned rows share the same list key.
    ///
    /// - Parameter req: The briefing open request specifying the owner and step.
    /// - Returns: The briefing row with creation status.
    /// - Throws: `StoreError` when the owner or step is invalid or does not exist.
    func open(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        let step = try BriefingStepSpec.validateStep(req.briefingForStep)
        let sessionUuid: String
        let promptUuid: String?
        switch (req.promptUuid, req.sessionUuid) {
        case (let prompt?, nil):
            guard
                let owner =
                    try PromptRecord
                    .all()
                    .withUuid(prompt)
                    .select(PromptRecord.Columns.sessionUuid, as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: "prompt", key: prompt)
            }
            sessionUuid = owner
            promptUuid = prompt
        case (nil, let session?):
            guard try SessionRecord.exists(db, key: ["uuid": session]) else {
                throw StoreError.notFound(entity: "session", key: session)
            }
            sessionUuid = session
            promptUuid = nil
        default:
            throw StoreError.badRequest(
                detail: "briefing open takes exactly one owner: --prompt-uuid or --session-uuid"
            )
        }

        // A prompt-owned open also claims the activation for the calling
        // instance (review finding 5f68f01d): briefings are consumed at the
        // very start of a run, and the claim is what makes every downstream
        // agent's zero-uuid pull deterministic.
        if let promptUuid, let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core)
                .claimActivation(
                    sessionUuid: sessionUuid,
                    promptUuid: promptUuid,
                    clientKey: clientKey
                )
        }

        // Opening a prompt's briefing is what STARTS it: draft → initiated,
        // here, and NOT on loading the prompt. Loading is a pure read and has to
        // stay one, because in an append-only db a read that advances the prompt
        // is not retractable. A guarded UPDATE rather than a read-then-write: it
        // is idempotent by construction and cannot race, and it deliberately
        // avoids setStatus, which checks an expected_version this caller has no
        // business holding. BRIEFING_OPEN is not a lifecycle verb.
        if let promptUuid {
            try db.execute(
                sql: """
                    UPDATE prompt
                       SET status = 'initiated', updated_at = ?, version = version + 1
                     WHERE uuid = ? AND status = 'draft';
                    """,
                arguments: [Store.isoNow(), promptUuid]
            )
            if db.changesCount > 0 {
                try core.appendEvent(
                    db,
                    kind: .promptStatusChange,
                    subjectUuid: promptUuid,
                    payload: Store.jsonPayload([
                        "from": PromptStatus.draft.rawValue,
                        "to": PromptStatus.initiated.rawValue,
                        "via": "briefing_open",
                    ])
                )
            }
        }

        if let existing = try fetchBriefingRow(
            ownerPrompt: promptUuid,
            ownerSession: sessionUuid,
            step: step
        ) {
            // Reset, never duplicate — and since refs are child rows now,
            // reset TRUNCATES them: a step's briefing is its CURRENT
            // briefing, stale refs must not leak into the rebuilt one.
            try deleteChildren(briefingUuid: existing.uuid)
            try core.updateBase(
                db,
                table: "agent_briefing",
                uuid: existing.uuid,
                expectedVersion: existing.version,
                set: ["status": "building"]
            )
            try core.appendEvent(
                db,
                kind: .briefingChange,
                subjectUuid: existing.uuid,
                payload: Store.jsonPayload([
                    "action": "reset", "step": step,
                    "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
                ])
            )
            try core.touchSession(db, uuid: sessionUuid)
            guard let row = try fetchBriefing(uuid: existing.uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: existing.uuid)
            }
            return BriefingRowResponse(briefing: row, created: false)
        }

        let uuid = try core.insertBase(
            db,
            table: "agent_briefing",
            extra: [
                "session_uuid": sessionUuid,
                "prompt_uuid": promptUuid,
                "briefing_for_step": step,
                "status": "building",
            ]
        )
        try core.appendEvent(
            db,
            kind: .briefingChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "open", "step": step,
                "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
            ])
        )
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchBriefing(uuid: uuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: uuid)
        }
        return BriefingRowResponse(briefing: row, created: true)
    }

    /// building → ready.
    ///
    /// Daemon stamps staleness; agent cannot mis-stamp. Denormalizes kbite
    /// briefs into child rows. One ref policy: MALFORMED hard-refuses, WELL-
    /// FORMED BUT UNRESOLVABLE stores in `unresolvedDopeRefs` (dope codes ghost),
    /// unknown UUID on FK throws (caller distinguishes vanished from typo).
    ///
    /// - Parameter req: The briefing completion request with resolved references.
    /// - Returns: The briefing row with unresolved dope refs, if any.
    /// - Throws: `StoreError` when the briefing, scope, or references do not exist.
    func complete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        guard let existing = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }

        // Server-side staleness stamp from the session's SESSION_INSTANCE
        // scope. No scope is a legal state (nil stamp, staleness unknown).
        // It sits above the ref loops because they need the validator it
        // unlocks, `DopeRepository.dotPathExists`.
        let scope =
            try dope.dopeScopeCandidates(
                sessionUuid: existing.sessionUuid,
                scopeType: .sessionInstance
            )
            .first

        // Wholesale replacement (the open-resets precedent): a re-complete
        // replaces the whole ref set, never appends to it.
        try deleteChildren(briefingUuid: req.briefingUuid)

        var unresolvedDopeRefs: [String] = []
        for (i, code) in (req.dopeRefs ?? []).enumerated() {
            try validateDopeRefShape(code)
            if let scope {
                let resolves = try dope.dotPathExists(scopeUuid: scope.uuid, path: code)
                if !resolves { unresolvedDopeRefs.append(code) }
            }
            try core.insertBase(
                db,
                table: "agent_briefing_dope_persistence",
                extra: [
                    "agent_briefing_uuid": req.briefingUuid,
                    "dope_code": code,
                    "seq": i,
                ]
            )
        }
        // Briefs denormalized from the kbite tables at write time:
        // point-in-time by design. An unknown file uuid is a typed refusal —
        // the file_change policy, adopted here (see the doc comment).
        for (i, fileUuid) in (req.kbiteRefs ?? []).enumerated() {
            guard
                let brief =
                    try KbiteResourceFileRecord
                    .all()
                    .withUuid(fileUuid)
                    .select(KbiteResourceFileRecord.Columns.resourceFileSummary, as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: "kbite_resource_file", key: fileUuid)
            }
            try core.insertBase(
                db,
                table: "agent_briefing_dope_kbite",
                extra: [
                    "agent_briefing_uuid": req.briefingUuid,
                    "kbite_resource_file_uuid": fileUuid,
                    "brief": brief,
                    "seq": i,
                ]
            )
        }
        for (i, changeUuid) in (req.fileChangeRefs ?? []).enumerated() {
            guard try FileChangeRecord.exists(db, key: ["uuid": changeUuid]) else {
                throw StoreError.notFound(entity: "file_change", key: changeUuid)
            }
            try core.insertBase(
                db,
                table: "agent_session_file_change",
                extra: [
                    "agent_briefing_uuid": req.briefingUuid,
                    "file_change_uuid": changeUuid,
                    "seq": i,
                ]
            )
        }

        try core.updateBase(
            db,
            table: "agent_briefing",
            uuid: req.briefingUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": "ready",
                "agent_id": req.agentId,
                "dope_scope_uuid": scope?.uuid,
                "dope_scope_revision": scope?.revision,
            ]
        )
        try core.appendEvent(
            db,
            kind: .briefingChange,
            subjectUuid: req.briefingUuid,
            payload: Store.jsonPayload([
                "action": "complete", "step": existing.briefingForStep,
                "session_uuid": existing.sessionUuid,
                "prompt_uuid": existing.promptUuid,
                "dope_scope_revision": scope?.revision,
            ])
        )
        try core.touchSession(db, uuid: existing.sessionUuid)
        guard let row = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }
        return BriefingRowResponse(
            briefing: row,
            unresolvedDopeRefs: unresolvedDopeRefs.isEmpty ? nil : unresolvedDopeRefs
        )
    }

    /// Validates the shape of a dope ref using purely lexical rules.
    ///
    /// The hard-reject half of the dope ref policy: purely LEXICAL, so it can
    /// never refuse a legitimate code that merely ghosts. One to four snake_case
    /// dot-segments — the depth `DopeRepository.dotPathExists` resolves — and
    /// nothing else.
    ///
    /// - Parameter code: The dope dot-path to validate.
    /// - Throws: `StoreError.badRequest` when the code has an invalid shape.
    private func validateDopeRefShape(_ code: String) throws {
        let segments = code.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...4).contains(segments.count) else {
            throw StoreError.badRequest(
                detail: dopeRefRefusal(
                    code,
                    "has \(segments.count) dot-separated segment(s); a dope dot-path has 1 to 4"
                )
            )
        }
        for (i, segment) in segments.enumerated() {
            do {
                try DopeCode.validateCode(segment, field: "segment \(i + 1)")
            } catch let error as DopeCode.ValidationError {
                throw StoreError.badRequest(detail: dopeRefRefusal(code, error.description))
            }
        }
    }

    /// Formats an error message for an invalid dope ref.
    ///
    /// - Parameters:
    ///   - code: The invalid dope ref code.
    ///   - why: The reason the code is invalid.
    /// - Returns: A formatted error message.
    private func dopeRefRefusal(_ code: String, _ why: String) -> String {
        "dope ref '\(code)' is not a dope dot-path — \(why). A dope ref is a "
            + "domain.entity[.property] CODE out of the dope tree (the dope_search pen "
            + "tool), never a file path, a uuid, a kbite name or prose. "
            + "Nothing was written; fix the ref and complete again."
    }

    /// Retrieves a briefing and its staleness.
    ///
    /// - Parameter req: The briefing get request specifying the selector.
    /// - Returns: The briefing with staleness information.
    /// - Throws: `StoreError` when the briefing does not exist or selector is invalid.
    func get(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        let row = try resolveSelector(req: req)
        let staleness = try computeStaleness(briefing: row)
        return BriefingGetResponse(briefing: row, staleness: staleness)
    }

    /// Retrieves briefings for a prompt or session.
    ///
    /// - Parameter req: The briefing list request specifying the owner.
    /// - Returns: The list of matching briefings.
    /// - Throws: `StoreError` when the owner does not exist or selector is invalid.
    func list(_ req: BriefingListRequest) throws -> BriefingListResponse {
        let rows: [AgentBriefingRow]
        if let promptUuid = req.promptUuid {
            guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            rows = try fetchBriefings(
                matching: AgentBriefingRecord.Columns.promptUuid == promptUuid
            )
        } else if let sessionUuid = req.sessionUuid {
            guard try SessionRecord.exists(db, key: ["uuid": sessionUuid]) else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            rows = try fetchBriefings(
                matching: AgentBriefingRecord.Columns.sessionUuid == sessionUuid
            )
        } else {
            throw StoreError.badRequest(
                detail: "briefing list takes --prompt-uuid or --session-uuid"
            )
        }
        return BriefingListResponse(briefings: rows)
    }

    /// The SubagentStart hook's one call.
    ///
    /// Empty stub + success when nothing applies — the hook must never wedge a
    /// spawn.
    ///
    /// - Parameter req: The briefing stub request specifying the session and agent type.
    /// - Returns: A briefing stub with session and briefing context.
    /// - Throws: Never; returns an empty stub or error message on failure.
    func stub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        guard let sessionUuid = req.sessionUuid else {
            return BriefingStubResponse(stub: "")
        }
        let sessions = SessionRepository(db: db, core: core)
        guard let session = try sessions.fetchRow(uuid: sessionUuid) else {
            return BriefingStubResponse(stub: "")
        }
        let step = req.agentType.flatMap(BriefingStepSpec.step(forAgentType:))

        var lines: [String] = []
        lines.append("[GMCC BRIEFING STUB]")
        lines.append("session_uuid: \(sessionUuid)")
        if let active = try sessions.resolveActivePrompt(
            sessionUuid: sessionUuid,
            clientKey: req.clientKey
        ) {
            lines.append("active_prompt_uuid: \(active)")
        }

        // Roles with a mapped step get their briefing line; everyone else
        // still gets the uuid block above.
        if let step {
            let row = try resolveActiveBriefing(
                session: session,
                step: step,
                clientKey: req.clientKey
            )
            if let row {
                let staleness = try computeStaleness(briefing: row)
                lines.append("briefing_uuid: \(row.uuid) (step: \(row.briefingForStep), status: \(row.status))")
                lines.append(
                    "refs: \(row.dopeRefs.count) dope, \(row.kbiteRefs.count) kbite, "
                        + "\(row.fileChangeRefs.count) file-change"
                )
                if staleness.drifted {
                    lines.append(
                        "WARNING: briefing is STALE — dope scope moved "
                            + "\(staleness.stampedRevision.map(String.init) ?? "?") → "
                            + "\(staleness.currentRevision.map(String.init) ?? "?"); "
                            + "prefer a fresh \(CdeToolSpec.qualifiedName("cde_dope")) op search_session "
                            + "for anything load-bearing"
                    )
                }
                lines.append(
                    "Pull the full briefing FIRST: \(CdeToolSpec.qualifiedName("cde_rpir_briefing")) "
                        + "op load briefing_uuid: \(row.uuid)"
                )
            } else {
                lines.append(
                    "briefing: none for step '\(step)' — proceed without; "
                        + "\(CdeToolSpec.qualifiedName("cde_dope")) op search_session and "
                        + "\(CdeToolSpec.qualifiedName("cde_kbite")) op search are available"
                )
            }
        }
        return BriefingStubResponse(stub: lines.joined(separator: "\n"))
    }

    // MARK: - Selector + staleness internals

    /// Resolves a briefing from a get request using uuid, prompt, or session selectors.
    ///
    /// - Parameter req: The briefing get request with selector information.
    /// - Returns: The resolved briefing row.
    /// - Throws: `StoreError` when the selector is invalid or ambiguous.
    private func resolveSelector(req: BriefingGetRequest) throws -> AgentBriefingRow {
        if let uuid = req.briefingUuid {
            guard let row = try fetchBriefing(uuid: uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: uuid)
            }
            return row
        }
        if let promptUuid = req.promptUuid {
            guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            var predicate = AgentBriefingRecord.Columns.promptUuid == promptUuid
            if let step = req.step {
                predicate = predicate && AgentBriefingRecord.Columns.briefingForStep == step
            }
            let rows = try fetchBriefings(matching: predicate)
            if rows.isEmpty {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: promptUuid)
            }
            guard rows.count == 1 else {
                throw StoreError.badRequest(
                    detail: "prompt \(promptUuid) has \(rows.count) briefings — pass --step to pick one"
                )
            }
            return rows[0]
        }
        if let sessionUuid = req.sessionUuid {
            guard
                let session = try SessionRepository(db: db, core: core)
                    .fetchRow(uuid: sessionUuid)
            else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            guard let step = req.step else {
                throw StoreError.badRequest(detail: "session-scoped briefing get requires --step")
            }
            guard
                let row = try resolveActiveBriefing(
                    session: session,
                    step: step,
                    clientKey: req.clientKey
                )
            else {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: sessionUuid)
            }
            return row
        }
        throw StoreError.badRequest(
            detail: "briefing get takes --briefing-uuid, --prompt-uuid [--step], or --session-uuid --step"
        )
    }

    /// Resolves the active briefing scoped to the calling instance or session.
    ///
    /// The ACTIVE resolution, scoped like attribution: the calling instance's
    /// own activation claim → the session's single claim when unambiguous →
    /// the session-owned (task) row. This is what makes a spawned agent's
    /// lookup deterministic — no uuid has to survive a spawn prompt.
    ///
    /// - Parameters:
    ///   - session: The session row containing the briefing owner.
    ///   - step: The briefing step to resolve.
    ///   - clientKey: The client key for instance-scoped activation lookup, or nil.
    /// - Returns: The active briefing row, or nil when none is found.
    /// - Throws: `StoreError` on database access failures.
    private func resolveActiveBriefing(
        session: SessionRow,
        step: String,
        clientKey: String?
    ) throws -> AgentBriefingRow? {
        if let active = try SessionRepository(db: db, core: core)
            .resolveActivePrompt(
                sessionUuid: session.uuid,
                clientKey: clientKey
            ),
            let row = try fetchBriefingRow(
                ownerPrompt: active,
                ownerSession: session.uuid,
                step: step
            )
        {
            return row
        }
        return try fetchBriefingRow(
            ownerPrompt: nil,
            ownerSession: session.uuid,
            step: step
        )
    }

    /// Computes staleness of a briefing relative to its dope scope.
    ///
    /// Forwards to the owner of dope_persistence*: `DopeRepository.scopeStaleness`
    /// and `.dotPathExists`, so agent_briefing and care_package cannot drift.
    ///
    /// - Parameter briefing: The briefing row to compute staleness for.
    /// - Returns: The staleness information including dope scope revision and ghosts.
    /// - Throws: `StoreError` on database access failures.
    private func computeStaleness(briefing: AgentBriefingRow) throws -> BriefingStaleness {
        let s = try dope.scopeStaleness(
            scopeUuid: briefing.dopeScopeUuid,
            stampedRevision: briefing.dopeScopeRevision,
            dotPaths: briefing.dopeRefs.map(\.dopeCode)
        )
        return BriefingStaleness(
            stampedRevision: s.stamped,
            currentRevision: s.current,
            drifted: s.drifted,
            ghostDotPaths: s.ghosts
        )
    }

    // MARK: - Fetch helpers

    /// Deletes all child ref rows associated with a briefing.
    ///
    /// - Parameter briefingUuid: The briefing uuid whose children to delete.
    /// - Throws: Never; database errors are propagated.
    private func deleteChildren(briefingUuid: String) throws {
        for table in [
            "agent_briefing_dope_persistence",
            "agent_briefing_dope_kbite",
            "agent_session_file_change",
        ] {
            try db.execute(
                sql: "DELETE FROM \(table) WHERE agent_briefing_uuid = ?",
                arguments: [briefingUuid]
            )
        }
    }

    /// Fetches a briefing for a prompt or session at a specific step.
    ///
    /// - Parameters:
    ///   - ownerPrompt: The prompt uuid to match, or nil for session-owned briefings.
    ///   - ownerSession: The session uuid to match.
    ///   - step: The briefing step to match.
    /// - Returns: The briefing row, or nil when no match is found.
    /// - Throws: `StoreError` on database access failures.
    private func fetchBriefingRow(
        ownerPrompt: String?,
        ownerSession: String,
        step: String
    ) throws -> AgentBriefingRow? {
        let forStep = AgentBriefingRecord.Columns.briefingForStep == step
        if let ownerPrompt {
            return try fetchBriefings(
                matching: AgentBriefingRecord.Columns.promptUuid == ownerPrompt && forStep
            )
            .first
        }
        return try fetchBriefings(
            matching: AgentBriefingRecord.Columns.sessionUuid == ownerSession
                && AgentBriefingRecord.Columns.promptUuid == nil
                && forStep
        )
        .first
    }

    /// Fetches a briefing by uuid.
    ///
    /// - Parameter uuid: The briefing uuid to fetch.
    /// - Returns: The briefing row, or nil when not found.
    /// - Throws: `StoreError` on database access failures.
    func fetchBriefing(uuid: String) throws -> AgentBriefingRow? {
        try fetchBriefings(matching: AgentBriefingRecord.Columns.uuid == uuid).first
    }

    /// Fetches briefings matching a SQL predicate.
    ///
    /// - Parameter predicate: The SQL predicate to filter briefing records.
    /// - Returns: The ordered list of briefing rows matching the predicate.
    /// - Throws: `StoreError` on database access failures.
    private func fetchBriefings(matching predicate: SQLExpression) throws -> [AgentBriefingRow] {
        try AgentBriefingWithRefs.request()
            .filter(predicate)
            .order(
                AgentBriefingRecord.Columns.briefingForStep,
                AgentBriefingRecord.Columns.createdAt
            )
            .fetchAll(db)
            .map { $0.dto() }
    }
}
