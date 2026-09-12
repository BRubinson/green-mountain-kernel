import Foundation
import GRDB

/// BRIEFING_* data access — the agent-briefing machine. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
///
/// m0025 model: a briefing is an OPINION-FREE ref pre-selection. The old
/// body/dope_refs/kbite_refs TEXT columns are gone; refs are typed child
/// rows (dope children carry dot-path CODES — ghost-legal at read; kbite
/// and file-change children carry uuid FKs).
/// The role-keyed briefing completeness rule — the door-side half of gap 7.
///
/// The nil-vs-empty fix is SUBTRACTION, not a column. `BriefingCompleteRequest`
/// has always declared all three ref classes as Optionals, so "did not
/// attempt" and "attempted and found nothing" were already distinguishable on
/// the wire; two layers just threw the distinction away before anyone could
/// act on it. This is the layer that makes it MEAN something: an agent-written
/// briefing that omits a class ENTIRELY is refused, while `[]` is accepted.
/// After that, a stored zero-row class on an agent briefing reads as
/// ATTEMPTED AND EMPTY — because the only writer that could have meant
/// otherwise was refused.
///
/// It lives beside the repository rather than in dispatch because it is a
/// PAYLOAD rule, and it applies to every caller: this is about the RECORD's
/// completeness, not about who is writing it.
public enum BriefingCompletenessRule {

