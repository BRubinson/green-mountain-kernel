import Foundation
import GRDB

/// CATALOG_SEARCH data access — tokenized OR name/code search across
/// instances + sessions. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct CatalogSearchRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func searchCatalog(_ req: CatalogSearchRequest, tokens: [String], limit: Int) throws -> CatalogSearchResponse {
        // OR across tokens × (name, code) for one table; every token is a bound
        // `%token%` pattern — never interpolated into the SQL.
        func matchPredicate(name: SQLExpression, code: SQLExpression) -> SQLExpression {
            tokens
                .map { token in
                    name.like("%\(token)%", escape: "\\") || code.like("%\(token)%", escape: "\\")
                }
                .joined(operator: .or)
        }

        if let projectUuid = req.projectUuid {
            guard try ProjectRecord.exists(db, key: ["uuid": projectUuid]) else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
        }

        // Sessions: direct matches plus the whole subtree of directly-matched
        // instances, in one query (project scope rides the join — session has
        // no project_uuid column).
        let instanceAlias = TableAlias<InstanceRecord>()
        let sessions =
            try SessionSummary
            .request(instance: instanceAlias, projectUuid: req.projectUuid)
            .filter(
                matchPredicate(
                    name: SessionRecord.Columns.name.sqlExpression,
                    code: SessionRecord.Columns.code.sqlExpression
                )
                    || matchPredicate(
                        name: instanceAlias[InstanceRecord.Columns.name],
                        code: instanceAlias[InstanceRecord.Columns.code]
                    )
            )
            .limit(limit)
            .fetchAll(db)
            .map { $0.dto() }

        // Instances: the parent closure of every returned session, plus
        // instances that matched directly (kept even when they contribute no
        // sessions — e.g. an empty instance whose name matched). The parent
        // closure is a second read rather than a prefetch: it is seeded by the
        // LIMITed session set, which a per-instance prefetch cannot reproduce.
        var instanceRequest = InstanceRecord.all()
        if let projectUuid = req.projectUuid {
            instanceRequest = instanceRequest.filter(InstanceRecord.Columns.projectUuid == projectUuid)
        }
        let parentUuids = Array(Set(sessions.map(\.instanceUuid)))
        let instanceMatch = matchPredicate(
            name: InstanceRecord.Columns.name.sqlExpression,
            code: InstanceRecord.Columns.code.sqlExpression
        )
        if parentUuids.isEmpty {
            instanceRequest = instanceRequest.filter(instanceMatch)
        } else {
            instanceRequest = instanceRequest.filter(
                instanceMatch || parentUuids.contains(InstanceRecord.Columns.uuid)
            )
        }
        let instances = try instanceRequest.fetchAll(db).map { $0.wireRow() }

        return CatalogSearchResponse(instances: instances, sessions: sessions)
    }
}
