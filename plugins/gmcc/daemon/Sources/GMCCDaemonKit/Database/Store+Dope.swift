import Foundation
import GRDB

// DOPED domain modeling — scope lifecycle, tree hydration, and the generic
// per-level node mutations. Bodies live in DopeRepository; these wrappers own
// the transaction and the cross-family helper forwards.

extension Store {

    static func dopeScopeRow(_ row: Row) throws -> DopeScopeRow {
        try DopeScopeRecord(row: row).wireRow()
    }

    // MARK: - Verbs

    public func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try dbQueue.write { db in try DopeRepository(db: db, core: core).dopeInit(req) }
    }

    public func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try dbQueue.read { db in try DopeRepository(db: db, core: core).dopeList(req) }
    }

    public func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        try dbQueue.read { db in try DopeRepository(db: db, core: core).dopeGet(req) }
    }

    public func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        try dbQueue.write { db in try DopeRepository(db: db, core: core).dopeNodeAdd(req) }
    }

    public func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        try dbQueue.write { db in try DopeRepository(db: db, core: core).dopeNodeUpdate(req) }
    }

    public func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        try dbQueue.write { db in try DopeRepository(db: db, core: core).dopeNodeDelete(req) }
    }

    // MARK: - Cross-family helper forwards (bodies in DopeRepository)

    func fetchDopeScope(_ db: Database, uuid: String) throws -> DopeScopeRow? {
        try DopeRepository(db: db, core: core).fetchDopeScope(uuid: uuid)
    }

    @discardableResult
    func bumpScopeRevision(
        _ db: Database, scopeUuid: String, area: DopeArea? = nil, ownerUuid: String? = nil
    ) throws -> Int64 {
        try DopeRepository(db: db, core: core)
            .bumpScopeRevision(scopeUuid: scopeUuid, area: area, ownerUuid: ownerUuid)
    }

    /// Session-keyed twin of the promptUuid variant in Store+Architecture.
    func instanceRoot(_ db: Database, sessionUuid: String) throws -> String {
        try DopeRepository(db: db, core: core).instanceRoot(sessionUuid: sessionUuid)
    }

    func dopeOwningScope(_ db: Database, level: DopeLevel, nodeUuid: String) throws -> DopeScopeRow {
        try DopeRepository(db: db, core: core).dopeOwningScope(level: level, nodeUuid: nodeUuid)
    }

    func recordDopeChange(
        _ db: Database, scope: DopeScopeRow, action: String, level: DopeLevel?,
        nodeUuid: String?, revision: Int64
    ) throws {
        try DopeRepository(db: db, core: core).recordDopeChange(
            scope: scope, action: action, level: level, nodeUuid: nodeUuid, revision: revision)
    }

    func dopeScopeCandidates(
        _ db: Database, sessionUuid: String, scopeType: DopeScopeType,
        promptUuid: String? = nil, code: String? = nil
    ) throws -> [DopeScopeRow] {
        try DopeRepository(db: db, core: core).dopeScopeCandidates(
            sessionUuid: sessionUuid, scopeType: scopeType,
            promptUuid: promptUuid, code: code)
    }

    func dopeProjectScopeCandidates(
        _ db: Database, projectUuid: String, scopeType: DopeScopeType,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        try DopeRepository(db: db, core: core).dopeProjectScopeCandidates(
            projectUuid: projectUuid, scopeType: scopeType, code: code)
    }

    func owningPersistenceUuid(
        _ db: Database, level: DopeLevel, nodeUuid: String
    ) throws -> String? {
        try DopeRepository(db: db, core: core)
            .owningPersistenceUuid(level: level, nodeUuid: nodeUuid)
    }

    func areaVersions(_ db: Database, scopeUuid: String) throws -> [String: Int64] {
        try DopeRepository(db: db, core: core).areaVersions(scopeUuid: scopeUuid)
    }

    func fetchDopeTree(
        _ db: Database, scope: DopeScopeRow, forProjection: Bool = false
    ) throws -> DopeScopeTree {
        try DopeRepository(db: db, core: core)
            .fetchDopeTree(scope: scope, forProjection: forProjection)
    }

    @discardableResult
    func copyDopeTree(
        _ db: Database, from source: DopeScopeRow, into targetScopeUuid: String
    ) throws -> DopeTreeCounts {
        try DopeRepository(db: db, core: core)
            .copyDopeTree(from: source, into: targetScopeUuid)
    }

    @discardableResult
    func insertDopeTree(
        _ db: Database, scopeUuid: String, domainFiles: [DopePersistenceFileDocument]
    ) throws -> DopeTreeCounts {
        try DopeRepository(db: db, core: core)
            .insertDopeTree(scopeUuid: scopeUuid, domainFiles: domainFiles)
    }

    func wipeDopeTree(_ db: Database, scopeUuid: String) throws {
        try DopeRepository(db: db, core: core).wipeDopeTree(scopeUuid: scopeUuid)
    }

    func insertDopeCogs(
        _ db: Database, scopeUuid: String, cogFiles: [DopeCogDocument]
    ) throws {
        try DopeRepository(db: db, core: core)
            .insertDopeCogs(scopeUuid: scopeUuid, cogFiles: cogFiles)
    }
}
