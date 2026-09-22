import Foundation
import GRDB

/// CONTEXT_ENSURE / CONTEXT_GET data access — the promoted ensure chain plus
/// create-time-only kbite seeding. Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts.
struct ContextRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Upsert project → instance → session from repo identity, seeding kbite
    /// inheritance down the chain at CREATE time only.
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
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM claude_session_binding WHERE session_uuid = ?",
                arguments: [sessionUuid]
            ) ?? 0
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

    /// Read-only resolution — never creates rows.
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

    /// A project is identified by its code, an instance by its name inside one
    /// project, and a session by its code inside one instance — the same three
    /// keys CONTEXT_GET resolves and the ensure chain tests before inserting.
    func projectUuid(code: String) throws -> String? {
        try ProjectRecord
            .filter(ProjectRecord.Columns.code == code)
            .select(ProjectRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    func instanceUuid(projectUuid: String, name: String) throws -> String? {
        try InstanceRecord
            .filter(InstanceRecord.Columns.projectUuid == projectUuid)
            .filter(InstanceRecord.Columns.name == name)
            .select(InstanceRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    func sessionUuid(instanceUuid: String, code: String) throws -> String? {
        try SessionRecord
            .filter(SessionRecord.Columns.instanceUuid == instanceUuid)
            .filter(SessionRecord.Columns.code == code)
            .select(SessionRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    // MARK: - Ensure chain (shared with addFileChange)

    func ensureProject(_ ctx: ProjectContext) throws -> (uuid: String, created: Bool) {
        if let existing = try projectUuid(code: ctx.code) {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "project",
            uuid: ctx.uuid,
            extra: [
                "git_repo_name": ctx.gitRepoName,
                "code": ctx.code,
                "name": ctx.name,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ]
        )
        try seedKbites(level: "project", ownerUuid: uuid, codes: ctx.kbiteCodes, parent: nil)
        try core.appendEvent(db, kind: .createProject, subjectUuid: uuid)
        return (uuid, true)
    }

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
            uuid: ctx.uuid,
            extra: [
                "project_uuid": projectUuid,
                "code": ctx.code,
                "name": ctx.name,
                "absolute_file_system_path": ctx.absoluteFileSystemPath,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ]
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
            uuid: ctx.uuid,
            extra: [
                "instance_uuid": instanceUuid,
                "code": ctx.code,
                "name": ctx.name,
                "backstory": ctx.backstory,
                "goal": ctx.goal,
                "status": SessionStatus.active.rawValue,
                "gmfs_relative_storage_path": ctx.gmfsRelativeStoragePath,
            ]
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

    /// Upsert a kbite row by code, returning its uuid.
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

    /// Fill a newly created row's active-kbite junction: explicit codes from
    /// the context payload, plus a copy of the parent level's junction rows
    /// (create-time-only inheritance — existing rows are never re-seeded,
    /// exactly like gm_session_startup.sh's inherit_kbite).
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
            let inherited = try String.fetchAll(
                db,
                sql: "SELECT kbite_uuid FROM \(parent.level)_active_kbite WHERE \(parent.level)_uuid = ?",
                arguments: [parent.uuid]
            )
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
