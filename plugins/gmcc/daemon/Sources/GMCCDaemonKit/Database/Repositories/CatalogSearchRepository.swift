import Foundation
import GRDB

/// CATALOG_SEARCH data access — tokenized OR name/code search across
/// instances + sessions. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct CatalogSearchRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func searchCatalog(_ req: CatalogSearchRequest, tokens: [String], limit: Int) throws -> CatalogSearchResponse {
        // OR across tokens × (name, code) for one table alias; every token is a
        // bound `%token%` parameter — never interpolated into the SQL.
        func matchPredicate(alias: String, into arguments: inout [any DatabaseValueConvertible]) -> String {
            let clauses = tokens.map { token -> String in
                arguments.append("%\(token)%")
                arguments.append("%\(token)%")
                return "\(alias).name LIKE ? ESCAPE '\\' OR \(alias).code LIKE ? ESCAPE '\\'"
            }
            return "(" + clauses.joined(separator: " OR ") + ")"
        }

        if let projectUuid = req.projectUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM project WHERE uuid = ?", arguments: [projectUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
        }

        // Sessions: direct matches plus the whole subtree of directly-matched
        // instances, in one query (project scope rides the join — session has
        // no project_uuid column).
        var sessionSql = """
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
            JOIN instance i ON i.uuid = s.instance_uuid
            """
        var sessionArguments: [any DatabaseValueConvertible] = []
        var sessionConditions: [String] = []
        if let projectUuid = req.projectUuid {
            sessionConditions.append("i.project_uuid = ?")
            sessionArguments.append(projectUuid)
        }
        let sessionMatch = matchPredicate(alias: "s", into: &sessionArguments)
        let instanceSubtreeMatch = matchPredicate(alias: "i", into: &sessionArguments)
        sessionConditions.append("(\(sessionMatch) OR \(instanceSubtreeMatch))")
        sessionSql += " WHERE " + sessionConditions.joined(separator: " AND ")
        sessionSql += " LIMIT \(limit)"
        let sessions = try SessionStubRecord.fetchAll(
            db, sql: sessionSql, arguments: StatementArguments(sessionArguments)
        ).map { $0.wireStub() }

        // Instances: the parent closure of every returned session, plus
        // instances that matched directly (kept even when they contribute no
        // sessions — e.g. an empty instance whose name matched).
        var instanceSql = """
            SELECT i.uuid, i.version, i.project_uuid, i.code, i.name,
                   i.absolute_file_system_path, i.ckfs_relative_storage_path,
                   i.created_at, i.updated_at
            FROM instance i
            """
        var instanceArguments: [any DatabaseValueConvertible] = []
        var instanceConditions: [String] = []
        if let projectUuid = req.projectUuid {
            instanceConditions.append("i.project_uuid = ?")
            instanceArguments.append(projectUuid)
        }
        let parentUuids = Array(Set(sessions.map(\.instanceUuid)))
        let instanceMatch = matchPredicate(alias: "i", into: &instanceArguments)
        if parentUuids.isEmpty {
            instanceConditions.append(instanceMatch)
        } else {
            // Match clause first: its arguments were appended before the
            // parent uuids, and bind order must follow placeholder order.
            let placeholders = Array(repeating: "?", count: parentUuids.count).joined(separator: ", ")
            instanceConditions.append("(\(instanceMatch) OR i.uuid IN (\(placeholders)))")
            instanceArguments.append(contentsOf: parentUuids)
        }
        instanceSql += " WHERE " + instanceConditions.joined(separator: " AND ")
        let instances = try InstanceRecord.fetchAll(
            db, sql: instanceSql, arguments: StatementArguments(instanceArguments)
        ).map { $0.wireRow() }

        return CatalogSearchResponse(instances: instances, sessions: sessions)
    }
}
