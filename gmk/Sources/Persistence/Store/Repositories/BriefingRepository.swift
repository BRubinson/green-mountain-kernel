import Foundation
import GRDB

/// BRIEFING_* data access — the agent-briefing machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
///
/// A briefing is an OPINION-FREE ref pre-selection. Dope children carry dot-path
/// CODES, ghost-legal at read; kbite and file-change children carry uuid FKs.
/// The completeness rule turns nil-vs-empty into meaning: omitting a ref class
/// ENTIRELY is refused while `[]` is accepted, so a stored zero-row class reads
/// as ATTEMPTED AND EMPTY. It is a PAYLOAD rule, applying to every caller.
enum BriefingCompletenessRule {

    /// Throws when the caller left a ref class out of the payload.
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
    /// Exactly one owner flag; session_uuid is ALWAYS stored (derived from
    /// the prompt's owner chain when prompt-owned) so the two columns can
    /// never disagree and task-owned rows share the same list key.
    func open(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        let step = try BriefingStepSpec.validateStep(req.briefingForStep)
        let sessionUuid: String
        let promptUuid: String?
        switch (req.promptUuid, req.sessionUuid) {
        case (let prompt?, nil):
            guard
                let owner = try String.fetchOne(
                    db,
                    sql: "SELECT session_uuid FROM prompt WHERE uuid = ?",
                    arguments: [prompt]
                )
            else {
                throw StoreError.notFound(entity: "prompt", key: prompt)
            }
            sessionUuid = owner
            promptUuid = prompt
        case (nil, let session?):
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM session WHERE uuid = ?",
                    arguments: [session]
                ) != nil
            else {
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

    /// building → ready. The daemon stamps the staleness evidence ITSELF, so the
    /// writing agent cannot mis-stamp, and denormalizes kbite briefs into the
    /// child rows.
    /// ONE ref policy for all three classes: MALFORMED is a hard refusal naming
    /// the ref; WELL-FORMED BUT UNRESOLVABLE is stored and reported back in
    /// `unresolvedDopeRefs`, since a legal dope code may ghost when the tree
    /// moves; and an unknown uuid on a REAL FK throws, because the caller cannot
    /// tell a vanished file from a typo through a silent success.
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
                let brief = try Row.fetchOne(
                    db,
                    sql: "SELECT resource_file_summary FROM kbite_resource_file WHERE uuid = ?",
                    arguments: [fileUuid]
                )
            else {
                throw StoreError.notFound(entity: "kbite_resource_file", key: fileUuid)
            }
            try core.insertBase(
                db,
                table: "agent_briefing_dope_kbite",
                extra: [
                    "agent_briefing_uuid": req.briefingUuid,
                    "kbite_resource_file_uuid": fileUuid,
                    "brief": brief["resource_file_summary"] as String?,
                    "seq": i,
                ]
            )
        }
        for (i, changeUuid) in (req.fileChangeRefs ?? []).enumerated() {
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM file_change WHERE uuid = ?",
                    arguments: [changeUuid]
                ) != nil
            else {
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

    /// The hard-reject half of the dope ref policy: purely LEXICAL, so it can
    /// never refuse a legitimate code that merely ghosts. One to four
    /// snake_case dot-segments — the depth `DopeRepository.dotPathExists`
    /// resolves — and nothing else.
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

    private func dopeRefRefusal(_ code: String, _ why: String) -> String {
        "dope ref '\(code)' is not a dope dot-path — \(why). A dope ref is a "
            + "domain.entity[.property] CODE out of the dope tree (the dope_search pen "
            + "tool), never a file path, a uuid, a kbite name or prose. "
            + "Nothing was written; fix the ref and complete again."
    }

    func get(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        let row = try resolveSelector(req: req)
        let staleness = try computeStaleness(briefing: row)
        return BriefingGetResponse(briefing: row, staleness: staleness)
    }

    func list(_ req: BriefingListRequest) throws -> BriefingListResponse {
        let rows: [AgentBriefingRow]
        if let promptUuid = req.promptUuid {
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM prompt WHERE uuid = ?",
                    arguments: [promptUuid]
                ) != nil
            else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            rows = try fetchBriefings(where: "prompt_uuid = ?", arguments: [promptUuid])
        } else if let sessionUuid = req.sessionUuid {
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM session WHERE uuid = ?",
                    arguments: [sessionUuid]
                ) != nil
            else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            rows = try fetchBriefings(where: "session_uuid = ?", arguments: [sessionUuid])
        } else {
            throw StoreError.badRequest(
                detail: "briefing list takes --prompt-uuid or --session-uuid"
            )
        }
        return BriefingListResponse(briefings: rows)
    }

    /// The SubagentStart hook's one call. Empty stub + success when nothing
    /// applies — the hook must never wedge a spawn.
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

    private func resolveSelector(req: BriefingGetRequest) throws -> AgentBriefingRow {
        if let uuid = req.briefingUuid {
            guard let row = try fetchBriefing(uuid: uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: uuid)
            }
            return row
        }
        if let promptUuid = req.promptUuid {
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM prompt WHERE uuid = ?",
                    arguments: [promptUuid]
                ) != nil
            else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            let rows = try fetchBriefings(
                where: req.step == nil ? "prompt_uuid = ?" : "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: req.step == nil ? [promptUuid] : [promptUuid, req.step!]
            )
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

    /// The ACTIVE resolution, scoped like attribution: the calling instance's
    /// own activation claim → the session's single claim when unambiguous →
    /// the session-owned (task) row. This is what makes a spawned agent's
    /// lookup deterministic — no uuid has to survive a spawn prompt.
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

    /// Forwards to the owner of dope_persistence*: `DopeRepository.scopeStaleness`
    /// and `.dotPathExists`, so agent_briefing and care_package cannot drift.
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

    private func fetchBriefingRow(
        ownerPrompt: String?,
        ownerSession: String,
        step: String
    ) throws -> AgentBriefingRow? {
        if let ownerPrompt {
            return try fetchBriefings(
                where: "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: [ownerPrompt, step]
            )
            .first
        }
        return try fetchBriefings(
            where: "session_uuid = ? AND prompt_uuid IS NULL AND briefing_for_step = ?",
            arguments: [ownerSession, step]
        )
        .first
    }

    func fetchBriefing(uuid: String) throws -> AgentBriefingRow? {
        try fetchBriefings(where: "uuid = ?", arguments: [uuid]).first
    }

    private func fetchBriefings(
        where condition: String,
        arguments: StatementArguments
    ) throws -> [AgentBriefingRow] {
        try AgentBriefingWithRefs.request()
            .filter(sql: condition, arguments: arguments)
            .order(sql: "briefing_for_step, created_at")
            .fetchAll(db)
            .map { $0.dto() }
    }
}
