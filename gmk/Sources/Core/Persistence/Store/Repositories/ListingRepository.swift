import Foundation
import GRDB

/// Read-only enumeration for the Landing browse surface (PROJECT_LIST /
/// INSTANCE_LIST / SESSION_LIST).
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never self-transacts.
struct ListingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Lists all projects ordered by code.
    /// - Returns: A response with all projects in the system.
    /// - Throws: A store error if the read fails.
    func listProjects() throws -> ProjectListResponse {
        let records = try ProjectRecord.order(ProjectRecord.Columns.code).fetchAll(db)
        return ProjectListResponse(projects: records.map { $0.dto() })
    }

    /// Lists instances, optionally filtered by project.
    /// - Parameter req: The request with optional project UUID filter.
    /// - Returns: A response with matching instances.
    /// - Throws: A store error if the read fails or project doesn't exist.
    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        var request = InstanceRecord.order(InstanceRecord.Columns.code, InstanceRecord.Columns.name)
        if let projectUuid = req.projectUuid {
            guard try ProjectRecord.exists(db, key: ["uuid": projectUuid]) else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
            request = request.filter(InstanceRecord.Columns.projectUuid == projectUuid)
        }
        return InstanceListResponse(instances: try request.fetchAll(db).map { $0.dto() })
    }

    /// Lists sessions, optionally filtered by instance.
    /// - Parameter req: The request with optional instance UUID filter.
    /// - Returns: A response with matching sessions.
    /// - Throws: A store error if the read fails or instance doesn't exist.
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
