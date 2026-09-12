import Foundation
import GRDB

/// SESSION_GET / SESSION_UPDATE data access, plus the activation registry
/// (v21) and the shared prompt-stub/change-summary aggregations. Runs INSIDE
/// a Store-owned transaction; holds no dbQueue and never self-transacts.
struct SessionRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        guard let session = try fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        let prompts = try fetchPromptStubs(sessionUuid: req.sessionUuid)
        let changeSummary = try changeSummary(
            where: "session_uuid = ?", arguments: [req.sessionUuid])
        let promptChanges = try promptChangeSummaries(sessionUuid: req.sessionUuid)
        return SessionGetResponse(
            session: session,
            prompts: prompts,
            changeSummary: changeSummary,
            promptChanges: promptChanges
        )
    }

    func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let name = req.name { set["name"] = name }
        if let backstory = req.backstory { set["backstory"] = backstory }
        if let goal = req.goal { set["goal"] = goal }
        // Manual override of the activation claim PROMPT_SET_STATUS
        // normally maintains for the calling instance. Exactly one of
        // the pair; the prompt must belong to this session (a Swift
        // guard — CHECK cannot cross tables).
        var activationTouched = false
        if let activePromptUuid = req.activePromptUuid {
            guard req.clearActivePrompt != true else {
                throw StoreError.badRequest(
                    detail: "activePromptUuid and clearActivePrompt are mutually exclusive")
            }
            guard let clientKey = req.clientKey else {
                throw StoreError.badRequest(
                    detail: "activation claims need a client key — run via gm, which resolves it")
            }
            guard let owner = try String.fetchOne(
                db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?",
                arguments: [activePromptUuid]
            ) else {
                throw StoreError.notFound(entity: "prompt", key: activePromptUuid)
            }
            guard owner == req.sessionUuid else {
                throw StoreError.badRequest(
                    detail: "prompt \(activePromptUuid) belongs to session \(owner), not \(req.sessionUuid)")
            }
            try claimActivation(
                sessionUuid: req.sessionUuid,
                promptUuid: activePromptUuid, clientKey: clientKey)
            activationTouched = true
        } else if req.clearActivePrompt == true {
            guard let clientKey = req.clientKey else {
                throw StoreError.badRequest(
                    detail: "activation claims need a client key — run via gm, which resolves it")
            }
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE client_key = ?",
                arguments: [clientKey])
            activationTouched = true
        }
        guard !set.isEmpty || activationTouched else {
            throw StoreError.emptyUpdate(entity: "session")
        }
        if !set.isEmpty {
            try core.updateBase(
                db, table: "session", uuid: req.sessionUuid,
                expectedVersion: req.expectedVersion, set: set)
        }
        try core.appendEvent(
            db, kind: .updateSession, subjectUuid: req.sessionUuid,
            payload: Store.jsonPayload(["fields": set.keys.sorted()]))
        guard let row = try fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        return row
    }

    // MARK: - Shared fetch helpers

    func fetchRow(uuid: String) throws -> SessionRow? {
        try SessionRecord.fetch(db, uuid: uuid)?
            .wireRow(activations: try fetchActivations(sessionUuid: uuid))
    }

    // MARK: - Activation registry (v21)

    /// One claim per running Claude instance (client_key) and per prompt:
    /// re-claiming replaces both sides' old rows so the two partial-unique
    /// indexes can never collide on a legitimate re-claim.
    func claimActivation(
        sessionUuid: String, promptUuid: String, clientKey: String
    ) throws {
        try evictDeadActivations(sessionUuid: sessionUuid)
        try db.execute(
            sql: "DELETE FROM prompt_activation WHERE client_key = ? OR prompt_uuid = ?",
            arguments: [clientKey, promptUuid])
        _ = try core.insertBase(db, table: "prompt_activation", extra: [
            "session_uuid": sessionUuid,
            "prompt_uuid": promptUuid,
            "client_key": clientKey,
        ])
    }

    /// Opportunistic liveness eviction (review finding 033dad8f): only
    /// `done` releases a claim, so a crashed/restarted Claude instance would
    /// otherwise poison the single-claim fallback forever. The key embeds
    /// pid + start time, so liveness is checkable server-side; unknown key
    /// shapes are left alone (they can't lie about liveness we can't check).
    func evictDeadActivations(sessionUuid: String) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT uuid, client_key FROM prompt_activation WHERE session_uuid = ?",
            arguments: [sessionUuid])
        for row in rows where !Store.clientKeyLooksAlive(row["client_key"]) {
            try db.execute(
                sql: "DELETE FROM prompt_activation WHERE uuid = ?",
                arguments: [row["uuid"] as String])
        }
    }

    func fetchActivations(sessionUuid: String) throws -> [PromptActivationRow] {
        try PromptActivationRecord.fetchAll(
            db, where: "session_uuid = ?", arguments: [sessionUuid],
            orderBy: "created_at"
        ).map { $0.wireRow() }
    }

    /// The attribution ladder shared by file-change auto-attribution and the
    /// briefing active resolution: the caller's own claim first, then the
    /// session's single claim when unambiguous, else nil (never a guess
    /// between two concurrent prompts).
    func resolveActivePrompt(
        sessionUuid: String, clientKey: String?
    ) throws -> String? {
        // Dead claims are FILTERED here rather than deleted: this runs inside
        // read transactions (briefing get/stub). Deletion happens on the
        // write paths (claimActivation) — filtering keeps read results
        // correct in the meantime.
        let live = try fetchActivations(sessionUuid: sessionUuid)
            .filter { Store.clientKeyLooksAlive($0.clientKey) }
        if let clientKey, let own = live.first(where: { $0.clientKey == clientKey }) {
            return own.promptUuid
        }
        return live.count == 1 ? live[0].promptUuid : nil
    }

    /// nil sessionUuid = every prompt in the db, grouped by session (seq is
    /// only unique per session, hence the two-column ORDER BY). withReports
    /// attaches the per-prompt clarification/architecture/exploration/review
    /// summary stubs via four grouped aggregate queries folded into
    /// dictionaries — one grouped aggregation per machine, never per-row (a
    /// per-prompt fetch here would be the N+1 the enrichment exists to
    /// delete).
    func fetchPromptStubs(
        sessionUuid: String?, withReports: Bool = false
    ) throws -> [PromptStub] {
        let sql: String
        let arguments: StatementArguments
        if let sessionUuid {
            sql = """
                SELECT uuid, session_uuid, seq, code, name, status, version,
                       ckfs_relative_storage_path, created_at, updated_at
                FROM prompt WHERE session_uuid = ? ORDER BY seq
                """
            arguments = [sessionUuid]
        } else {
            sql = """
                SELECT uuid, session_uuid, seq, code, name, status, version,
                       ckfs_relative_storage_path, created_at, updated_at
                FROM prompt ORDER BY session_uuid, seq
                """
            arguments = []
        }
        var clar: [String: ClarificationReportStub] = [:]
        var arch: [String: ArchitectureReportStub] = [:]
        var explore: [String: ExplorationReportStub] = [:]
        var review: [String: ReviewReportStub] = [:]
        if withReports {
            let scope = sessionUuid == nil
                ? ""
                : "WHERE cs.prompt_uuid IN (SELECT uuid FROM prompt WHERE session_uuid = ?)"
            let scopeArgs: StatementArguments = sessionUuid.map { [$0] } ?? []
            // m0025: questions/notes are the split children; the care
            // package flag surfaces the clarified-intent artifact.
            for row in try Row.fetchAll(db, sql: """
                SELECT cs.prompt_uuid, cs.uuid, cs.version, cs.status,
                       COUNT(q.uuid) AS q_count,
                       COALESCE(SUM(q.status = 'open'), 0) AS open_count,
                       (SELECT COUNT(*) FROM internal_clarification_note n
                        WHERE n.clarification_summary_uuid = cs.uuid) AS note_count,
                       EXISTS(SELECT 1 FROM care_package cp
                              WHERE cp.clarification_summary_uuid = cs.uuid
                                AND cp.status = 'ready') AS package_ready
                FROM clarification_summary cs
                LEFT JOIN user_clarification_question q
                    ON q.clarification_summary_uuid = cs.uuid
                \(scope)
                GROUP BY cs.uuid
                """, arguments: scopeArgs) {
                clar[row["prompt_uuid"]] = ClarificationReportStub(
                    summaryUuid: row["uuid"],
                    version: row["version"],
                    status: row["status"],
                    questionCount: row["q_count"],
                    openQuestionCount: row["open_count"],
                    noteCount: row["note_count"],
                    carePackageReady: (row["package_ready"] as Int64) != 0
                )
            }
            for row in try Row.fetchAll(db, sql: """
                SELECT cs.prompt_uuid, cs.uuid, cs.version, cs.status,
                       (SELECT COUNT(*) FROM architecture_persistence_change pc
                        WHERE pc.architecture_summary_uuid = cs.uuid) AS p_count,
                       (SELECT COUNT(*) FROM architecture_general_change gc
                        WHERE gc.architecture_summary_uuid = cs.uuid) AS g_count
                FROM architecture_summary cs
                \(scope)
                """, arguments: scopeArgs) {
                arch[row["prompt_uuid"]] = ArchitectureReportStub(
                    summaryUuid: row["uuid"],
                    version: row["version"],
                    status: row["status"],
                    persistenceChangeCount: row["p_count"],
                    generalChangeCount: row["g_count"]
                )
            }
            // m0025: summaries are per-agent — the stub aggregates the
            // PROMPT: counts span every summary; the representative row is
            // the synthesis (seal) row when present. key_file findings are
            // path anchors — counted separately, excluded from ranking math.
            for row in try Row.fetchAll(db, sql: """
                SELECT cs.prompt_uuid,
                       COALESCE(
                           MAX(CASE WHEN cs.agent_type = 'synthesis' THEN cs.uuid END),
                           MIN(cs.uuid)) AS rep_uuid,
                       COALESCE(
                           MAX(CASE WHEN cs.agent_type = 'synthesis' THEN cs.version END),
                           0) AS rep_version,
                       COALESCE(
                           MAX(CASE WHEN cs.agent_type = 'synthesis' THEN cs.status END),
                           'exploring') AS rep_status,
                       (SELECT COALESCE(SUM(f.kind = 'key_file'), 0)
                        FROM exploration_finding f
                        JOIN exploration_summary es ON es.uuid = f.exploration_summary_uuid
                        WHERE es.prompt_uuid = cs.prompt_uuid) AS kf_count,
                       (SELECT COUNT(*)
                        FROM exploration_finding f
                        JOIN exploration_summary es ON es.uuid = f.exploration_summary_uuid
                        WHERE es.prompt_uuid = cs.prompt_uuid AND f.kind != 'key_file') AS f_count,
                       (SELECT COALESCE(SUM(f.finding_rating < 100), 0)
                        FROM exploration_finding f
                        JOIN exploration_summary es ON es.uuid = f.exploration_summary_uuid
                        WHERE es.prompt_uuid = cs.prompt_uuid AND f.kind != 'key_file') AS sub100_count,
                       (SELECT COUNT(*)
                        FROM exploration_finding f
                        JOIN exploration_summary es ON es.uuid = f.exploration_summary_uuid
                        WHERE es.prompt_uuid = cs.prompt_uuid AND f.kind != 'key_file'
                          AND f.finding_rating IS NULL) AS unranked_count
                FROM exploration_summary cs
                \(scope)
                GROUP BY cs.prompt_uuid
                """, arguments: scopeArgs) {
                explore[row["prompt_uuid"]] = ExplorationReportStub(
                    summaryUuid: row["rep_uuid"],
                    version: row["rep_version"],
                    status: row["rep_status"],
                    keyFileCount: row["kf_count"],
                    findingCount: row["f_count"],
                    sub100FindingCount: row["sub100_count"],
                    unrankedFindingCount: row["unranked_count"]
                )
            }
            for row in try Row.fetchAll(db, sql: """
                SELECT cs.prompt_uuid, cs.uuid, cs.version, cs.status, cs.verdict,
                       COUNT(f.uuid) AS f_count,
                       COALESCE(SUM(f.finding_rating < 100), 0) AS sub100_count,
                       COUNT(f.uuid) - COUNT(f.finding_rating) AS unranked_count,
                       COALESCE(SUM(f.status = 'open'), 0) AS open_count
                FROM review_summary cs
                LEFT JOIN review_finding f ON f.review_summary_uuid = cs.uuid
                \(scope)
                GROUP BY cs.uuid
                """, arguments: scopeArgs) {
                review[row["prompt_uuid"]] = ReviewReportStub(
                    summaryUuid: row["uuid"],
                    version: row["version"],
                    status: row["status"],
                    verdict: row["verdict"],
                    findingCount: row["f_count"],
                    sub100FindingCount: row["sub100_count"],
                    unrankedFindingCount: row["unranked_count"],
                    openFindingCount: row["open_count"]
                )
            }
        }
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let uuid: String = row["uuid"]
            return PromptStub(
                uuid: uuid,
                sessionUuid: row["session_uuid"],
                seq: row["seq"],
                code: row["code"],
                name: row["name"],
                status: row["status"],
                version: row["version"],
                ckfsRelativeStoragePath: row["ckfs_relative_storage_path"],
                reports: withReports
                    ? PromptReportsStub(
                        clarification: clar[uuid], architecture: arch[uuid],
                        exploration: explore[uuid], review: review[uuid])
                    : nil,
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    /// One grouped aggregation: file_change row count, distinct files touched,
    /// and total line span from the joined ranges.
    func changeSummary(
        where condition: String,
        arguments: StatementArguments
    ) throws -> ChangeSummary {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT
                    COUNT(DISTINCT fc.uuid) AS change_count,
                    COUNT(DISTINCT fc.session_file_uuid) AS distinct_files,
                    COALESCE(SUM(r.line_end - r.line_start + 1), 0) AS total_line_span
                FROM file_change fc
                LEFT JOIN file_change_range r ON r.file_change_uuid = fc.uuid
                WHERE fc.\(condition)
                """,
            arguments: arguments
        )
        return ChangeSummary(
            changeCount: row?["change_count"] ?? 0,
            distinctFiles: row?["distinct_files"] ?? 0,
            totalLineSpan: row?["total_line_span"] ?? 0
        )
    }

    func promptChangeSummaries(sessionUuid: String) throws -> [PromptChangeSummary] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT
                    fc.prompt_uuid AS prompt_uuid,
                    COUNT(DISTINCT fc.uuid) AS change_count,
                    COUNT(DISTINCT fc.session_file_uuid) AS distinct_files,
                    COALESCE(SUM(r.line_end - r.line_start + 1), 0) AS total_line_span
                FROM file_change fc
                LEFT JOIN file_change_range r ON r.file_change_uuid = fc.uuid
                WHERE fc.session_uuid = ?
                GROUP BY fc.prompt_uuid
                ORDER BY fc.prompt_uuid
                """,
            arguments: [sessionUuid]
        ).map { row in
            PromptChangeSummary(
                promptUuid: row["prompt_uuid"],
                summary: ChangeSummary(
                    changeCount: row["change_count"] ?? 0,
                    distinctFiles: row["distinct_files"] ?? 0,
                    totalLineSpan: row["total_line_span"] ?? 0
                )
            )
        }
    }
}
