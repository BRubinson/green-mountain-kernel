import Foundation
import GRDB

/// CONTEXT_ENSURE / CONTEXT_GET data access — the promoted ensure chain plus
/// create-time-only kbite seeding.
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never self-transacts.
struct ContextRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Upserts project, instance, and session from repo identity.
    ///
    /// Seeds kbite inheritance down the chain at CREATE time only.
    ///
    /// - Parameter req: The ensure request with context payloads.
    /// - Returns: The `ContextEnsureResponse`.
    /// - Throws: Any database or persistence error.
    func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        let (projectUuid, createdProject) = try ensureProject(req.project)
        let (instanceUuid, createdInstance) = try ensureInstance(
            req.instance,
            projectUuid: projectUuid
        )
        let (sessionUuid, createdSession) = try ensureSession(
            req.session,
            instanceUuid: instanceUuid
        )
        // The binding rides this call because SessionStart already makes it:
        // pinning here costs no second process and cannot be forgotten
        // independently of creating the session it points at. Pin-once is the
        // UNIQUE index, so a re-ensure is a no-op and the FIRST session a
        // conversation ensured is the one it stays bound to.
        if let claudeSessionId = req.claudeSessionId {
            try claudeSessionBinding.pin(
                claudeSessionId: claudeSessionId,
                sessionUuid: sessionUuid
            )
        }
        // Counted AFTER the pin above, so a caller that just bound this session
        // is told 1 rather than the pre-pin 0 and does not warn about a session
        // it has this instant made healthy.
        let bindingCount =
            try ClaudeSessionBindingRecord
            .filter(ClaudeSessionBindingRecord.Columns.sessionUuid == sessionUuid)
            .fetchCount(db)
        return ContextEnsureResponse(
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            createdProject: createdProject,
            createdInstance: createdInstance,
            createdSession: createdSession,
            claudeSessionBindingCount: bindingCount
        )
    }

    /// Read-only resolution of context without creating rows.
    ///
    /// - Parameter req: The get request with project code, instance name, and session code.
    /// - Returns: The `ContextGetResponse`.
    /// - Throws: Any database error.
    func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        let projectUuid = try self.projectUuid(code: req.projectCode)
        var instanceUuid: String?
        if let projectUuid {
            instanceUuid = try self.instanceUuid(projectUuid: projectUuid, name: req.instanceName)
        }
        var sessionUuid: String?
        if let instanceUuid {
            sessionUuid = try self.sessionUuid(instanceUuid: instanceUuid, code: req.sessionCode)
        }
        var kbiteCodes: [String] = []
        if let sessionUuid {
            kbiteCodes =
                try KbiteRecord
                .joining(
                    required: KbiteRecord.sessionActivations
                        .filter(Column("session_uuid") == sessionUuid)
                )
                .order(Column("code"))
                .select(Column("code"), as: String.self)
                .fetchAll(db)
        }
        return ContextGetResponse(
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            kbiteCodes: kbiteCodes
        )
    }

    // MARK: - Identity lookups (shared by the read and the ensure chain)

    /// Resolves a project UUID from its code.
    ///
    /// Projects are identified by code; instances by name within a project;
    /// sessions by code within an instance. These are the same three keys that
    /// CONTEXT_GET resolves and the ensure chain tests before inserting.
    ///
    /// - Parameter code: The project code.
    /// - Returns: The project UUID, or `nil` if not found.
    /// - Throws: Any database error.
    func projectUuid(code: String) throws -> String? {
        try ProjectRecord
            .filter(ProjectRecord.Columns.code == code)
            .select(ProjectRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    /// Resolves an instance UUID from its project and name.
    ///
    /// - Parameters:
    ///   - projectUuid: The parent project UUID.
    ///   - name: The instance name.
    /// - Returns: The instance UUID, or `nil` if not found.
    /// - Throws: Any database error.
    func instanceUuid(projectUuid: String, name: String) throws -> String? {
        try InstanceRecord
            .filter(InstanceRecord.Columns.projectUuid == projectUuid)
            .filter(InstanceRecord.Columns.name == name)
            .select(InstanceRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    /// Resolves a session UUID from its instance and code.
    ///
    /// - Parameters:
    ///   - instanceUuid: The parent instance UUID.
    ///   - code: The session code.
    /// - Returns: The session UUID, or `nil` if not found.
    /// - Throws: Any database error.
    func sessionUuid(instanceUuid: String, code: String) throws -> String? {
        try SessionRecord
            .filter(SessionRecord.Columns.instanceUuid == instanceUuid)
            .filter(SessionRecord.Columns.code == code)
            .select(SessionRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    // MARK: - Ensure chain (shared with addFileChange)

    /// Creates a project or returns the existing one, seeding its kbites.
    ///
    /// - Parameter ctx: The project context.
    /// - Returns: Tuple of the project UUID and a boolean indicating if created.
    /// - Throws: Any database or persistence error.
    func ensureProject(_ ctx: ProjectContext) throws -> (uuid: String, created: Bool) {
        if let existing = try projectUuid(code: ctx.code) {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "project",
            extra: [
                "git_repo_name": ctx.gitRepoName,
                "code": ctx.code,
                "name": ctx.name,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ],
            uuid: ctx.uuid
        )
        try seedKbites(level: "project", ownerUuid: uuid, codes: ctx.kbiteCodes, parent: nil)
        try core.appendEvent(db, kind: .createProject, subjectUuid: uuid)
        return (uuid, true)
    }

    /// Creates an instance or returns the existing one, seeding its kbites.
    ///
    /// - Parameters:
    ///   - ctx: The instance context.
    ///   - projectUuid: The parent project UUID.
    /// - Returns: Tuple of the instance UUID and a boolean indicating if created.
    /// - Throws: Any database or persistence error.
    func ensureInstance(
        _ ctx: InstanceContext,
        projectUuid: String
    ) throws -> (uuid: String, created: Bool) {
        if let existing = try instanceUuid(projectUuid: projectUuid, name: ctx.name) {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "instance",
            extra: [
                "project_uuid": projectUuid,
                "code": ctx.code,
                "name": ctx.name,
                "absolute_file_system_path": ctx.absoluteFileSystemPath,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ],
            uuid: ctx.uuid
        )
        try seedKbites(
            level: "instance",
            ownerUuid: uuid,
            codes: ctx.kbiteCodes,
            parent: (level: "project", uuid: projectUuid)
        )
        try core.appendEvent(db, kind: .createInstance, subjectUuid: uuid)
        return (uuid, true)
    }

    /// Creates a session or returns the existing one, seeding its kbites.
    ///
    /// - Parameters:
    ///   - ctx: The session context.
    ///   - instanceUuid: The parent instance UUID.
    /// - Returns: Tuple of the session UUID and a boolean indicating if created.
    /// - Throws: Any database or persistence error.
    func ensureSession(
        _ ctx: SessionContext,
        instanceUuid: String
    ) throws -> (uuid: String, created: Bool) {
        if let existing = try sessionUuid(instanceUuid: instanceUuid, code: ctx.code) {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "session",
            extra: [
                "instance_uuid": instanceUuid,
                "code": ctx.code,
                "name": ctx.name,
                "backstory": ctx.backstory,
                "goal": ctx.goal,
                "status": SessionStatus.active.rawValue,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ],
            uuid: ctx.uuid
        )
        try seedKbites(
            level: "session",
            ownerUuid: uuid,
            codes: ctx.kbiteCodes,
            parent: (level: "instance", uuid: instanceUuid)
        )
        try core.appendEvent(db, kind: .createSession, subjectUuid: uuid)
        return (uuid, true)
    }

    // MARK: - Kbite seeding (create-time-only, mirrors inherit_kbite)

    /// Upserts a kbite row by code, returning its UUID.
    ///
    /// - Parameter code: The kbite code.
    /// - Returns: The kbite UUID.
    /// - Throws: Any database error.
    func ensureKbite(code: String) throws -> String {
        if let existing =
            try KbiteRecord
            .filter(KbiteRecord.Columns.code == code)
            .select(KbiteRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            return existing
        }
        return try core.insertBase(db, table: "kbite", extra: ["code": code])
    }

    /// Seeds active kbites for a newly created context row.
    ///
    /// Populates the junction with explicit codes from the context payload,
    /// plus a copy of the parent level's junction rows (create-time-only
    /// inheritance). Existing rows are never re-seeded, exactly like
    /// `gm_session_startup.sh`'s `inherit_kbite`.
    ///
    /// - Parameters:
    ///   - level: The context level: `project`, `instance`, or `session`.
    ///   - ownerUuid: The UUID of the newly created row.
    ///   - codes: Explicit kbite codes to add; `nil` for none.
    ///   - parent: Parent level and UUID for inheritance; `nil` to skip.
    /// - Throws: Any database error.
    private func seedKbites(
        level: String,
        ownerUuid: String,
        codes: [String]?,
        parent: (level: String, uuid: String)?
    ) throws {
        var kbiteUuids: Set<String> = []
        for code in codes ?? [] {
            kbiteUuids.insert(try ensureKbite(code: code))
        }
        if let parent {
            let inherited = try Table("\(parent.level)_active_kbite")
                .filter(Column("\(parent.level)_uuid") == parent.uuid)
                .select(Column("kbite_uuid"), as: String.self)
                .fetchAll(db)
            kbiteUuids.formUnion(inherited)
        }
        for kbiteUuid in kbiteUuids.sorted() {
            try core.insertBase(
                db,
                table: "\(level)_active_kbite",
                extra: [
                    "\(level)_uuid": ownerUuid,
                    "kbite_uuid": kbiteUuid,
                ]
            )
        }
    }
}