    /// Throws when the caller left a ref class out of the payload.
    public static func check(_ req: BriefingCompleteRequest) throws {
        let missing = [
            ("dope_refs", req.dopeRefs == nil),
            ("kbite_refs", req.kbiteRefs == nil),
            ("file_change_refs", req.fileChangeRefs == nil),
        ].filter(\.1).map(\.0)
        guard missing.isEmpty else {
            throw StoreError.badRequest(detail:
                "briefing complete omits \(missing.joined(separator: ", ")) entirely — a "
                + "briefing must record what it LOOKED FOR, not only what it found. Pass an "
                + "EMPTY ARRAY for a class you searched and came up empty on (that is a real, "
                + "readable answer); leaving the class out is indistinguishable from never "
                + "having looked, and this daemon no longer accepts the ambiguity.")
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
            guard let owner = try String.fetchOne(
                db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?", arguments: [prompt]
            ) else {
                throw StoreError.notFound(entity: "prompt", key: prompt)
            }
            sessionUuid = owner
            promptUuid = prompt
        case (nil, let session?):
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [session]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: session)
            }
            sessionUuid = session
            promptUuid = nil
        default:
            throw StoreError.badRequest(
                detail: "briefing open takes exactly one owner: --prompt-uuid or --session-uuid")
        }

        // A prompt-owned open also claims the activation for the calling
        // instance (review finding 5f68f01d): briefings are consumed in
        // the draft/architecting phases, long before set-status
        // implementing would claim — and the claim is what makes every
        // downstream agent's zero-uuid pull deterministic.
        if let promptUuid, let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core).claimActivation(
                sessionUuid: sessionUuid,
                promptUuid: promptUuid, clientKey: clientKey)
        }

        if let existing = try fetchBriefingRow(
            ownerPrompt: promptUuid, ownerSession: sessionUuid, step: step
        ) {
            // Reset, never duplicate — and since refs are child rows now,
            // reset TRUNCATES them: a step's briefing is its CURRENT
            // briefing, stale refs must not leak into the rebuilt one.
            try deleteChildren(briefingUuid: existing.uuid)
            try core.updateBase(
                db, table: "agent_briefing", uuid: existing.uuid,
                expectedVersion: existing.version,
                set: ["status": "building"])
            try core.appendEvent(
                db, kind: .briefingChange, subjectUuid: existing.uuid,
                payload: Store.jsonPayload([
                    "action": "reset", "step": step,
                    "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
                ]))
            try core.touchSession(db, uuid: sessionUuid)
            guard let row = try fetchBriefing(uuid: existing.uuid) else {
                throw StoreError.notFound(entity: "agent_briefing", key: existing.uuid)
            }
            return BriefingRowResponse(briefing: row, created: false)
        }

        let uuid = try core.insertBase(db, table: "agent_briefing", extra: [
            "session_uuid": sessionUuid,
            "prompt_uuid": promptUuid,
            "briefing_for_step": step,
            "status": "building",
        ])
        try core.appendEvent(
            db, kind: .briefingChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "open", "step": step,
                "session_uuid": sessionUuid, "prompt_uuid": promptUuid,
            ]))
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchBriefing(uuid: uuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: uuid)
        }
        return BriefingRowResponse(briefing: row, created: true)
    }

    /// building → ready. The daemon stamps the staleness evidence ITSELF
    /// (the writing agent cannot mis-stamp) and denormalizes kbite briefs
    /// into the child rows.
    ///
    /// ONE ref policy, not three. This function used to run three mutually
    /// incompatible policies in adjacent loops — dope refs inserted RAW,
    /// kbite refs silently DROPPED on an unknown uuid, file-change refs
    /// THROWN on — which is how a doper wrote twenty-three FILE PATHS into
    /// `--dope-ref`, twice, and had every one accepted silently; they
    /// surfaced only as ghost dot-paths at read, long after the agent that
    /// could have fixed them was gone. The policy is now single, with one
    /// deliberate distinction:
    ///
    /// - MALFORMED is always a hard refusal that NAMES the offending ref.
    ///   For dope that test is purely lexical (`DopeCode.validateCode` per
    ///   dot-segment), which is exactly the class the incident produced:
    ///   slashes, `.swift`/`.md` suffixes, uuid shapes, sentences, a
    ///   `gmcc:` scope prefix.
    /// - WELL-FORMED BUT UNRESOLVABLE is not a refusal. A legal dope code
    ///   may ghost when the tree moves under a briefing, so it is stored
    ///   and reported back in `unresolvedDopeRefs` — the writing agent sees
    ///   its own mistake while it is still holding the pen, without a legal
    ///   ref set being refused for tree drift.
    /// - A ref carrying a REAL FK (kbite file, file_change) offers the
    ///   caller no ghost-vs-typo distinction at all, so an unknown uuid
    ///   THROWS. The old ghost-tolerance note justified dropping a VANISHED
    ///   file; it never justified dropping a typo, and the caller cannot
    ///   tell the two apart from a silent success.
    func complete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        guard let existing = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }

        // Server-side staleness stamp from the session's SESSION_INSTANCE
        // scope. No scope is a legal state (nil stamp, staleness unknown).
        //
        // HOISTED above the ref loops: this lookup used to sit thirty lines
        // BELOW them, doing nothing but stamp staleness, while the validator
        // it unlocks (`DopeRepository.dotPathExists`) went unused by the very
        // loop that needed it.
        let scope = try dope.dopeScopeCandidates(
            sessionUuid: existing.sessionUuid, scopeType: .sessionInstance
        ).first

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
            try core.insertBase(db, table: "agent_briefing_dope_persistence", extra: [
                "agent_briefing_uuid": req.briefingUuid,
                "dope_code": code,
                "seq": i,
            ])
        }
        // Briefs denormalized from the kbite tables at write time:
        // point-in-time by design. An unknown file uuid is a typed refusal —
        // the file_change policy, adopted here (see the doc comment).
        for (i, fileUuid) in (req.kbiteRefs ?? []).enumerated() {
            guard let brief = try Row.fetchOne(
                db,
                sql: "SELECT resource_file_summary FROM kbite_resource_file WHERE uuid = ?",
                arguments: [fileUuid]
            ) else {
                throw StoreError.notFound(entity: "kbite_resource_file", key: fileUuid)
            }
            try core.insertBase(db, table: "agent_briefing_dope_kbite", extra: [
                "agent_briefing_uuid": req.briefingUuid,
                "kbite_resource_file_uuid": fileUuid,
                "brief": brief["resource_file_summary"] as String?,
                "seq": i,
            ])
        }
        for (i, changeUuid) in (req.fileChangeRefs ?? []).enumerated() {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM file_change WHERE uuid = ?", arguments: [changeUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "file_change", key: changeUuid)
            }
            try core.insertBase(db, table: "agent_session_file_change", extra: [
                "agent_briefing_uuid": req.briefingUuid,
                "file_change_uuid": changeUuid,
                "seq": i,
            ])
        }

        try core.updateBase(
            db, table: "agent_briefing", uuid: req.briefingUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": "ready",
                "agent_id": req.agentId,
                "dope_scope_uuid": scope?.uuid,
                "dope_scope_revision": scope?.revision,
            ])
        try core.appendEvent(
            db, kind: .briefingChange, subjectUuid: req.briefingUuid,
            payload: Store.jsonPayload([
                "action": "complete", "step": existing.briefingForStep,
                "session_uuid": existing.sessionUuid,
                "prompt_uuid": existing.promptUuid,
                "dope_scope_revision": scope?.revision,
            ]))
        try core.touchSession(db, uuid: existing.sessionUuid)
        guard let row = try fetchBriefing(uuid: req.briefingUuid) else {
            throw StoreError.notFound(entity: "agent_briefing", key: req.briefingUuid)
        }
        return BriefingRowResponse(
            briefing: row,
            unresolvedDopeRefs: unresolvedDopeRefs.isEmpty ? nil : unresolvedDopeRefs)
    }

    /// The hard-reject half of the dope ref policy: purely LEXICAL, so it can
    /// never refuse a legitimate code that merely ghosts. One to four
    /// snake_case dot-segments — the depth `DopeRepository.dotPathExists`
    /// resolves — and nothing else.
    private func validateDopeRefShape(_ code: String) throws {
        let segments = code.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...4).contains(segments.count) else {
            throw StoreError.badRequest(detail: dopeRefRefusal(
                code,
                "has \(segments.count) dot-separated segment(s); a dope dot-path has 1 to 4"))
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
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            rows = try fetchBriefings(where: "prompt_uuid = ?", arguments: [promptUuid])
        } else if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            rows = try fetchBriefings(where: "session_uuid = ?", arguments: [sessionUuid])
        } else {
            throw StoreError.badRequest(
                detail: "briefing list takes --prompt-uuid or --session-uuid")
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
            sessionUuid: sessionUuid, clientKey: req.clientKey
        ) {
            lines.append("active_prompt_uuid: \(active)")
        }

        // Roles with a mapped step get their briefing line; everyone else
        // still gets the uuid block above.
        if let step {
            let row = try resolveActiveBriefing(
                session: session, step: step, clientKey: req.clientKey)
            if let row {
                let staleness = try computeStaleness(briefing: row)
                lines.append("briefing_uuid: \(row.uuid) (step: \(row.briefingForStep), status: \(row.status))")
                lines.append(
                    "refs: \(row.dopeRefs.count) dope, \(row.kbiteRefs.count) kbite, "
                    + "\(row.fileChangeRefs.count) file-change")
                if staleness.drifted {
                    lines.append(
                        "WARNING: briefing is STALE — dope scope moved "
                        + "\(staleness.stampedRevision.map(String.init) ?? "?") → "
                        + "\(staleness.currentRevision.map(String.init) ?? "?"); "
                        + "prefer a fresh mcp__plugin_gmcc_pen__dope_search for anything load-bearing")
                }
                lines.append("Pull the full briefing FIRST: mcp__plugin_gmcc_pen__briefing_get "
                             + "briefing_uuid: \(row.uuid)")
            } else {
                lines.append("briefing: none for step '\(step)' — proceed without; "
                             + "mcp__plugin_gmcc_pen__dope_search and "
                             + "mcp__plugin_gmcc_pen__kbite_search are available")
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
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            let rows = try fetchBriefings(
                where: req.step == nil ? "prompt_uuid = ?" : "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: req.step == nil ? [promptUuid] : [promptUuid, req.step!])
            if rows.isEmpty {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: promptUuid)
            }
            guard rows.count == 1 else {
                throw StoreError.badRequest(
                    detail: "prompt \(promptUuid) has \(rows.count) briefings — pass --step to pick one")
            }
            return rows[0]
        }
        if let sessionUuid = req.sessionUuid {
            guard let session = try SessionRepository(db: db, core: core)
                .fetchRow(uuid: sessionUuid) else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            guard let step = req.step else {
                throw StoreError.badRequest(detail: "session-scoped briefing get requires --step")
            }
            guard let row = try resolveActiveBriefing(
                session: session, step: step, clientKey: req.clientKey
            ) else {
                throw StoreError.summaryAbsent(entity: "briefing", promptUuid: sessionUuid)
            }
            return row
        }
        throw StoreError.badRequest(
            detail: "briefing get takes --briefing-uuid, --prompt-uuid [--step], or --session-uuid --step")
    }

    /// The ACTIVE resolution, scoped like attribution: the calling instance's
    /// own activation claim → the session's single claim when unambiguous →
    /// the session-owned (task) row. This is what makes a spawned agent's
    /// lookup deterministic — no uuid has to survive a spawn prompt.
    private func resolveActiveBriefing(
        session: SessionRow, step: String, clientKey: String?
    ) throws -> AgentBriefingRow? {
        if let active = try SessionRepository(db: db, core: core).resolveActivePrompt(
               sessionUuid: session.uuid, clientKey: clientKey),
           let row = try fetchBriefingRow(
               ownerPrompt: active, ownerSession: session.uuid, step: step) {
            return row
        }
        return try fetchBriefingRow(
            ownerPrompt: nil, ownerSession: session.uuid, step: step)
    }

    /// Forwards to the owner of dope_persistence*. The body (and the private
    /// `dopeDotPathExists` it used to carry) moved VERBATIM to
    /// `DopeRepository.scopeStaleness` / `.dotPathExists` so agent_briefing and
    /// care_package cannot drift apart — this output stays byte-identical.
    private func computeStaleness(briefing: AgentBriefingRow) throws -> BriefingStaleness {
        let s = try dope.scopeStaleness(
            scopeUuid: briefing.dopeScopeUuid,
            stampedRevision: briefing.dopeScopeRevision,
            dotPaths: briefing.dopeRefs.map(\.dopeCode))
        return BriefingStaleness(
            stampedRevision: s.stamped,
            currentRevision: s.current,
            drifted: s.drifted,
            ghostDotPaths: s.ghosts)
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
                arguments: [briefingUuid])
        }
    }

    private func fetchBriefingRow(
        ownerPrompt: String?, ownerSession: String, step: String
    ) throws -> AgentBriefingRow? {
        if let ownerPrompt {
            return try fetchBriefings(
                where: "prompt_uuid = ? AND briefing_for_step = ?",
                arguments: [ownerPrompt, step]
            ).first
        }
        return try fetchBriefings(
            where: "session_uuid = ? AND prompt_uuid IS NULL AND briefing_for_step = ?",
            arguments: [ownerSession, step]
        ).first
    }

    func fetchBriefing(uuid: String) throws -> AgentBriefingRow? {
        try fetchBriefings(where: "uuid = ?", arguments: [uuid]).first
    }

    private func fetchBriefings(
        where condition: String, arguments: StatementArguments
    ) throws -> [AgentBriefingRow] {
        try AgentBriefingRecord.fetchAll(
            db, where: condition, arguments: arguments,
            orderBy: "briefing_for_step, created_at"
        ).map { record in
            let dopeRefs = try AgentBriefingDopePersistenceRecord.fetchAll(
                db, where: "agent_briefing_uuid = ?", arguments: [record.uuid], orderBy: "seq"
            ).map { $0.wireRow() }
            let kbiteRefs = try AgentBriefingDopeKbiteRecord.fetchAll(
                db, where: "agent_briefing_uuid = ?", arguments: [record.uuid], orderBy: "seq"
            ).map { $0.wireRow() }
            let fileChangeRefs = try AgentSessionFileChangeRecord.fetchAll(
                db, where: "agent_briefing_uuid = ?", arguments: [record.uuid], orderBy: "seq"
            ).map { $0.wireRow() }
            return record.wireRow(
                dopeRefs: dopeRefs, kbiteRefs: kbiteRefs, fileChangeRefs: fileChangeRefs)
        }
    }
}
