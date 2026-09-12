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
    public func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogAdd(req) }
    }

    public func dopeCogUpdate(_ req: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogUpdate(req) }
    }

    public func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogDelete(req) }
    }

    public func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogElementAdd(req) }
    }

    public func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogElementUpdate(req) }
    }

    public func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, core: core).dopeCogElementDelete(req) }
    }

    public func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try dbQueue.read { db in try DopeCogRepository(db: db, core: core).dopeCogGet(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Every cog of a scope, hydrated, for callers already inside a
    /// transaction — the repo write path needs cogs alongside the
    /// persistence tree.
    func fetchDopeCogs(_ db: Database, scopeUuid: String) throws -> [DopeCogNode] {
        try DopeCogRepository(db: db, core: core).fetchDopeCogs(scopeUuid: scopeUuid)
    }
}
