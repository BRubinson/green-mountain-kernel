import Foundation
import GRDB

/// FILE_CHANGE_ADD / FILE_CHANGE_LIST data access. Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct FileChangeRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Ensure the project → instance → session chain exists, then record the
    /// file change: session_file upsert, file_change row, one row per range,
    /// and the FILE_CHANGE daemon_event — all composed by the caller's single
    /// transaction so a change and its event commit atomically.
    ///
    /// Two gates run BEFORE any of that: the claude_session_binding gate, and
    /// the (tool call, file) idempotency check.
    func add(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        // A dangling prompt reference must be a typed NOT_FOUND, not the
        // opaque FK DB_ERROR the insert below would produce.
        if let promptUuid = req.promptUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
        }
        // origin vocabulary — provenance honesty, so an inferred
        // command-derived row never masquerades as an exact hook row. The
        // column has no CHECK constraint, so THIS guard is the whole
        // constraint: it reads the one shared list (FileChangeOrigin.all)
        // rather than a local literal, because a value the dope enum accepts
        // and this guard rejects throws on every write — and the hook callers
        // that exit 0 by design swallow the throw and record nothing.
        let origin = req.origin ?? FileChangeOrigin.hook
        guard FileChangeOrigin.all.contains(origin) else {
            throw StoreError.badRequest(
                detail: "origin must be \(FileChangeOrigin.vocabulary) (got '\(origin)')")
        }
        // THE BINDING GATE. A write that names a Claude conversation is
        // payload-borne, and a payload-borne write resolves through the
        // binding or not at all — this is the server-side half of the no-op
        // contract, and it is strictly stronger than the env gate it replaces
        // (which only ever tested whether one variable survived a
        // subprocess).
        //
        // It runs before the ensure chain on purpose: ensureProject/
        // ensureInstance CREATE rows, so after them every repo looks booted
        // and the loud/silent distinction below collapses.
        var boundSessionUuid: String?
        if let claudeSessionId = req.claudeSessionId {
            boundSessionUuid = try claudeSessionBinding.resolveSession(
                claudeSessionId: claudeSessionId)
            guard boundSessionUuid != nil else {
                throw StoreError.hookUnbound(
                    claudeSessionId: claudeSessionId,
                    booted: try bootedInstanceUuid(req) != nil)
            }
        }
        let context = ContextRepository(db: db, core: core)
        let (projectUuid, _) = try context.ensureProject(req.project)
        let (instanceUuid, _) = try context.ensureInstance(req.instance, projectUuid: projectUuid)
        let (sessionUuid, _) = try context.ensureSession(req.session, instanceUuid: instanceUuid)
        // The comparison join key: normalized at the boundary so
        // architecture change rows and file changes always meet on the
        // same repo-relative string (absolute-outside-instance rejected).
        let relativePath = try Store.normalizeRepoRelativePath(
            req.relativePath, repoRoot: req.instance.absoluteFileSystemPath)

        // IDEMPOTENCY, as an explicit already-recorded SUCCESS. The point
        // query comes before ensureSessionFile because that call bumps
        // session_file.version — a replay must leave the db byte-identical,
        // and must not look like a second edit to a subscriber, so it also
        // appends no event and does not touchSession.
        if let toolUseId = req.toolUseId,
           let recorded = try recordedChange(
               toolUseId: toolUseId, sessionUuid: sessionUuid, relativePath: relativePath) {
            return recorded
        }

        let sessionFileUuid = try ensureSessionFile(
            sessionUuid: sessionUuid,
            relativePath: relativePath,
            changeKind: req.changeKind
        )
        // OPT-IN attribution: the long-standing "omitted prompt means
        // deliberately session-scoped" semantic stays intact for every other
        // caller; only autoAttribute callers resolve a prompt, and an
        // unresolvable one leaves the change unattributed — never a guess
        // between two concurrent prompts.
        //
        // Only the PROMPT comes from the bound session; session_uuid and
        // session_file above stay cwd-derived, which is where the accepted
        // branch-switch staleness comes from (see resolveAttributedPrompt). A
        // caller with no conversation to name resolves the same ladder
        // against the session its cwd landed in.
        var attributedPromptUuid = req.promptUuid
        if attributedPromptUuid == nil, req.autoAttribute == true {
            attributedPromptUuid = try resolveAttributedPrompt(
                sessionUuid: boundSessionUuid ?? sessionUuid)
        }
        // workflow_phase is stamped SERVER-SIDE and DERIVED LIVE (the
        // machine's doctrine — last_served_phase is observability only and
        // stales between bot-next calls): a handful of indexed point
        // queries in the same transaction.
        var workflowPhase: String?
        if let promptUuid = attributedPromptUuid {
            let workflows = BotWorkflowRepository(db: db, core: core)
            if let workflow = try workflows.fetchActive(promptUuid: promptUuid),
               let variant = BotVariant(rawValue: workflow.variant) {
                workflowPhase = try workflows.derivePhase(
                    workflow: workflow, variant: variant).0.rawValue
            }
        }
        // The FK is satisfied by CONSTRUCTION rather than by precondition: an
        // agent whose registration is missing gets one invented from this
        // payload (loudly), so no agent's change is ever dropped for want of
        // a SubagentStart that did not run. nil is the PRIMARY, which carries
        // no agent_id at all.
        let agentRegistrationUuid = try agentRegistration.ensureRegistration(
            agentId: req.agentId,
            from: .init(
                agentType: req.agentType,
                claudeSessionId: req.claudeSessionId,
                claudeTurnId: req.claudeTurnId,
                sessionUuid: sessionUuid,
                promptUuid: attributedPromptUuid))

        let fileChangeUuid: String
        do {
            fileChangeUuid = try core.insertBase(db, table: "file_change", extra: [
                "session_file_uuid": sessionFileUuid,
                "session_uuid": sessionUuid,
                "prompt_uuid": attributedPromptUuid,
                "change_kind": req.changeKind.rawValue,
                "agent_id": req.agentId,
                "agent_name": req.agentName.map(Store.normalizedAgentName),
                "workflow_phase": workflowPhase,
                "origin": origin,
                "claude_session_id": req.claudeSessionId,
                "claude_turn_id": req.claudeTurnId,
                "tool_use_id": req.toolUseId,
                "tool_name": req.toolName,
                "agent_type": req.agentType,
                "permission_mode": req.permissionMode,
                "duration_ms": req.durationMs,
                "transcript_path": req.transcriptPath,
                "agent_registration_uuid": agentRegistrationUuid,
            ])
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT
            && error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            // The partial UNIQUE fired after the point query above passed.
            // Map it to the SAME already-recorded success rather than an
            // error: the caller asked for this row to exist and it does.
            // SQLite aborts the statement, not the transaction, so the
            // surrounding work stands.
            //
            // NARROWED TO *_UNIQUE ON PURPOSE. A bare SQLITE_CONSTRAINT also
            // covers the foreign keys on this insert — and this train just
            // added one, agent_registration_uuid — so the wide form could
            // report a genuine FK failure as a dedup success whenever a row
            // matching (tool_use_id, session, path) happened to exist. The
            // catch may only ever mean the thing it claims to mean.
            guard let toolUseId = req.toolUseId,
                  let recorded = try recordedChange(
                      toolUseId: toolUseId,
                      sessionUuid: sessionUuid,
                      relativePath: relativePath)
            else { throw error }
            return recorded
        }

        // The size budget on append-only history: a regenerated file can
        // produce thousands of hunks and megabytes of body, and nothing
        // trims file_change_range afterwards.
        var rangeUuids: [String] = []
        for range in req.ranges.prefix(FileChangeLimits.maxRangesPerChange) {
            let rangeUuid = try core.insertBase(db, table: "file_change_range", extra: [
                "file_change_uuid": fileChangeUuid,
                "line_start": range.lineStart,
                "line_end": range.lineEnd,
                "changed_content": range.changedContent.map {
                    String($0.prefix(FileChangeLimits.maxChangedContentCharacters))
                },
            ])
            rangeUuids.append(rangeUuid)
        }

        // Item 4: session_uuid in the payload lets GMVibes route the
        // event to one session instead of invalidating all of them.
        try core.appendEvent(
            db,
            kind: .fileChange,
            subjectUuid: fileChangeUuid,
            payload: Store.jsonPayload([
                "relative_path": relativePath,
                "change_kind": req.changeKind.rawValue,
                "ranges": rangeUuids.count,
                "session_uuid": sessionUuid,
            ])
        )
        // Item 3: file-change writes advance session recency.
        try core.touchSession(db, uuid: sessionUuid)

        return FileChangeAddResponse(
            sessionFileUuid: sessionFileUuid,
            fileChangeUuid: fileChangeUuid,
            rangeUuids: rangeUuids
        )
    }

    // MARK: - Attribution

    /// The prompt a change belongs to, resolved from ONE session and nothing
    /// else. Both rungs demand that the answer be unique; a session running
    /// two prompts at once returns nil, and the change is recorded
    /// session-scoped rather than guessed onto one of them.
    ///
    /// ACCEPTED BEHAVIOUR, deliberate and not a gap: for a payload-borne write
    /// the session passed here is the one the conversation was PINNED to,
    /// while the row's own session_uuid and session_file stay cwd-derived. So
    /// after a mid-session `git checkout`, changes land in the new branch's
    /// session attributed to the old branch's prompt, with no signal. That
    /// was decided rather than overlooked: detecting it would need a drift
    /// check, a branch column or a re-bind, all three of which were declined,
    /// and claude_session_binding deliberately holds no column that could
    /// support one.
    func resolveAttributedPrompt(sessionUuid: String) throws -> String? {
        let workflowPrompts = try String.fetchAll(
            db,
            sql: "SELECT prompt_uuid FROM bot_workflow WHERE session_uuid = ? AND status = 'active'",
            arguments: [sessionUuid])
        if workflowPrompts.count == 1 { return workflowPrompts[0] }
        let implementing = try String.fetchAll(
            db,
            sql: "SELECT uuid FROM prompt WHERE session_uuid = ? AND status = ?",
            arguments: [sessionUuid, PromptStatus.implementing.rawValue])
        if implementing.count == 1 { return implementing[0] }
        return nil
    }

    /// Durable trace for a refused payload-borne write, appended by
    /// `Store.addFileChange` in its OWN transaction — inside the refused write
    /// it would roll back with it, and an event that vanishes is precisely the
    /// silence this replaces.
    ///
    /// Only a repo the daemon KNOWS gets one. A PostToolUse hook fires in
    /// every repo on the machine, so an unknown one producing an unbound
    /// payload is ordinary and silent; a known one producing it is dead
    /// capture.
    func recordUnbound(_ req: FileChangeAdd, claudeSessionId: String) throws {
        guard let instanceUuid = try bootedInstanceUuid(req) else { return }
        var payload: [String: Any] = [
            "claude_session_id": claudeSessionId,
            // The RAW path: normalization can itself reject, and the point of
            // the event is to say what was lost.
            "relative_path": req.relativePath,
        ]
        if let toolName = req.toolName { payload["tool_name"] = toolName }
        if let toolUseId = req.toolUseId { payload["tool_use_id"] = toolUseId }
        if let agentId = req.agentId { payload["agent_id"] = agentId }
        try core.appendEvent(
            db, kind: .hookUnbound, subjectUuid: instanceUuid,
            payload: Store.jsonPayload(payload))
    }

    /// Read-only bootedness: has this repo ever been through CONTEXT_ENSURE?
    /// Tested at the INSTANCE rather than the session, because a
    /// branch whose session row is missing is exactly the state an unbound
    /// payload comes from — calling that "unbooted" would silence the case
    /// the event exists for.
    private func bootedInstanceUuid(_ req: FileChangeAdd) throws -> String? {
        guard let projectUuid = try String.fetchOne(
            db, sql: "SELECT uuid FROM project WHERE code = ?", arguments: [req.project.code]
        ) else { return nil }
        return try String.fetchOne(
            db,
            sql: "SELECT uuid FROM instance WHERE project_uuid = ? AND name = ?",
            arguments: [projectUuid, req.instance.name])
    }

    /// The existing row for a (tool call, file) pair, as the response a fresh
    /// write would have produced. The pair — not tool_use_id alone — is the
    /// unit: one `sed -i a b c` is one tool_use_id and three rows.
    private func recordedChange(
        toolUseId: String, sessionUuid: String, relativePath: String
    ) throws -> FileChangeAddResponse? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT fc.uuid AS file_change_uuid, sf.uuid AS session_file_uuid
                FROM file_change fc
                JOIN session_file sf ON sf.uuid = fc.session_file_uuid
                WHERE fc.tool_use_id = ? AND sf.session_uuid = ? AND sf.relative_path = ?
                """,
            arguments: [toolUseId, sessionUuid, relativePath]
        ) else { return nil }
        let fileChangeUuid: String = row["file_change_uuid"]
        let rangeUuids = try String.fetchAll(
            db,
            sql: "SELECT uuid FROM file_change_range WHERE file_change_uuid = ? ORDER BY id",
            arguments: [fileChangeUuid])
        return FileChangeAddResponse(
            sessionFileUuid: row["session_file_uuid"],
            fileChangeUuid: fileChangeUuid,
            rangeUuids: rangeUuids,
            deduplicated: true)
    }

    /// nil sessionUuid means no session filter (whole-db query); a
    /// supplied-but-unknown uuid is a typed NOT_FOUND, never a silent empty
    /// list (the same optional-filter contract as Store+Listing).
    func list(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            conditions.append("fc.session_uuid = ?")
            arguments.append(sessionUuid)
        }
        if let promptUuid = req.promptUuid {
            conditions.append("fc.prompt_uuid = ?")
            arguments.append(promptUuid)
        }
        if let relativePath = req.relativePath {
            conditions.append("sf.relative_path = ?")
            arguments.append(relativePath)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let limit = min(max(req.limit ?? 200, 1), 10_000)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT fc.uuid, fc.session_uuid, fc.prompt_uuid, fc.change_kind, fc.created_at,
                       fc.agent_id, fc.agent_name, fc.workflow_phase, fc.origin,
                       fc.claude_session_id, fc.claude_turn_id, fc.tool_use_id, fc.tool_name,
                       fc.agent_type, fc.permission_mode, fc.duration_ms, fc.transcript_path,
                       fc.agent_registration_uuid,
                       sf.relative_path
                FROM file_change fc
                JOIN session_file sf ON sf.uuid = fc.session_file_uuid
                \(whereClause)
                ORDER BY fc.id DESC
                LIMIT \(limit)
                """,
            arguments: StatementArguments(arguments))
        // One IN(...) prefetch of all ranges grouped in memory — 2
        // statements total, not one per returned row (251 at limit 250).
        let uuids = rows.map { $0["uuid"] as String }
        var rangesByChange: [String: [ChangeRangeRow]] = [:]
        if !uuids.isEmpty {
            let placeholders = Array(repeating: "?", count: uuids.count).joined(separator: ", ")
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT file_change_uuid, line_start, line_end FROM file_change_range
                    WHERE file_change_uuid IN (\(placeholders)) ORDER BY id
                    """,
                arguments: StatementArguments(uuids)
            ) {
                let changeUuid: String = row["file_change_uuid"]
                rangesByChange[changeUuid, default: []].append(
                    ChangeRangeRow(lineStart: row["line_start"], lineEnd: row["line_end"]))
            }
        }
        let changes = rows.map { row -> FileChangeRow in
            let uuid: String = row["uuid"]
            return FileChangeRow(
                uuid: uuid,
                sessionUuid: row["session_uuid"],
                promptUuid: row["prompt_uuid"],
                relativePath: row["relative_path"],
                changeKind: row["change_kind"],
                agentId: row["agent_id"],
                agentName: row["agent_name"],
                workflowPhase: row["workflow_phase"],
                origin: row["origin"],
                claudeSessionId: row["claude_session_id"],
                claudeTurnId: row["claude_turn_id"],
                toolUseId: row["tool_use_id"],
                toolName: row["tool_name"],
                agentType: row["agent_type"],
                permissionMode: row["permission_mode"],
                durationMs: row["duration_ms"],
                transcriptPath: row["transcript_path"],
                agentRegistrationUuid: row["agent_registration_uuid"],
                createdAt: row["created_at"],
                ranges: rangesByChange[uuid] ?? []
            )
        }
        return FileChangeListResponse(changes: changes)
    }

    // MARK: - session_file upsert

    func ensureSessionFile(
        sessionUuid: String,
        relativePath: String,
        changeKind: ChangeKind
    ) throws -> String {
        // Deleted files stay as rows marked inactive; anything else re-activates.
        let active = changeKind == .delete ? 0 : 1
        if let existing = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM session_file WHERE session_uuid = ? AND relative_path = ?",
            arguments: [sessionUuid, relativePath]
        ) {
            try db.execute(
                sql: "UPDATE session_file SET active = ?, version = version + 1, updated_at = ? WHERE uuid = ?",
                arguments: [active, Store.isoNow(), existing]
            )
            return existing
        }
        return try core.insertBase(db, table: "session_file", extra: [
            "session_uuid": sessionUuid,
            "relative_path": relativePath,
            "active": active,
        ])
    }
}
