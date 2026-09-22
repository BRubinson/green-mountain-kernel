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
            let records = try KbiteRecord.order(KbiteRecord.Columns.code).fetchAll(db)
            return KbiteListResponse(
                kbites: records.map { KbiteRef(uuid: $0.uuid, code: $0.code) }
            )
        }
        let scopes = try ancestorScopes(scope: req.scope, ownerUuid: req.ownerUuid)
        var seen: Set<String> = []
        var refs: [KbiteRef] = []
        for (scope, uuid) in scopes {
            for record in try activeKbites(scope: scope, ownerUuid: uuid)
            where seen.insert(record.uuid).inserted {
                refs.append(KbiteRef(uuid: record.uuid, code: record.code))
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
        let exists =
            try Table("\(level)_active_kbite")
            .filter(Column("\(level)_uuid") == req.ownerUuid && Column("kbite_uuid") == kbiteUuid)
            .fetchCount(db) > 0
        if !exists {
            try core.insertBase(
                db,
                table: "\(level)_active_kbite",
                extra: [
                    "\(level)_uuid": req.ownerUuid,
                    "kbite_uuid": kbiteUuid,
                ]
            )
            try core.appendEvent(
                db,
                kind: .addKbite,
                subjectUuid: req.ownerUuid,
                payload: Store.jsonPayload(["scope": level, "code": req.code])
            )
        }
        return KbiteAddResponse(kbiteUuid: kbiteUuid, code: req.code, added: !exists)
    }

    /// Remove a kbite from ONE scope's registry (never cascades to other
    /// scopes, never deletes the kbite row itself).
    func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try requireScopeOwner(scope: req.scope, ownerUuid: req.ownerUuid)
        guard
            let kbiteUuid =
                try KbiteRecord
                .filter(KbiteRecord.Columns.code == req.code)
                .select(KbiteRecord.Columns.uuid, as: String.self)
                .fetchOne(db)
        else {
            return KbiteRemoveResponse(removed: false)
        }
        let level = req.scope.rawValue
        try db.execute(
            sql: """
                DELETE FROM \(level)_active_kbite WHERE \(level)_uuid = ? AND kbite_uuid = ?
                """,
            arguments: [req.ownerUuid, kbiteUuid]
        )
        let removed = db.changesCount > 0
        if removed {
            try core.appendEvent(
                db,
                kind: .removeKbite,
                subjectUuid: req.ownerUuid,
                payload: Store.jsonPayload(["scope": level, "code": req.code])
            )
        }
        return KbiteRemoveResponse(removed: removed)
    }

    // MARK: - Registry reads

    /// The kbites one scope owner has registered, ordered by code.
    private func activeKbites(scope: KbiteScope, ownerUuid: String) throws -> [KbiteRecord] {
        let kbites = KbiteRecord.order(Column("code"))
        switch scope {
        case .project:
            return
                try kbites.joining(
                    required: KbiteRecord.projectActivations
                        .filter(Column("project_uuid") == ownerUuid)
                )
                .fetchAll(db)
        case .instance:
            return
                try kbites.joining(
                    required: KbiteRecord.instanceActivations
                        .filter(Column("instance_uuid") == ownerUuid)
                )
                .fetchAll(db)
        case .session:
            return
                try kbites.joining(
                    required: KbiteRecord.sessionActivations
                        .filter(Column("session_uuid") == ownerUuid)
                )
                .fetchAll(db)
        case .prompt:
            return
                try kbites.joining(
                    required: KbiteRecord.promptActivations
                        .filter(Column("prompt_uuid") == ownerUuid)
                )
                .fetchAll(db)
        }
    }

    // MARK: - Scope resolution

    /// `ancestorScopes` spelled with the level as its raw string, for callers
    /// outside this repository.
    func resolveAncestorScopes(
        scope: KbiteScope,
        ownerUuid: String
    ) throws -> [(level: String, uuid: String)] {
        try ancestorScopes(scope: scope, ownerUuid: ownerUuid)
            .map { (level: $0.scope.rawValue, uuid: $0.uuid) }
    }

    /// The owner's own scope plus every ancestor scope+uuid, walked up the
    /// prompt → session → instance → project FK columns.
    private func ancestorScopes(
        scope: KbiteScope,
        ownerUuid: String
    ) throws -> [(scope: KbiteScope, uuid: String)] {
        var scopes: [(scope: KbiteScope, uuid: String)] = [(scope, ownerUuid)]
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
            guard
                let parentUuid = try Table(current.scope.rawValue)
                    .filter(Column("uuid") == current.uuid)
                    .select(Column(parent.column), as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: current.scope.rawValue, key: current.uuid)
            }
            scopes.append((parent.scope, parentUuid))
            current = (parent.scope, parentUuid)
        }
        return scopes
    }

    /// Mutations verify the owner row exists so a typo'd uuid surfaces as
    /// NOT_FOUND instead of a silently empty registry.
    private func requireScopeOwner(scope: KbiteScope, ownerUuid: String) throws {
        guard try Table(scope.rawValue).filter(Column("uuid") == ownerUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: scope.rawValue, key: ownerUuid)
        }
    }
}
