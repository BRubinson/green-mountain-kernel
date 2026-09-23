import Foundation
import GRDB

// COGS CRUD. A cog is a named grouping inside a dope scope; its elements are
// typed nodes whose per-type metadata lives in a subtype table chosen by the
// DopeCogElementSpec registry.
//
// Deliberately a peer verb family (DOPE_COG_*) rather than more DOPE_NODE_*
// verbs, matching the in-repo precedent that the DIAGRAM_* family is a peer
// over dope rather than a dope subfamily.
// Bodies live in DopeCogRepository; these wrappers own the transaction.

extension Store {
    /// Adds a new cog to a scope within a transaction boundary.
    ///
    /// - Parameter req: The cog creation request.
    /// - Returns: A response with the created cog and its revision.
    /// - Throws: `StoreError` errors on add failure or validation failure.
    func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogAdd(req) }
    }

    /// Updates an existing cog within a transaction boundary.
    ///
    /// - Parameter req: The cog update request.
    /// - Returns: A response with the updated cog and its new revision.
    /// - Throws: `StoreError` errors on update failure or validation failure.
    func dopeCogUpdate(_ req: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogUpdate(req) }
    }

    /// Deletes a cog from a scope within a transaction boundary.
    ///
    /// - Parameter req: The cog deletion request.
    /// - Returns: A response with the deleted cog UUID, cascaded element count, scope UUID, and revision.
    /// - Throws: `StoreError` errors on delete failure or validation failure.
    func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogDelete(req) }
    }

    /// Adds a new element to a cog within a transaction boundary.
    ///
    /// - Parameter req: The element creation request.
    /// - Returns: A response with the created element and its revision.
    /// - Throws: `StoreError` errors on add failure or validation failure.
    func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogElementAdd(req) }
    }

    /// Updates an existing cog element within a transaction boundary.
    ///
    /// - Parameter req: The element update request.
    /// - Returns: A response with the updated element and its new revision.
    /// - Throws: `StoreError` errors on update failure or validation failure.
    func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogElementUpdate(req) }
    }

    /// Deletes a cog element from its cog within a transaction boundary.
    ///
    /// - Parameter req: The element deletion request.
    /// - Returns: A response with the deleted element UUID, cascaded child count, scope UUID, and revision.
    /// - Throws: `StoreError` errors on delete failure or validation failure.
    func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try boundary { db in try DopeCogRepository(db: db, core: core).dopeCogElementDelete(req) }
    }

    /// Fetches cogs from a scope within a read transaction boundary.
    ///
    /// - Parameter req: The fetch request with scope UUID and optional code filter.
    /// - Returns: A response with the matching cogs.
    /// - Throws: `StoreError` errors on fetch failure.
    func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try boundaryRead { db in try DopeCogRepository(db: db, core: core).dopeCogGet(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Fetches every cog of a scope, hydrated for the write path.
    ///
    /// For callers already inside a transaction; the repo write path needs cogs
    /// alongside the persistence tree.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - scopeUuid: The scope UUID to fetch cogs from.
    /// - Returns: An array of hydrated cogs with their elements.
    /// - Throws: `StoreError` errors on fetch failure.
    func fetchDopeCogs(_ db: Database, scopeUuid: String) throws -> [DopeCogNode] {
        try DopeCogRepository(db: db, core: core).fetchDopeCogs(scopeUuid: scopeUuid)
    }
}
