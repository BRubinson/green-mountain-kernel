import Foundation
import GRDB

/// Registry data access over the {scope}_active_kbite junctions. All dynamic
/// table/column identifiers come from KbiteScope.rawValue — enum-bound, never
/// caller text. Runs INSIDE a Store-owned transaction; holds no dbQueue and
/// never self-transacts.
struct KbiteRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        if req.all == true {
            let rows = try Row.fetchAll(db, sql: "SELECT uuid, code FROM kbite ORDER BY code")
            return KbiteListResponse(kbites: rows.map { KbiteRef(uuid: $0["uuid"], code: $0["code"]) })
        }
        let scopes = try resolveAncestorScopes(scope: req.scope, ownerUuid: req.ownerUuid)
        var seen: Set<String> = []
        var refs: [KbiteRef] = []
        for (level, uuid) in scopes {
            let rows = try Row.fetchAll(db, sql: """
                SELECT k.uuid, k.code FROM kbite k
                JOIN \(level)_active_kbite j ON j.kbite_uuid = k.uuid
                WHERE j.\(level)_uuid = ?
                """, arguments: [uuid])
            for row in rows {
                let kbiteUuid: String = row["uuid"]
                if seen.insert(kbiteUuid).inserted {
                    refs.append(KbiteRef(uuid: kbiteUuid, code: row["code"]))
                }
            }
        }
        return KbiteListResponse(kbites: refs.sorted { $0.code < $1.code })
    }

    /// Explicit-only registration (v11 model — the daemon never adds a kbite
    /// on its own). Idempotent: re-adding an existing junction reports
    /// added: false rather than erroring.
    func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try requireScopeOwner(scope: req.scope, ownerUuid: req.ownerUuid)
        let kbiteUuid = try context.ensureKbite(code: req.code)
        let level = req.scope.rawValue
        let exists = try Row.fetchOne(db, sql: """
            SELECT 1 FROM \(level)_active_kbite WHERE \(level)_uuid = ? AND kbite_uuid = ?
            """, arguments: [req.ownerUuid, kbiteUuid]) != nil
        if !exists {
            try core.insertBase(db, table: "\(level)_active_kbite", extra: [
                "\(level)_uuid": req.ownerUuid,
                "kbite_uuid": kbiteUuid,
            ])
            try core.appendEvent(
                db, kind: .addKbite, subjectUuid: req.ownerUuid,
                payload: Store.jsonPayload(["scope": level, "code": req.code]))
        }
        return KbiteAddResponse(kbiteUuid: kbiteUuid, code: req.code, added: !exists)
    }

    /// Remove a kbite from ONE scope's registry (never cascades to other
    /// scopes, never deletes the kbite row itself).
    func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try requireScopeOwner(scope: req.scope, ownerUuid: req.ownerUuid)
        guard let kbiteUuid = try String.fetchOne(
            db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [req.code]
        ) else {
            return KbiteRemoveResponse(removed: false)
        }
        let level = req.scope.rawValue
        try db.execute(sql: """
            DELETE FROM \(level)_active_kbite WHERE \(level)_uuid = ? AND kbite_uuid = ?
            """, arguments: [req.ownerUuid, kbiteUuid])
        let removed = db.changesCount > 0
        if removed {
            try core.appendEvent(
                db, kind: .removeKbite, subjectUuid: req.ownerUuid,
                payload: Store.jsonPayload(["scope": level, "code": req.code]))
        }
        return KbiteRemoveResponse(removed: removed)
    }

    // MARK: - Scope resolution

    /// The owner's own scope plus every ancestor scope+uuid, walked up the
    /// prompt → session → instance → project FK columns.
    func resolveAncestorScopes(
        scope: KbiteScope, ownerUuid: String
    ) throws -> [(level: String, uuid: String)] {
        var scopes: [(level: String, uuid: String)] = [(scope.rawValue, ownerUuid)]
        var current = (scope: scope, uuid: ownerUuid)
        while true {
            let parent: (scope: KbiteScope, column: String)?
            switch current.scope {
            case .prompt: parent = (.session, "session_uuid")
            case .session: parent = (.instance, "instance_uuid")
            case .instance: parent = (.project, "project_uuid")
            case .project: parent = nil
            }
            guard let parent else { break }
            guard let parentUuid = try String.fetchOne(
                db,
                sql: "SELECT \(parent.column) FROM \(current.scope.rawValue) WHERE uuid = ?",
                arguments: [current.uuid]
            ) else {
                throw StoreError.notFound(entity: current.scope.rawValue, key: current.uuid)
            }
            scopes.append((parent.scope.rawValue, parentUuid))
            current = (parent.scope, parentUuid)
        }
        return scopes
    }

    /// Mutations verify the owner row exists so a typo'd uuid surfaces as
    /// NOT_FOUND instead of a silently empty registry.
    private func requireScopeOwner(scope: KbiteScope, ownerUuid: String) throws {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM \(scope.rawValue) WHERE uuid = ?", arguments: [ownerUuid]
        ) != nil else {
            throw StoreError.notFound(entity: scope.rawValue, key: ownerUuid)
        }
    }
}
