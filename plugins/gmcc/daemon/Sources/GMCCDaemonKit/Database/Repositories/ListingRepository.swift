import Foundation
import GRDB

/// Read-only enumeration for the Landing browse surface (PROJECT_LIST /
/// INSTANCE_LIST / SESSION_LIST). Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts.
struct ListingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func listProjects() throws -> ProjectListResponse {
        let records = try ProjectRecord.fetchAll(db, sql: "SELECT * FROM project ORDER BY code")
        return ProjectListResponse(projects: records.map { $0.wireRow() })
    }

    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        var sql = "SELECT * FROM instance"
        var arguments: StatementArguments = []
        if let projectUuid = req.projectUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM project WHERE uuid = ?", arguments: [projectUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
            sql += " WHERE project_uuid = ?"
            arguments = [projectUuid]
        }
        sql += " ORDER BY code, name"
        let records = try InstanceRecord.fetchAll(db, sql: sql, arguments: arguments)
        return InstanceListResponse(instances: records.map { $0.wireRow() })
    }

    func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        // Item 1: last_activity_at = latest of the session's own
        // updated_at, its prompts' updated_at, and its file changes'
        // created_at — one query, correlated scalar MAXes (a childless
        // session still sorts by its own recency). ISO-8601 seconds-Z
        // strings compare lexicographically. Retires GMVibes' client-side
        // fold over an unfiltered FILE_CHANGE_LIST.
        var sql = """
            SELECT s.uuid, s.version, s.instance_uuid, s.code, s.name,
                   s.ckfs_relative_storage_path, s.created_at, s.updated_at,
                   MAX(
                       s.updated_at,
                       COALESCE((SELECT MAX(p.updated_at) FROM prompt p
                                 WHERE p.session_uuid = s.uuid), ''),
                       COALESCE((SELECT MAX(fc.created_at) FROM file_change fc
                                 WHERE fc.session_uuid = s.uuid), '')
                   ) AS last_activity_at
            FROM session s
            """
        var arguments: StatementArguments = []
        if let instanceUuid = req.instanceUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM instance WHERE uuid = ?", arguments: [instanceUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "instance", key: instanceUuid)
            }
            sql += " WHERE s.instance_uuid = ?"
            arguments = [instanceUuid]
        }
        sql += " ORDER BY s.code"
        let rows = try SessionStubRecord.fetchAll(db, sql: sql, arguments: arguments)
        return SessionListResponse(sessions: rows.map { $0.wireStub() })
    }
}
