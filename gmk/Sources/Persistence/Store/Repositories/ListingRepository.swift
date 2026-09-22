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
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM project WHERE uuid = ?",
                    arguments: [projectUuid]
                ) != nil
            else {
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
        var request = SessionSummary.request().order(Column("code"))
        if let instanceUuid = req.instanceUuid {
            guard try InstanceRecord.exists(db, key: ["uuid": instanceUuid]) else {
                throw StoreError.notFound(entity: "instance", key: instanceUuid)
            }
            request = request.filter(Column("instance_uuid") == instanceUuid)
        }
        return SessionListResponse(sessions: try request.fetchAll(db).map { $0.dto() })
    }
}
