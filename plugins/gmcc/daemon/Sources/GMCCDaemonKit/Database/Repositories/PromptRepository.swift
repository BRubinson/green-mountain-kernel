import Foundation
import GRDB

/// PROMPT_* data access — the prompt lifecycle. Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct PromptRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func create(_ req: PromptCreateRequest) throws -> PromptRow {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [req.sessionUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        // Atomic under the single writer: MAX+1 inside the write
        // transaction; UNIQUE(session_uuid, seq) is the backstop.
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM prompt WHERE session_uuid = ?",
            arguments: [req.sessionUuid]) ?? 0) + 1
        let code = req.code ?? "p\(seq)"
        // Item 7: derive the ckfs folder daemon-side when the caller
        // doesn't supply one — the session row (same transaction) already
        // carries its own path, and the folder convention is
        // {seq}_{name}. Legacy rows stay empty (no backfill: a wrong path
        // is worse than an absent one).
        var ckfsPath = req.ckfsRelativeStoragePath ?? ""
        if ckfsPath.isEmpty {
            let sessionPath = try String.fetchOne(
                db,
                sql: "SELECT ckfs_relative_storage_path FROM session WHERE uuid = ?",
                arguments: [req.sessionUuid]) ?? ""
            if !sessionPath.isEmpty {
                // A4: the name is slugged (forward-only, lossy) so the
                // stored path — which the MemoryWatcher matches by exact
                // case-sensitive equality — never contains spaces/slashes.
                // Clients MUST use this returned path verbatim, never
                // re-derive {seq}_{name} themselves.
                ckfsPath = "\(sessionPath)/prompts/\(seq)_\(Store.slugStorageSegment(req.name))"
            }
        }
        let uuid = try core.insertBase(db, table: "prompt", uuid: req.uuid, extra: [
            "session_uuid": req.sessionUuid,
            "seq": seq,
            "code": code,
            "name": req.name,
            "backstory": req.backstory,
            "goal": req.goal,
            "detail": req.detail,
            "command": req.command ?? "",
            "status": PromptStatus.draft.rawValue,
            "ckfs_relative_storage_path": ckfsPath,
        ])
        // Seed prompt kbites from the session registry (create-time-only
        // inheritance, same rule as the context chain).
        let sessionKbites = try String.fetchAll(
            db,
            sql: "SELECT kbite_uuid FROM session_active_kbite WHERE session_uuid = ?",
            arguments: [req.sessionUuid])
        for kbiteUuid in sessionKbites {
            try core.insertBase(db, table: "prompt_active_kbite", extra: [
                "prompt_uuid": uuid,
                "kbite_uuid": kbiteUuid,
            ])
        }
        // Item 4: payload carries session_uuid so GMVibes can route the
        // event to one session instead of invalidating all of them.
        try core.appendEvent(
            db, kind: .createPrompt, subjectUuid: uuid,
            payload: Store.jsonPayload(
                ["seq": seq, "name": req.name, "session_uuid": req.sessionUuid]))
        // Item 3: prompt writes advance session recency (version untouched).
        try core.touchSession(db, uuid: req.sessionUuid)
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "prompt", key: uuid)
        }
        return row
    }

    /// nil sessionUuid lists every prompt in the db; a supplied-but-unknown
    /// uuid is a typed NOT_FOUND, never a silent empty list (the same
    /// optional-filter contract as Store+Listing).
    func list(_ req: PromptListRequest) throws -> PromptListResponse {
        if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
        }
        return PromptListResponse(prompts: try SessionRepository(db: db, core: core)
            .fetchPromptStubs(sessionUuid: req.sessionUuid, withReports: req.withReports ?? false))
    }

    func get(_ req: PromptGetRequest) throws -> PromptGetResponse {
        guard let prompt = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        let artifacts = try ArtifactRepository(db: db, core: core)
            .fetchRows(promptUuid: req.promptUuid)
        let kbiteCodes = try String.fetchAll(db, sql: """
            SELECT k.code FROM kbite k
            JOIN prompt_active_kbite j ON j.kbite_uuid = k.uuid
            WHERE j.prompt_uuid = ?
            ORDER BY k.code
            """, arguments: [req.promptUuid])
        let changeSummary = try SessionRepository(db: db, core: core)
            .changeSummary(where: "prompt_uuid = ?", arguments: [req.promptUuid])
        return PromptGetResponse(
            prompt: prompt,
            artifacts: artifacts,
            kbiteCodes: kbiteCodes,
            changeSummary: changeSummary
        )
    }

    /// STAY TRUE enforced in code: the backstory/goal/detail triple is
    /// editable only while status == draft.
    func updateContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        guard let statusRaw = try String.fetchOne(
            db, sql: "SELECT status FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let status = PromptStatus(rawValue: statusRaw) else {
            throw StoreError.corruptState(entity: "prompt", detail: "status '\(statusRaw)'")
        }
        guard status == .draft else {
            throw StoreError.contentLocked(status: status)
        }
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let backstory = req.backstory { set["backstory"] = backstory }
        if let goal = req.goal { set["goal"] = goal }
        if let detail = req.detail { set["detail"] = detail }
        guard !set.isEmpty else {
            throw StoreError.emptyUpdate(entity: "prompt")
        }
        try core.updateBase(
            db, table: "prompt", uuid: req.promptUuid,
            expectedVersion: req.expectedVersion, set: set)
        try core.appendEvent(
            db, kind: .updatePrompt, subjectUuid: req.promptUuid,
            payload: Store.jsonPayload(["fields": set.keys.sorted()]))
        guard let row = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        try core.touchSession(db, uuid: row.sessionUuid)
        return row
    }

    /// Lifecycle v2: forward-only, adjacent-only per PromptStatus.allowedNext
    /// (one skip edge, implementing → done). This is the SINGLE front door for
    /// prompt transitions — clarify/arch verbs never touch prompt.status.
    /// Gate coupling and create-on-enter side effects run inside this same
    /// write transaction:
    ///   draft → clarifying:        creates the clarification_summary
    ///   clarifying → architecting: requires it complete; creates the
    ///                              architecture_summary
    ///   architecting → implementing: requires the architecture approved
    /// Legacy (pre-m0002) prompts bypass absent-backing-row gates AND skip
    /// create-on-enter — creating a summary for one would wedge it a state
    /// later. They walk all six states on their ckfs artifacts; CLARIFY_OPEN
    /// is the explicit adoption path.
    func setStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        guard let head = try Row.fetchOne(
            db, sql: "SELECT status, created_at, session_uuid FROM prompt WHERE uuid = ?",
            arguments: [req.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        let statusRaw: String = head["status"]
        guard let from = PromptStatus(rawValue: statusRaw) else {
            throw StoreError.corruptState(entity: "prompt", detail: "status '\(statusRaw)'")
        }
        guard from.allowedNext.contains(req.status) else {
            throw StoreError.invalidTransition(
                from: from, to: req.status,
                reason: from.allowedNext.isEmpty
                    ? "\(from.rawValue) is terminal"
                    : "legal next from \(from.rawValue): "
                        + from.allowedNext.map(\.rawValue).sorted().joined(separator: ", "))
        }
        switch (from, req.status) {
        case (.draft, .clarifying):
            _ = try ClarificationRepository(db: db, core: core)
                .ensureSummary(promptUuid: req.promptUuid)
        case (.clarifying, .architecting):
            try requireSummaryStatus(
                table: "clarification_summary", entity: "clarification",
                promptUuid: req.promptUuid,
                expected: ClarificationStatus.complete.rawValue)
            _ = try ArchitectureRepository(db: db, core: core)
                .ensureSummary(promptUuid: req.promptUuid)
        case (.architecting, .implementing):
            try requireSummaryStatus(
                table: "architecture_summary", entity: "architecture",
                promptUuid: req.promptUuid,
                expected: ArchitectureStatus.approved.rawValue)
        default:
            // implementing → {reviewing, done} and reviewing → done stay
            // UNGATED (decision 7, advisory for one release). Their exit
            // contracts DO exist now — WorkflowGates.implementExitUnmet and
            // WorkflowGates.reviewFixExitUnmet — but they are only REPORTED,
            // through the blockers BOT_NEXT already prints, prefixed
            // `advisory: `. Refusing here today would block prompts that are
            // mid-flight against a capture path still being repaired.
            //
            // Promotion condition, both halves required: the advisories run
            // clean on real prompts, AND per-agent file-change attribution
            // has been watched across at least one parallel fan-out run
            // (N agents race one baseline cursor; prompt-level attribution
            // and change kinds are exact, agent_id is best-effort). Promote
            // by calling the two predicates from cases added here — not by
            // moving them into BotWorkflowRepository.entryBlockers, which
            // would derive already-done prompts backwards.
            break
        }
        try core.updateBase(
            db, table: "prompt", uuid: req.promptUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": req.status.rawValue])
        // Activation is a SIDE EFFECT of the lifecycle door, not a verb:
        // declaring work active already WAS set-status implementing. One
        // claim per running Claude instance (client_key), so concurrent
        // prompts on one session each keep their own claim — never a
        // last-writer-wins pointer. done releases the PROMPT's claim
        // regardless of which instance calls it.
        let sessionUuid: String = head["session_uuid"]
        if req.status == .implementing, let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core).claimActivation(
                sessionUuid: sessionUuid,
                promptUuid: req.promptUuid, clientKey: clientKey)
        } else if req.status == .done {
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE prompt_uuid = ?",
                arguments: [req.promptUuid])
            // m0025: done also closes the prompt's active workflow row.
            try BotWorkflowRepository(db: db, core: core).closeForPrompt(
                promptUuid: req.promptUuid)
        }
        try core.appendEvent(
            db, kind: .promptStatusChange, subjectUuid: req.promptUuid,
            payload: Store.jsonPayload(["from": from.rawValue, "to": req.status.rawValue]))
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        return row
    }

    /// Gate check shared by the lifecycle transitions: the backing summary
    /// must exist at the expected status.
    private func requireSummaryStatus(
        table: String,
        entity: String,
        promptUuid: String,
        expected: String
    ) throws {
        guard let actual = try String.fetchOne(
            db, sql: "SELECT status FROM \(table) WHERE prompt_uuid = ?", arguments: [promptUuid]
        ) else {
            throw StoreError.invalidEntityTransition(
                entity: "prompt", from: "gate", to: expected,
                reason: "no \(entity) summary exists for prompt \(promptUuid)")
        }
        guard actual == expected else {
            throw StoreError.invalidEntityTransition(
                entity: "prompt", from: actual, to: expected,
                reason: "\(entity) summary must be \(expected) first")
        }
    }

    // MARK: - Shared fetch helper

    func fetchRow(uuid: String) throws -> PromptRow? {
        try PromptRecord.fetch(db, uuid: uuid)?.wireRow()
    }
}
