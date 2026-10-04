import Foundation
import GRDB

/// PROMPT_* data access — the prompt lifecycle.
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never self-transacts.
struct PromptRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Creates a new prompt for the session.
    ///
    /// - Parameter req: Request containing the prompt metadata and session UUID.
    /// - Returns: The created prompt row.
    /// - Throws: `StoreError.notFound` if the session does not exist.
    func create(_ req: PromptCreateRequest) throws -> PromptRow {
        guard try SessionRecord.exists(db, key: ["uuid": req.sessionUuid]) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        // Atomic under the single writer: MAX+1 inside the write
        // transaction; UNIQUE(session_uuid, seq) is the backstop.
        let seq =
            try nextSeq(
                db,
                in: PromptRecord.self,
                parent: Column("session_uuid"),
                uuid: req.sessionUuid
            ) + 1
        let code = req.code ?? "p\(seq)"
        let gmfsPath = try resolveGmfsPath(for: req, seq: seq)
        let uuid = try core.insertBase(
            db,
            table: "prompt",
            extra: [
                "session_uuid": req.sessionUuid,
                "seq": seq,
                "code": code,
                "name": req.name,
                "backstory": req.backstory,
                "goal": req.goal,
                "detail": req.detail,
                "command": req.command ?? "",
                "status": PromptStatus.draft.rawValue,
                "gmfs_relative_storage_path": gmfsPath,
            ],
            uuid: req.uuid
        )
        try seedPromptKbites(promptUuid: uuid, sessionUuid: req.sessionUuid)
        // Item 4: payload carries session_uuid so GMVibes can route the
        // event to one session instead of invalidating all of them.
        try core.appendEvent(
            db,
            kind: .createPrompt,
            subjectUuid: uuid,
            payload: Store.jsonPayload(
                ["seq": seq, "name": req.name, "session_uuid": req.sessionUuid])
        )
        // Item 3: prompt writes advance session recency (version untouched).
        try core.touchSession(db, uuid: req.sessionUuid)
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "prompt", key: uuid)
        }
        return row
    }

    /// Resolves the gmfs folder a new prompt stores under, deriving it from the session when absent.
    ///
    /// - Parameters:
    ///   - req: The create request, whose supplied path wins when non-empty.
    ///   - seq: The prompt's per-session sequence number.
    /// - Returns: The relative storage path, or an empty string when none can be derived.
    /// - Throws: Any database error while reading the session's path.
    private func resolveGmfsPath(for req: PromptCreateRequest, seq: Int64) throws -> String {
        // Item 7: derive the gmfs folder daemon-side when the caller
        // doesn't supply one — the session row (same transaction) already
        // carries its own path, and the folder convention is
        // {seq}_{name}. Legacy rows stay empty (no backfill: a wrong path
        // is worse than an absent one).
        var gmfsPath = req.gmfsRelativeStoragePath ?? ""
        if gmfsPath.isEmpty {
            let sessionPath =
                try SessionRecord
                .all()
                .withUuid(req.sessionUuid)
                .select(SessionRecord.Columns.gmfsRelativeStoragePath, as: String.self)
                .fetchOne(db) ?? ""
            if !sessionPath.isEmpty {
                // A4: the name is slugged (forward-only, lossy) so the
                // stored path — which the MemoryWatcher matches by exact
                // case-sensitive equality — never contains spaces/slashes.
                // Clients MUST use this returned path verbatim, never
                // re-derive {seq}_{name} themselves.
                gmfsPath = "\(sessionPath)/prompts/\(seq)_\(Store.slugStorageSegment(req.name))"
            }
        }
        return gmfsPath
    }

    /// Copies the session's active kbites onto a newly created prompt.
    ///
    /// - Parameters:
    ///   - promptUuid: The new prompt's uuid.
    ///   - sessionUuid: The session whose kbite registry is inherited.
    /// - Throws: Any database error during the fetch or inserts.
    private func seedPromptKbites(promptUuid: String, sessionUuid: String) throws {
        // Seed prompt kbites from the session registry (create-time-only
        // inheritance, same rule as the context chain).
        let sessionKbites =
            try SessionActiveKbiteRecord
            .filter(SessionActiveKbiteRecord.Columns.sessionUuid == sessionUuid)
            .select(SessionActiveKbiteRecord.Columns.kbiteUuid, as: String.self)
            .fetchAll(db)
        for kbiteUuid in sessionKbites {
            try core.insertBase(
                db,
                table: "prompt_active_kbite",
                extra: [
                    "prompt_uuid": promptUuid,
                    "kbite_uuid": kbiteUuid,
                ]
            )
        }
    }

    /// Lists prompts for a session or all prompts.
    ///
    /// A nil sessionUuid lists every prompt in the database; a supplied-but-unknown
    /// uuid is a typed NOT_FOUND, never a silent empty list (the same optional-filter
    /// contract as Store+Listing).
    ///
    /// - Parameter req: Request containing the optional session UUID.
    /// - Returns: The list of prompts.
    /// - Throws: `StoreError.notFound` if the session UUID is supplied but not found.
    func list(_ req: PromptListRequest) throws -> PromptListResponse {
        if let sessionUuid = req.sessionUuid {
            guard try SessionRecord.exists(db, key: ["uuid": sessionUuid]) else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
        }
        return PromptListResponse(
            prompts: try SessionRepository(db: db, core: core)
                .fetchPromptStubs(sessionUuid: req.sessionUuid, withReports: req.withReports ?? false)
        )
    }

    /// Fetches the complete prompt state including artifacts and kbites.
    ///
    /// - Parameter req: Request containing the prompt UUID.
    /// - Returns: The prompt row with artifacts, kbite codes, and change summary.
    /// - Throws: `StoreError.notFound` if the prompt does not exist.
    func get(_ req: PromptGetRequest) throws -> PromptGetResponse {
        guard let prompt = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        let artifacts = try ArtifactRepository(db: db, core: core)
            .fetchRows(promptUuid: req.promptUuid)
        let kbiteCodes =
            try KbiteRecord
            .joining(
                required: KbiteRecord.promptActivations
                    .filter(Column("prompt_uuid") == req.promptUuid)
            )
            .order(Column("code"))
            .select(Column("code"), as: String.self)
            .fetchAll(db)
        let changeSummary = try SessionRepository(db: db, core: core)
            .changeSummary(promptUuid: req.promptUuid)
        return PromptGetResponse(
            prompt: prompt,
            artifacts: artifacts,
            kbiteCodes: kbiteCodes,
            changeSummary: changeSummary
        )
    }

    /// Updates prompt content when the status is draft.
    ///
    /// The backstory/goal/detail triple is editable only while status == draft.
    /// This is enforced in code.
    ///
    /// - Parameter req: Request containing the prompt UUID and fields to update.
    /// - Returns: The updated prompt row.
    /// - Throws: `StoreError.contentLocked` if the prompt is not in draft status.
    func updateContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        guard
            let statusRaw =
                try PromptRecord
                .all()
                .withUuid(req.promptUuid)
                .select(PromptRecord.Columns.status, as: String.self)
                .fetchOne(db)
        else {
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
            db,
            table: "prompt",
            uuid: req.promptUuid,
            expectedVersion: req.expectedVersion,
            set: set
        )
        try core.appendEvent(
            db,
            kind: .updatePrompt,
            subjectUuid: req.promptUuid,
            payload: Store.jsonPayload(["fields": set.keys.sorted()])
        )
        guard let row = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        try core.touchSession(db, uuid: row.sessionUuid)
        return row
    }

    /// Transitions the prompt status and handles activation claims.
    ///
    /// The single front door for prompt transitions: forward-only and adjacent-only per
    /// `PromptStatus.allowedNext`, with one skip edge. Clarify and architecture verbs
    /// never touch prompt.status. Activation claim and workflow close ride this same
    /// write transaction.
    ///
    /// - Parameter req: Request containing the prompt UUID, new status, and optional client key.
    /// - Returns: The updated prompt row.
    /// - Throws: `StoreError.invalidTransition` if the status change is not allowed.
    func setStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        guard let head = try PromptRecord.fetch(db, uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let from = PromptStatus(rawValue: head.status) else {
            throw StoreError.corruptState(entity: "prompt", detail: "status '\(head.status)'")
        }
        guard from.allowedNext.contains(req.status) else {
            throw StoreError.invalidTransition(
                from: from,
                to: req.status,
                reason: from.allowedNext.isEmpty
                    ? "\(from.rawValue) is terminal"
                    : "legal next from \(from.rawValue): "
                        + from.allowedNext.map(\.rawValue).sorted().joined(separator: ", ")
            )
        }
        // NO GATE SWITCH, deliberately. The only moves are draft → initiated →
        // done plus the done → draft edit edge, so there is nothing to gate
        // between. Summaries are created by explicit opens — CLARIFY_OPEN,
        // ARCH_OPTION_ADD, REVIEW_OPEN — so opening one is a call an agent
        // makes, never something that happens to it while moving a status.
        // Nothing reimplements the refusal: BOT_NEXT's gate blockers report
        // what a phase is waiting on advisorily, matching the registry's stance
        // that the machine classifies and guides but does not authorize.
        try core.updateBase(
            db,
            table: "prompt",
            uuid: req.promptUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": req.status.rawValue]
        )
        // Activation is a SIDE EFFECT of the lifecycle door, not a verb:
        // declaring work active already IS moving the status. One claim per
        // running Claude instance (client_key), so concurrent prompts on one
        // session each keep their own claim rather than a last-writer-wins
        // pointer, and `done` releases the PROMPT's claim whichever instance
        // calls it. The claim is taken at `initiated`, so briefing, exploration
        // and architecture all run under it.
        let sessionUuid = head.sessionUuid
        if req.status == .initiated, let clientKey = req.clientKey {
            try SessionRepository(db: db, core: core)
                .claimActivation(
                    sessionUuid: sessionUuid,
                    promptUuid: req.promptUuid,
                    clientKey: clientKey
                )
        } else if req.status == .done {
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE prompt_uuid = ?",
                arguments: [req.promptUuid]
            )
            // m0025: done also closes the prompt's active workflow row.
            try BotWorkflowRepository(db: db, core: core)
                .closeForPrompt(
                    promptUuid: req.promptUuid
                )
        }
        try core.appendEvent(
            db,
            kind: .promptStatusChange,
            subjectUuid: req.promptUuid,
            payload: Store.jsonPayload(["from": from.rawValue, "to": req.status.rawValue])
        )
        try core.touchSession(db, uuid: sessionUuid)
        guard let row = try fetchRow(uuid: req.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        return row
    }

    // `requireSummaryStatus` lived here until m0028 and is deliberately gone
    // rather than left unused. It read one summary table's status and refused
    // the transition unless it matched — the enforcement half of the gate
    // switch above. With no transitions left to gate it had no caller, and a
    // private helper kept "for later" is how a removed rule quietly comes back.
    // The queries it ran are trivial to write again if a gate is ever wanted.

    // MARK: - Shared fetch helper

    /// Fetches and converts a prompt record to a DTO.
    ///
    /// - Parameter uuid: The prompt UUID.
    /// - Returns: The prompt row, or nil if not found.
    /// - Throws: `StoreError` on database failure.
    func fetchRow(uuid: String) throws -> PromptRow? {
        try PromptRecord.fetch(db, uuid: uuid)?.dto()
    }
}
