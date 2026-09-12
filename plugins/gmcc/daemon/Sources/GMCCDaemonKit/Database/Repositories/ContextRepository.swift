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
            req.instance, projectUuid: projectUuid)
        let (sessionUuid, createdSession) = try ensureSession(
            req.session, instanceUuid: instanceUuid)
        // The binding rides this call because SessionStart already makes it:
        // pinning here costs no second process and cannot be forgotten
        // independently of creating the session it points at. Pin-once is the
        // UNIQUE index, so a re-ensure is a no-op and the FIRST session a
        // conversation ensured is the one it stays bound to.
        if let claudeSessionId = req.claudeSessionId {
            try claudeSessionBinding.pin(
                claudeSessionId: claudeSessionId, sessionUuid: sessionUuid)
        }
        // Counted AFTER the pin above, so a caller that just bound this session
        // is told 1 rather than the pre-pin 0 and does not warn about a session
        // it has this instant made healthy.
        let bindingCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM claude_session_binding WHERE session_uuid = ?",
            arguments: [sessionUuid]) ?? 0
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
        let projectUuid = try String.fetchOne(
            db, sql: "SELECT uuid FROM project WHERE code = ?", arguments: [req.projectCode])
        var instanceUuid: String?
        if let projectUuid {
            instanceUuid = try String.fetchOne(
                db,
                sql: "SELECT uuid FROM instance WHERE project_uuid = ? AND name = ?",
                arguments: [projectUuid, req.instanceName])
        }
        var sessionUuid: String?
        if let instanceUuid {
            sessionUuid = try String.fetchOne(
                db,
                sql: "SELECT uuid FROM session WHERE instance_uuid = ? AND code = ?",
                arguments: [instanceUuid, req.sessionCode])
        }
        var kbiteCodes: [String] = []
        if let sessionUuid {
            kbiteCodes = try String.fetchAll(db, sql: """
                SELECT k.code FROM kbite k
                JOIN session_active_kbite j ON j.kbite_uuid = k.uuid
                WHERE j.session_uuid = ?
                ORDER BY k.code
                """, arguments: [sessionUuid])
        }
        return ContextGetResponse(
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            kbiteCodes: kbiteCodes
        )
    }

    // MARK: - Ensure chain (shared with addFileChange)

    func ensureProject(_ ctx: ProjectContext) throws -> (uuid: String, created: Bool) {
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM project WHERE code = ?", arguments: [ctx.code]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "project", uuid: ctx.uuid, extra: [
            "git_repo_name": ctx.gitRepoName,
            "code": ctx.code,
            "name": ctx.name,
            "ckfs_relative_storage_path": ctx.ckfsRelativeStoragePath,
        ])
        try seedKbites(level: "project", ownerUuid: uuid, codes: ctx.kbiteCodes, parent: nil)
        try core.appendEvent(db, kind: .createProject, subjectUuid: uuid)
        return (uuid, true)
    }

    func ensureInstance(
        _ ctx: InstanceContext, projectUuid: String
    ) throws -> (uuid: String, created: Bool) {
        if let existing = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM instance WHERE project_uuid = ? AND name = ?",
            arguments: [projectUuid, ctx.name]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "instance", uuid: ctx.uuid, extra: [
            "project_uuid": projectUuid,
            "code": ctx.code,
            "name": ctx.name,
            "absolute_file_system_path": ctx.absoluteFileSystemPath,
            "ckfs_relative_storage_path": ctx.ckfsRelativeStoragePath,
        ])
        try seedKbites(
            level: "instance", ownerUuid: uuid, codes: ctx.kbiteCodes,
            parent: (level: "project", uuid: projectUuid))
        try core.appendEvent(db, kind: .createInstance, subjectUuid: uuid)
        return (uuid, true)
    }

    func ensureSession(
        _ ctx: SessionContext, instanceUuid: String
    ) throws -> (uuid: String, created: Bool) {
        if let existing = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM session WHERE instance_uuid = ? AND code = ?",
            arguments: [instanceUuid, ctx.code]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "session", uuid: ctx.uuid, extra: [
            "instance_uuid": instanceUuid,
            "code": ctx.code,
            "name": ctx.name,
            "backstory": ctx.backstory,
            "goal": ctx.goal,
            "status": SessionStatus.active.rawValue,
            "ckfs_relative_storage_path": ctx.ckfsRelativeStoragePath,
        ])
        try seedKbites(
            level: "session", ownerUuid: uuid, codes: ctx.kbiteCodes,
            parent: (level: "instance", uuid: instanceUuid))
        try core.appendEvent(db, kind: .createSession, subjectUuid: uuid)
        return (uuid, true)
    }

    // MARK: - Kbite seeding (create-time-only, mirrors inherit_kbite)

    /// Upsert a kbite row by code, returning its uuid.
    func ensureKbite(code: String) throws -> String {
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [code]
        ) {
            return existing
        }
        return try core.insertBase(db, table: "kbite", extra: ["code": code])
    }

    /// Fill a newly created row's active-kbite junction: explicit codes from
    /// the context payload, plus a copy of the parent level's junction rows
    /// (create-time-only inheritance — existing rows are never re-seeded,
    /// exactly like gmcc_session_startup.sh's inherit_kbite).
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
                arguments: [parent.uuid])
            kbiteUuids.formUnion(inherited)
        }
        for kbiteUuid in kbiteUuids.sorted() {
            try core.insertBase(db, table: "\(level)_active_kbite", extra: [
                "\(level)_uuid": ownerUuid,
                "kbite_uuid": kbiteUuid,
            ])
        }
    }
}
