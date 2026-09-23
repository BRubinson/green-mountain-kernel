import Foundation
import GRDB

// KBITE_LIST / KBITE_ADD / KBITE_REMOVE — the registry family over the
// {scope}_active_kbite junctions from m0001. The db is the sole kbite
// registry. Bodies live in KbiteRepository; these wrappers own the
// transaction.

extension Store {
    /// Lists registered kbites at a scope, resolved through the inheritance chain.
    ///
    /// Registered kbites at a scope, resolved through the inheritance chain at
    /// READ time: the owner's own junction plus every ancestor level's.
    ///
    /// Unlike the create-time-only seeding path, this sees kbites added to a
    /// parent after the child row was created. `all: true` bypasses scope
    /// resolution and returns every kbite row.
    ///
    /// - Parameter req: The list request with scope and owner information.
    /// - Returns: The response with registered kbites.
    /// - Throws: A store error if the read fails.
    func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        try boundaryRead { db in try KbiteRepository(db: db, core: core).listKbites(req) }
    }

    /// Registers a kbite at a scope.
    /// - Parameter req: The add request with scope and resource information.
    /// - Returns: The response confirming the kbite registration.
    /// - Throws: A store error if the write fails.
    func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try boundary { db in try KbiteRepository(db: db, core: core).addKbite(req) }
    }

    /// Unregisters a kbite from a scope.
    /// - Parameter req: The remove request with scope and kbite resource information.
    /// - Returns: The response confirming the kbite removal.
    /// - Throws: A store error if the write fails.
    func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try boundary { db in try KbiteRepository(db: db, core: core).removeKbite(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Resolves the owner's scope plus every ancestor scope and UUID.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - scope: The starting scope level.
    ///   - ownerUuid: The scope owner's UUID.
    /// - Returns: An array of scope levels and their UUIDs.
    /// - Throws: A store error if the read fails.
    func resolveAncestorScopes(
        _ db: Database,
        scope: KbiteScope,
        ownerUuid: String
    ) throws -> [(level: String, uuid: String)] {
        try KbiteRepository(db: db, core: core)
            .resolveAncestorScopes(scope: scope, ownerUuid: ownerUuid)
    }
}
