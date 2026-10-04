import Foundation
import GRDB

// DOPED domain modeling — scope lifecycle, tree hydration, and the generic
// per-level node mutations. Bodies live in DopeRepository; these wrappers own
// the transaction and the cross-family helper forwards.

extension Store {

    // MARK: - Verbs

    /// Creates or returns an existing dope scope.
    /// - Parameter req: The init request with session, optional prompt, code, and domain data.
    /// - Returns: The created or existing scope and a flag indicating creation.
    /// - Throws: Validation errors if code is invalid, references not found, or description too long.
    func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try boundary { db in try DopeRepository(db: db, core: core).dopeInit(req) }
    }

    /// Lists dope scopes for a session, with optional prompt filter.
    /// - Parameter req: The list request with session and optional prompt uuids.
    /// - Returns: Scopes matching the session or prompt.
    /// - Throws: `StoreError.notFound` if session or prompt not found.
    func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try boundaryRead { db in try DopeRepository(db: db, core: core).dopeList(req) }
    }

    /// Fetches a dope tree with optional overlay resolution.
    ///
    /// Resolves a scope by address hierarchy: session → prompt or project → base, returning
    /// the matching tree and the resolution path taken.
    ///
    /// - Parameter req: The get request with session or project, optional prompt and code.
    /// - Returns: The dope tree and the resolution hierarchy used.
    /// - Throws: `StoreError.notFound` if session/prompt/project not found; `badRequest` if
    ///   multiple scopes match the code.
    func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        try boundaryRead { db in try DopeRepository(db: db, core: core).dopeGet(req) }
    }

    /// Adds a node at the specified level in a dope tree.
    /// - Parameter req: The add request with parent uuid, level, code, name, and optional fields.
    /// - Returns: The new node and its scope.
    /// - Throws: Validation errors if level is invalid, code malformed, or parent not found.
    func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        try boundary { db in try DopeRepository(db: db, core: core).dopeNodeAdd(req) }
    }

    /// Updates a node at the specified level.
    /// - Parameter req: The update request with node uuid, level, and field values.
    /// - Returns: The updated node and its scope.
    /// - Throws: Validation errors if fields are invalid or node not found.
    func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        try boundary { db in try DopeRepository(db: db, core: core).dopeNodeUpdate(req) }
    }

    /// Deletes a node at the specified level.
    /// - Parameter req: The delete request with node uuid and level.
    /// - Returns: The deletion outcome and the scope.
    /// - Throws: `StoreError.notFound` if node not found; `badRequest` if deletion is unsafe.
    func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        try boundary { db in try DopeRepository(db: db, core: core).dopeNodeDelete(req) }
    }

    // MARK: - Cross-family helper forwards (bodies in DopeRepository)

    /// Fetches the scope row by uuid.
    /// - Parameters:
    ///   - db: The database.
    ///   - uuid: The scope uuid.
    /// - Returns: The scope row, or nil if not found.
    /// - Throws: Store errors if the fetch fails.
    func fetchDopeScope(_ db: Database, uuid: String) throws -> DopeScopeRow? {
        try DopeRepository(db: db, core: core).fetchDopeScope(uuid: uuid)
    }

    /// Advances the scope revision counter, optionally for a subtree area.
    ///
    /// The scope revision is the sole CAS gate for dope mutations, while area counters
    /// enable clients to track subtree changes without refetching the whole tree.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - scopeUuid: The scope uuid.
    ///   - area: The area to advance, if any; requires `ownerUuid`.
    ///   - ownerUuid: The row uuid owning the area, required when `area` is provided.
    /// - Returns: The new scope revision number.
    /// - Throws: Store errors if the update fails.
    @discardableResult
    func bumpScopeRevision(
        _ db: Database,
        scopeUuid: String,
        area: DopeArea? = nil,
        ownerUuid: String? = nil
    ) throws -> Int64 {
        try DopeRepository(db: db, core: core)
            .bumpScopeRevision(scopeUuid: scopeUuid, area: area, ownerUuid: ownerUuid)
    }

    /// Fetches the instance root path for a session.
    ///
    /// Session-keyed twin of the promptUuid variant in Store+Architecture. Dope repo
    /// verbs are scope-addressed and scopes hang off sessions.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - sessionUuid: The session uuid.
    /// - Returns: The absolute file system path.
    /// - Throws: Store errors if the fetch fails.
    func instanceRoot(_ db: Database, sessionUuid: String) throws -> String {
        try DopeRepository(db: db, core: core).instanceRoot(sessionUuid: sessionUuid)
    }

    /// Fetches the scope that owns a node at the given level.
    ///
    /// Walks the registry's parent links to resolve ownership.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - level: The node level.
    ///   - nodeUuid: The node uuid.
    /// - Returns: The owning scope.
    /// - Throws: `StoreError.notFound` if node or scope not found.
    func dopeOwningScope(_ db: Database, level: DopeLevel, nodeUuid: String) throws -> DopeScopeRow {
        try DopeRepository(db: db, core: core).dopeOwningScope(level: level, nodeUuid: nodeUuid)
    }

    /// Records a change event for a dope node.
    ///
    /// Every granular mutation funnels through here, so ingest can track which session
    /// touched each element using dot-paths.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - scope: The scope owning the node.
    ///   - action: The mutation action (e.g., "init", "update", "delete").
    ///   - level: The node level, or nil for a scope-level change.
    ///   - nodeUuid: The node uuid, or nil for a scope-level change.
    ///   - revision: The scope revision after the change.
    /// - Throws: Store errors if the event append fails.
    func recordDopeChange(
        _ db: Database,
        scope: DopeScopeRow,
        action: String,
        level: DopeLevel?,
        nodeUuid: String?,
        revision: Int64
    ) throws {
        try DopeRepository(db: db, core: core)
            .recordDopeChange(
                scope: scope,
                action: action,
                level: level,
                nodeUuid: nodeUuid,
                revision: revision
            )
    }

    /// Fetches dope scope candidates matching session, type, prompt, and optional code.
    ///
    /// Shared by get's resolution ladder and list's enumeration; results are ordered by code.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - sessionUuid: The session uuid.
    ///   - scopeType: The scope type to filter by.
    ///   - promptUuid: The optional prompt uuid; required when scope type is
    ///     `.sessionInstanceItem`.
    ///   - code: The optional scope code to filter by.
    /// - Returns: Array of matching scope rows.
    /// - Throws: Store errors if the query fails.
    func dopeScopeCandidates(
        _ db: Database,
        sessionUuid: String,
        scopeType: DopeScopeType,
        promptUuid: String? = nil,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        try DopeRepository(db: db, core: core)
            .dopeScopeCandidates(
                sessionUuid: sessionUuid,
                scopeType: scopeType,
                promptUuid: promptUuid,
                code: code
            )
    }

    /// Fetches dope scope candidates at the project tier.
    ///
    /// Mirrors the session-tier ladder for project-scoped diagrams.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - projectUuid: The project uuid.
    ///   - scopeType: The scope type to filter by.
    ///   - code: The optional scope code to filter by.
    /// - Returns: Array of matching scope rows.
    /// - Throws: Store errors if the query fails.
    func dopeProjectScopeCandidates(
        _ db: Database,
        projectUuid: String,
        scopeType: DopeScopeType,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        try DopeRepository(db: db, core: core)
            .dopeProjectScopeCandidates(
                projectUuid: projectUuid,
                scopeType: scopeType,
                code: code
            )
    }

    /// Fetches the persistence uuid owning a node at the given level.
    /// - Parameters:
    ///   - db: The database.
    ///   - level: The node level.
    ///   - nodeUuid: The node uuid.
    /// - Returns: The owning persistence uuid, or nil if none.
    /// - Throws: Store errors if the lookup fails.
    func owningPersistenceUuid(
        _ db: Database,
        level: DopeLevel,
        nodeUuid: String
    ) throws -> String? {
        try DopeRepository(db: db, core: core)
            .owningPersistenceUuid(level: level, nodeUuid: nodeUuid)
    }

    /// Fetches area revision numbers for a scope.
    /// - Parameters:
    ///   - db: The database.
    ///   - scopeUuid: The scope uuid.
    /// - Returns: A dictionary mapping area names to their current revision numbers.
    /// - Throws: Store errors if the fetch fails.
    func areaVersions(_ db: Database, scopeUuid: String) throws -> [String: Int64] {
        try DopeRepository(db: db, core: core).areaVersions(scopeUuid: scopeUuid)
    }

    /// Fetches an entire dope tree with optional projection filtering.
    /// - Parameters:
    ///   - db: The database.
    ///   - scope: The scope owning the tree.
    ///   - forProjection: When true, applies projection-specific filtering.
    /// - Returns: The complete dope tree.
    /// - Throws: Store errors if the fetch fails.
    func fetchDopeTree(
        _ db: Database,
        scope: DopeScopeRow,
        forProjection: Bool = false
    ) throws -> DopeScopeTree {
        try DopeRepository(db: db, core: core)
            .fetchDopeTree(scope: scope, forProjection: forProjection)
    }

    /// Copies a dope tree from one scope to another.
    /// - Parameters:
    ///   - db: The database.
    ///   - source: The source scope to copy from.
    ///   - targetScopeUuid: The target scope uuid to copy into.
    /// - Returns: Counts of copied nodes by level.
    /// - Throws: Store errors if the copy fails.
    @discardableResult
    func copyDopeTree(
        _ db: Database,
        from source: DopeScopeRow,
        into targetScopeUuid: String
    ) throws -> DopeTreeCounts {
        try DopeRepository(db: db, core: core)
            .copyDopeTree(from: source, into: targetScopeUuid)
    }

    /// Inserts a dope tree from domain file documents.
    /// - Parameters:
    ///   - db: The database.
    ///   - scopeUuid: The target scope uuid.
    ///   - domainFiles: The persistence and entity documents to insert.
    /// - Returns: Counts of inserted nodes by level.
    /// - Throws: Store errors if the insert fails.
    @discardableResult
    func insertDopeTree(
        _ db: Database,
        scopeUuid: String,
        domainFiles: [DopePersistenceFileDocument]
    ) throws -> DopeTreeCounts {
        try DopeRepository(db: db, core: core)
            .insertDopeTree(scopeUuid: scopeUuid, domainFiles: domainFiles)
    }

    /// Deletes all dope tree content for a scope.
    /// - Parameters:
    ///   - db: The database.
    ///   - scopeUuid: The scope uuid to wipe.
    /// - Throws: Store errors if the deletion fails.
    func wipeDopeTree(_ db: Database, scopeUuid: String) throws {
        try DopeRepository(db: db, core: core).wipeDopeTree(scopeUuid: scopeUuid)
    }

    /// Inserts cog documents into a scope.
    /// - Parameters:
    ///   - db: The database.
    ///   - scopeUuid: The target scope uuid.
    ///   - cogFiles: The cog documents to insert.
    /// - Throws: Store errors if the insert fails.
    func insertDopeCogs(
        _ db: Database,
        scopeUuid: String,
        cogFiles: [DopeCogDocument]
    ) throws {
        try DopeRepository(db: db, core: core)
            .insertDopeCogs(scopeUuid: scopeUuid, cogFiles: cogFiles)
    }
}
