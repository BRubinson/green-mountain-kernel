import Foundation
import GRDB

// KBITE_LIST / KBITE_ADD / KBITE_REMOVE — the registry family over the
// {scope}_active_kbite junctions from m0001. The db is the sole kbite
// registry. Bodies live in KbiteRepository; these wrappers own the
// transaction.

extension Store {
    /// Registered kbites at a scope, resolved through the inheritance chain at
    /// READ time: the owner's own junction plus every ancestor level's. Unlike
    /// the create-time-only seeding path, this sees kbites added to a parent
    /// after the child row was created. `all: true` bypasses scope resolution
    /// and returns every kbite row.
    public func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        try dbQueue.read { db in try KbiteRepository(db: db, core: core).listKbites(req) }
    }

    public func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try dbQueue.write { db in try KbiteRepository(db: db, core: core).addKbite(req) }
    }

    public func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try dbQueue.write { db in try KbiteRepository(db: db, core: core).removeKbite(req) }
    }

    // MARK: - Cross-domain helper forward

    /// The owner's own scope plus every ancestor scope+uuid.
    func resolveAncestorScopes(
        _ db: Database, scope: KbiteScope, ownerUuid: String
    ) throws -> [(level: String, uuid: String)] {
        try KbiteRepository(db: db, core: core)
            .resolveAncestorScopes(scope: scope, ownerUuid: ownerUuid)
    }
}
