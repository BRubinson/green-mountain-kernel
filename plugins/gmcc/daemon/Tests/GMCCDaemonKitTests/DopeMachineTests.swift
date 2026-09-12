import XCTest
import GRDB
@testable import GMCCDaemonKit

final class DopeMachineTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-machine-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Helpers

    @discardableResult
    private func initScope(prompt: String? = nil, code: String = "gmcc",
                           clone: Bool? = nil) throws -> DopeScopeResponse {
        try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: prompt, code: code, name: "GMCC",
            description: "model", cloneFromSessionBase: clone))
    }

    @discardableResult
    private func addNode(_ level: DopeLevel, parent: String,
                         _ fields: DopeNodeFields) throws -> DopeNodeResponse {
        try store.dopeNodeAdd(DopeNodeAddRequest(level: level, parentUuid: parent, fields: fields))
    }

    private func buildSmallTree(scopeUuid: String) throws -> (domain: String, entity: String,
                                                              enumUuid: String, property: String) {
        let domain = try addNode(.persistence, parent: scopeUuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        let en = try addNode(.enumeration, parent: domain.uuid,
                             DopeNodeFields(code: "status", name: "Status"))
        try addNode(.option, parent: en.uuid, DopeNodeFields(code: "active", name: "Active"))
        let property = try addNode(.property, parent: entity.uuid,
                                   DopeNodeFields(code: "id", name: "Id",
                                                  dataType: .uuid, nullable: false,
                                                  isUnique: true))
        return (domain.uuid, entity.uuid, en.uuid, property.uuid)
    }

    // MARK: - Init

    func testInitIsIdempotentAndDerivesScopeType() throws {
        let first = try initScope()
        XCTAssertTrue(first.created)
        XCTAssertEqual(first.scope.scopeType, "SESSION_INSTANCE")
        XCTAssertEqual(first.scope.revision, 0)

        let again = try initScope()
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.scope.uuid, first.scope.uuid)

        let promptScope = try initScope(prompt: "prompt-a")
        XCTAssertTrue(promptScope.created)
        XCTAssertEqual(promptScope.scope.scopeType, "SESSION_INSTANCE_ITEM")
    }

    func testCloneFromSessionBaseCopiesTheTree() throws {
        let base = try initScope()
        _ = try buildSmallTree(scopeUuid: base.scope.uuid)
        // Plus a relationship property to prove the two-pass insert clones.
        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let entityUuid = tree.domains[0].entities[0].identity.uuid
        try addNode(.property, parent: entityUuid,
                    DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                   relationshipTargetUuid: tree.domains[0].entities[0]
                                       .properties[0].identity.uuid))

        let cloned = try initScope(prompt: "prompt-a", clone: true)
        XCTAssertTrue(cloned.created)
        let promptTree = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).tree
        XCTAssertEqual(promptTree.identity.uuid, cloned.scope.uuid)
        XCTAssertEqual(promptTree.domains.count, 1)
        XCTAssertEqual(promptTree.domains[0].entities[0].properties.count, 2)
        // Cloned rows are new rows.
        XCTAssertNotEqual(promptTree.domains[0].identity.uuid, tree.domains[0].identity.uuid)
        // The relationship ref re-resolved inside the clone.
        let owner = promptTree.domains[0].entities[0].properties.first { $0.body.code == "owner" }
        XCTAssertEqual(owner?.body.relationshipTargetRef, "core.user.id")
    }

    // MARK: - Get fallback

    func testGetFallsBackToSessionBase() throws {
        _ = try initScope()
        let viaPrompt = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a"))
        XCTAssertEqual(viaPrompt.resolvedVia, "session_base")

        _ = try initScope(prompt: "prompt-a")
        let direct = try store.dopeGet(
            DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a"))
        XCTAssertEqual(direct.resolvedVia, "prompt")
    }

    // MARK: - List (v12)

    func testListReturnsSessionBaseScopesOnly() throws {
        _ = try initScope(code: "gmcc")
        _ = try initScope(code: "alpha")
        _ = try initScope(prompt: "prompt-a", code: "gmcc")

        let scopes = try store.dopeList(DopeListRequest(sessionUuid: "sess-1")).scopes
        XCTAssertEqual(scopes.map(\.code), ["alpha", "gmcc"], "ORDER BY code")
        XCTAssertTrue(scopes.allSatisfy { $0.scopeType == "SESSION_INSTANCE" })
    }

    func testListWithPromptReturnsPromptScopesOnlyNoUnion() throws {
        _ = try initScope(code: "gmcc")
        let promptScope = try initScope(prompt: "prompt-a", code: "gmcc").scope

        let scopes = try store.dopeList(
            DopeListRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).scopes
        XCTAssertEqual(scopes.map(\.uuid), [promptScope.uuid])
        XCTAssertEqual(scopes.first?.scopeType, "SESSION_INSTANCE_ITEM")
    }

    func testListOfAnUninitializedTargetIsAnEmptyListNotAnError() throws {
        XCTAssertEqual(try store.dopeList(DopeListRequest(sessionUuid: "sess-1")).scopes, [])
        XCTAssertEqual(try store.dopeList(
            DopeListRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")).scopes, [])
    }

    func testListRejectsUnknownUuids() throws {
        assertNotFound("session") { try self.store.dopeList(DopeListRequest(sessionUuid: "nope")) }
        assertNotFound("prompt") {
            try self.store.dopeList(DopeListRequest(sessionUuid: "sess-1", promptUuid: "nope"))
        }
    }

    // MARK: - Get absence discrimination (v12)

    func testGetOnRealButUninitializedTargetIsSummaryAbsent() throws {
        for req in [DopeGetRequest(sessionUuid: "sess-1"),
                    DopeGetRequest(sessionUuid: "sess-1", promptUuid: "prompt-a")] {
            XCTAssertThrowsError(try store.dopeGet(req)) { error in
                guard case StoreError.dopeScopeAbsent = error else {
                    return XCTFail("wrong error: \(error)")
                }
                let payload = (error as! StoreError).errorPayload
                XCTAssertEqual(payload.code, .summaryAbsent)
                XCTAssertTrue(payload.message.contains("DOPE_INIT"), payload.message)
            }
        }
    }

    func testGetRejectsUnknownUuidsBeforeAbsence() throws {
        _ = try initScope()   // a scope EXISTS, so only the guards can fire
        assertNotFound("session") { try self.store.dopeGet(DopeGetRequest(sessionUuid: "nope")) }
        assertNotFound("prompt") {
            try self.store.dopeGet(DopeGetRequest(sessionUuid: "sess-1", promptUuid: "nope"))
        }
    }

    private func assertNotFound(
        _ entity: String, file: StaticString = #filePath, line: UInt = #line,
        _ body: () throws -> Any
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case StoreError.notFound(let got, _) = error else {
                return XCTFail("wrong error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(got, entity, file: file, line: line)
        }
    }

    // MARK: - Revision vs version split

    func testNodeMutationsBumpRevisionNotScopeVersion() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let after = try store.dbQueue.read { db in
            try self.store.fetchDopeScope(db, uuid: scope.uuid)!
        }
        XCTAssertEqual(after.revision, 5, "five node adds = five revision bumps")
        XCTAssertEqual(after.version, 0, "scope optimistic-lock version must not move")

        let update = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: ids.entity, expectedVersion: 0,
            fields: DopeNodeFields(name: "Person")))
        XCTAssertEqual(update.revision, 6)
        XCTAssertEqual(update.version, 1)
    }

    // MARK: - Field ownership + shape

    func testFieldOwnershipMatrix() throws {
        let scope = try initScope().scope
        XCTAssertThrowsError(try addNode(.persistence, parent: scope.uuid,
                                         DopeNodeFields(code: "x", name: "X",
                                                        dataType: .text))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("has no field"), detail)
        }
        // entity code 'enums' is reserved.
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        XCTAssertThrowsError(try addNode(.entity, parent: domain.uuid,
                                         DopeNodeFields(code: "enums", name: "Enums")))
        // property requires data-type; enum data-type requires enum uuid.
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        XCTAssertThrowsError(try addNode(.property, parent: entity.uuid,
                                         DopeNodeFields(code: "p", name: "P")))
        XCTAssertThrowsError(try addNode(.property, parent: entity.uuid,
                                         DopeNodeFields(code: "p", name: "P",
                                                        dataType: .enumeration)))
    }

    func testChainRelationshipRefused() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let rel = try addNode(.property, parent: ids.entity,
                              DopeNodeFields(code: "owner", name: "Owner",
                                             dataType: .relationship,
                                             relationshipTargetUuid: ids.property))
        XCTAssertThrowsError(try addNode(
            .property, parent: ids.entity,
            DopeNodeFields(code: "chain", name: "Chain", dataType: .relationship,
                           relationshipTargetUuid: rel.uuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("chain"), detail)
        }
    }

    func testCrossScopeRefRefused() throws {
        let base = try initScope().scope
        let baseIds = try buildSmallTree(scopeUuid: base.uuid)
        let promptScope = try initScope(prompt: "prompt-a").scope
        let domain = try addNode(.persistence, parent: promptScope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User"))
        XCTAssertThrowsError(try addNode(
            .property, parent: entity.uuid,
            DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                           enumUuid: baseIds.enumUuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("different dope scope"), detail)
        }
    }

    // MARK: - Deletes

    func testDeleteEnumRefusedWhileReferencedThenAllowed() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        let state = try addNode(.property, parent: ids.entity,
                                DopeNodeFields(code: "state", name: "State",
                                               dataType: .enumeration,
                                               enumUuid: ids.enumUuid))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: ids.enumUuid, expectedVersion: 0))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("core.user.state"), detail)
        }
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .property, nodeUuid: state.uuid, expectedVersion: 0))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: ids.enumUuid, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.options, 1)
    }

    func testDomainDeleteHandlesInternalRelationships() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        // Internal referrers (relationship + enum property in the same
        // domain) must not block the ordered delete.
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                       relationshipTargetUuid: ids.property))
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                                       enumUuid: ids.enumUuid))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: ids.domain, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.properties, 3)
        try store.dbQueue.read { db in
            for table in ["dope_persistence", "dope_persistence_entity", "dope_persistence_enum",
                          "dope_persistence_enum_option", "dope_persistence_entity_property"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0)
            }
        }
    }

    /// Review fix [20]: a same-entity relationship pair must not trip the
    /// RESTRICT FK during entity-delete's property sweep (the target row has
    /// the lower rowid and is scanned first by a naive bulk DELETE).
    func testEntityDeleteWithSameEntityRelationshipPair() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        _ = try addNode(.property, parent: ids.entity,
                        DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                       relationshipTargetUuid: ids.property))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .entity, nodeUuid: ids.entity, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.properties, 2)
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM dope_persistence_entity_property"), 0)
        }
    }

    func testScopeDeleteDeferred() throws {
        let scope = try initScope().scope
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .scope, nodeUuid: scope.uuid, expectedVersion: 0)))
    }

    func testDeleteVersionGuard() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid, expectedVersion: 7))) { error in
            guard case StoreError.versionConflict = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Events

    func testDopeChangeEventsAreDurable() throws {
        let scope = try initScope().scope
        _ = try addNode(.persistence, parent: scope.uuid, DopeNodeFields(code: "core", name: "Core"))
        let kinds = try store.dbQueue.read { db in
            try String.fetchAll(
                db, sql: "SELECT kind FROM daemon_event WHERE subject_uuid = ?",
                arguments: [scope.uuid])
        }
        XCTAssertEqual(kinds, ["DOPE_CHANGE", "DOPE_CHANGE"], "init + node_add")
    }

    // MARK: - Base composables

    /// Adds a BASE_COMPOSABLE entity under `domain`.
    @discardableResult
    private func addBase(_ code: String, domain: String) throws -> DopeNodeResponse {
        try addNode(.entity, parent: domain,
                    DopeNodeFields(code: code, name: code, entityType: .baseComposable))
    }

    func testBaseComposableSameScopeEnforced() throws {
        let base = try initScope().scope
        let baseDomain = try addNode(.persistence, parent: base.uuid,
                                     DopeNodeFields(code: "core", name: "Core"))
        let baseEntity = try addBase("base_entity", domain: baseDomain.uuid)

        let promptScope = try initScope(prompt: "prompt-a").scope
        let domain = try addNode(.persistence, parent: promptScope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        XCTAssertThrowsError(try addNode(
            .entity, parent: domain.uuid,
            DopeNodeFields(code: "user", name: "User",
                           baseComposableUuid: baseEntity.uuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("different dope scope"), detail)
        }
    }

    func testBaseComposableTargetMustBeBaseComposable() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)   // 'user' is a MODEL
        XCTAssertThrowsError(try addNode(
            .entity, parent: ids.domain,
            DopeNodeFields(code: "post", name: "Post",
                           baseComposableUuid: ids.entity))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("only a BASE_COMPOSABLE"), detail)
        }
    }

    func testBaseComposableChainingAllowedButCycleRefused() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let a = try addBase("b_one", domain: domain.uuid)
        let b = try addBase("b_two", domain: domain.uuid)
        let c = try addBase("b_three", domain: domain.uuid)

        // Chaining is legal: a → b → c.
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: a.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: b.uuid)))
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: b.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: c.uuid)))

        // Closing the loop (c → a) is the 3-cycle; refused at the last call.
        XCTAssertThrowsError(try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: c.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: a.uuid)))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("cycle"), detail)
        }

        // The 2-cycle: d → e, then e → d refused.
        let d = try addBase("b_four", domain: domain.uuid)
        let e = try addBase("b_five", domain: domain.uuid)
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: d.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: e.uuid)))
        XCTAssertThrowsError(try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: e.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: d.uuid))))

        // The 1-cycle: an entity may not compose itself.
        XCTAssertThrowsError(try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: c.uuid, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: c.uuid)))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("compose itself"), detail)
        }
    }

    func testDemotingAComposedBaseIsRefused() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let base = try addBase("base_entity", domain: domain.uuid)
        _ = try addNode(.entity, parent: domain.uuid,
                        DopeNodeFields(code: "user", name: "User",
                                       baseComposableUuid: base.uuid))
        XCTAssertThrowsError(try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: base.uuid, expectedVersion: 0,
            fields: DopeNodeFields(entityType: .model)))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("core.user"), detail)
        }
    }

    func testDeleteBaseRefusedWhileComposedThenAllowed() throws {
        let scope = try initScope().scope
        let coreDomain = try addNode(.persistence, parent: scope.uuid,
                                     DopeNodeFields(code: "core", name: "Core"))
        let baseDomain = try addNode(.persistence, parent: scope.uuid,
                                     DopeNodeFields(code: "base", name: "Base"))
        let base = try addBase("base_entity", domain: baseDomain.uuid)
        let user = try addNode(.entity, parent: coreDomain.uuid,
                               DopeNodeFields(code: "user", name: "User",
                                              baseComposableUuid: base.uuid))

        // Deleting the composed base — or the domain holding it — is refused
        // naming the cross-domain composer.
        for (level, uuid) in [(DopeLevel.entity, base.uuid), (.persistence, baseDomain.uuid)] {
            XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
                level: level, nodeUuid: uuid, expectedVersion: 0))) { error in
                guard case StoreError.badRequest(let detail) = error else {
                    return XCTFail("wrong error: \(error)")
                }
                XCTAssertTrue(detail.contains("core.user"), detail)
            }
        }

        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: user.uuid, expectedVersion: 0,
            fields: DopeNodeFields(clearBaseComposable: true)))
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .entity, nodeUuid: base.uuid, expectedVersion: 0))
    }

    /// A same-domain base pair must not trip the RESTRICT self-FK during the
    /// domain delete's CASCADE (the NULL-out pre-step).
    func testDomainDeleteWithInternalBasePair() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let base = try addBase("base_entity", domain: domain.uuid)
        _ = try addNode(.entity, parent: domain.uuid,
                        DopeNodeFields(code: "user", name: "User",
                                       baseComposableUuid: base.uuid))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.entities, 2)
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_persistence_entity"), 0)
        }
    }

    // MARK: - Materialized base properties (m0009)

    private func expectBadRequest(
        _ containing: String, file: StaticString = #filePath, line: UInt = #line,
        _ block: () throws -> Void
    ) {
        XCTAssertThrowsError(try block(), file: file, line: line) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(detail.contains(containing), detail, file: file, line: line)
        }
    }

    /// Base entity + one datetime property on it, plus a MODEL entity.
    private func makeBaseWithProperty(
        scopeUuid: String
    ) throws -> (domain: String, base: String, originProp: String, model: String) {
        let domain = try addNode(.persistence, parent: scopeUuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let base = try addBase("base_entity", domain: domain.uuid)
        let origin = try addNode(.property, parent: base.uuid,
                                 DopeNodeFields(code: "created_at", name: "Created At",
                                                dataType: .datetime, nullable: false))
        let model = try addNode(.entity, parent: domain.uuid,
                                DopeNodeFields(code: "user", name: "User",
                                               baseComposableUuid: base.uuid))
        return (domain.uuid, base.uuid, origin.uuid, model.uuid)
    }

    func testBaseOriginRequiresTheOwningEntityToComposeTheOrigin() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        let loner = try addNode(.entity, parent: ids.domain,
                                DopeNodeFields(code: "loner", name: "Loner"))
        expectBadRequest("does not compose") {
            _ = try self.addNode(.property, parent: loner.uuid,
                                 DopeNodeFields(code: "created_at", name: "Created At",
                                                dataType: .datetime,
                                                baseOriginPropertyUuid: ids.originProp))
        }
        // The composing entity may materialize it.
        _ = try addNode(.property, parent: ids.model,
                        DopeNodeFields(code: "created_at", name: "Created At",
                                       dataType: .datetime,
                                       baseOriginPropertyUuid: ids.originProp))
    }

    func testBaseOriginResolvesThroughAChain() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let b2 = try addBase("b_two", domain: domain.uuid)
        let stamp = try addNode(.property, parent: b2.uuid,
                                DopeNodeFields(code: "stamp", name: "Stamp",
                                               dataType: .datetime))
        let b1 = try addNode(.entity, parent: domain.uuid,
                             DopeNodeFields(code: "b_one", name: "b_one",
                                            entityType: .baseComposable,
                                            baseComposableUuid: b2.uuid))
        let leaf = try addNode(.entity, parent: domain.uuid,
                               DopeNodeFields(code: "leaf", name: "Leaf",
                                              baseComposableUuid: b1.uuid))
        _ = try addNode(.property, parent: leaf.uuid,
                        DopeNodeFields(code: "stamp", name: "Stamp", dataType: .datetime,
                                       baseOriginPropertyUuid: stamp.uuid))
    }

    func testBaseOriginMustMatchTheOriginDataType() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        expectBadRequest("must keep the origin's data_type") {
            _ = try self.addNode(.property, parent: ids.model,
                                 DopeNodeFields(code: "created_at", name: "Created At",
                                                dataType: .text,
                                                baseOriginPropertyUuid: ids.originProp))
        }
    }

    func testBaseOriginCannotPointAtItself() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        let prop = try addNode(.property, parent: ids.model,
                               DopeNodeFields(code: "created_at", name: "Created At",
                                              dataType: .datetime))
        expectBadRequest("originate from itself") {
            _ = try self.store.dopeNodeUpdate(DopeNodeUpdateRequest(
                level: .property, nodeUuid: prop.uuid, expectedVersion: 0,
                fields: DopeNodeFields(baseOriginPropertyUuid: prop.uuid)))
        }
    }

    func testClearingOrRepointingTheBaseThatStrandsATagIsRefused() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        _ = try addNode(.property, parent: ids.model,
                        DopeNodeFields(code: "created_at", name: "Created At",
                                       dataType: .datetime,
                                       baseOriginPropertyUuid: ids.originProp))
        // Clear strands the tag.
        expectBadRequest("still originates from a base") {
            _ = try self.store.dopeNodeUpdate(DopeNodeUpdateRequest(
                level: .entity, nodeUuid: ids.model, expectedVersion: 0,
                fields: DopeNodeFields(clearBaseComposable: true)))
        }
        // Re-pointing to a different base strands it just as thoroughly.
        let other = try addBase("other_base", domain: ids.domain)
        expectBadRequest("still originates from a base") {
            _ = try self.store.dopeNodeUpdate(DopeNodeUpdateRequest(
                level: .entity, nodeUuid: ids.model, expectedVersion: 0,
                fields: DopeNodeFields(baseComposableUuid: other.uuid)))
        }
        // An unrelated update with tags intact is allowed (self-neutralizing).
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: ids.model, expectedVersion: 0,
            fields: DopeNodeFields(name: "User Renamed")))
    }

    func testDeleteOriginPropertyRefusedWhileTaggedThenAllowed() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        let tagged = try addNode(.property, parent: ids.model,
                                 DopeNodeFields(code: "created_at", name: "Created At",
                                                dataType: .datetime,
                                                baseOriginPropertyUuid: ids.originProp))
        expectBadRequest("core.user.created_at") {
            _ = try self.store.dopeNodeDelete(DopeNodeDeleteRequest(
                level: .property, nodeUuid: ids.originProp, expectedVersion: 0))
        }
        // Deleting the base entity (and its domain) is refused the same way.
        expectBadRequest("core.user.created_at") {
            _ = try self.store.dopeNodeDelete(DopeNodeDeleteRequest(
                level: .entity, nodeUuid: ids.base, expectedVersion: 0))
        }
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .property, nodeUuid: tagged.uuid, expectedVersion: 0,
            fields: DopeNodeFields(clearBaseOrigin: true)))
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .property, nodeUuid: ids.originProp, expectedVersion: 0))
    }

    func testDomainDeleteRefusedWhileACrossDomainTagPointsIn() throws {
        let scope = try initScope().scope
        let baseDomain = try addNode(.persistence, parent: scope.uuid,
                                     DopeNodeFields(code: "base", name: "Base"))
        let base = try addBase("base_entity", domain: baseDomain.uuid)
        let origin = try addNode(.property, parent: base.uuid,
                                 DopeNodeFields(code: "stamp", name: "Stamp",
                                                dataType: .datetime))
        let coreDomain = try addNode(.persistence, parent: scope.uuid,
                                     DopeNodeFields(code: "core", name: "Core"))
        let user = try addNode(.entity, parent: coreDomain.uuid,
                               DopeNodeFields(code: "user", name: "User",
                                              baseComposableUuid: base.uuid))
        _ = try addNode(.property, parent: user.uuid,
                        DopeNodeFields(code: "stamp", name: "Stamp", dataType: .datetime,
                                       baseOriginPropertyUuid: origin.uuid))
        expectBadRequest("core.user.stamp") {
            _ = try self.store.dopeNodeDelete(DopeNodeDeleteRequest(
                level: .persistence, nodeUuid: baseDomain.uuid, expectedVersion: 0))
        }
    }

    /// Base and composer in the SAME domain: the domain delete succeeds only
    /// because the base_origin NULL-out precedes both property DELETEs.
    func testDomainDeleteWithInternalBaseOriginTags() throws {
        let scope = try initScope().scope
        let ids = try makeBaseWithProperty(scopeUuid: scope.uuid)
        _ = try addNode(.property, parent: ids.model,
                        DopeNodeFields(code: "created_at", name: "Created At",
                                       dataType: .datetime,
                                       baseOriginPropertyUuid: ids.originProp))
        let deleted = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: ids.domain, expectedVersion: 0))
        XCTAssertEqual(deleted.cascaded.properties, 2)
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM dope_persistence_entity_property"), 0)
        }
    }

    func testEntityBaseFieldOwnership() throws {
        let scope = try initScope().scope
        let ids = try buildSmallTree(scopeUuid: scope.uuid)
        // baseComposableUuid is entity-owned; a property update carrying it
        // is a precise refusal.
        XCTAssertThrowsError(try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .property, nodeUuid: ids.property, expectedVersion: 0,
            fields: DopeNodeFields(baseComposableUuid: ids.entity)))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("has no field"), detail)
        }
        // …and baseOriginPropertyUuid is property-owned, not entity-owned.
        expectBadRequest("has no field") {
            _ = try self.store.dopeNodeUpdate(DopeNodeUpdateRequest(
                level: .entity, nodeUuid: ids.entity, expectedVersion: 0,
                fields: DopeNodeFields(baseOriginPropertyUuid: ids.property)))
        }
    }

    /// Review fix: every clear flag must persist a real NULL — a typed-nil
    /// subscript assignment used to drop the key, making clear-alone calls
    /// throw emptyUpdate and combined calls silently skip the clear.
    func testClearFlagsPersistNulls() throws {
        let scope = try initScope().scope
        let domain = try addNode(.persistence, parent: scope.uuid,
                                 DopeNodeFields(code: "core", name: "Core"))
        let entity = try addNode(.entity, parent: domain.uuid,
                                 DopeNodeFields(code: "user", name: "User",
                                                repoRepresentativeFile: "Sources/User.swift"))
        let en = try addNode(.enumeration, parent: domain.uuid,
                             DopeNodeFields(code: "status", name: "Status"))

        // clear-repo-representative-file ALONE (used to throw emptyUpdate).
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: entity.uuid, expectedVersion: 0,
            fields: DopeNodeFields(clearRepoRepresentativeFile: true)))

        // clear-auto-increment and clear-text-char-limit ALONE.
        let counter = try addNode(.property, parent: entity.uuid,
                                  DopeNodeFields(code: "counter", name: "Counter",
                                                 dataType: .long, autoIncrement: true))
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .property, nodeUuid: counter.uuid, expectedVersion: 0,
            fields: DopeNodeFields(clearAutoIncrement: true)))
        let note = try addNode(.property, parent: entity.uuid,
                               DopeNodeFields(code: "note", name: "Note",
                                              dataType: .text, textCharLimit: 80))
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .property, nodeUuid: note.uuid, expectedVersion: 0,
            fields: DopeNodeFields(clearTextCharLimit: true)))

        // clear-enum COMBINED with a data-type change (the silent-skip path;
        // clear-alone is refused by the CHECK coupling by design).
        let state = try addNode(.property, parent: entity.uuid,
                                DopeNodeFields(code: "state", name: "State",
                                               dataType: .enumeration, enumUuid: en.uuid))
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .property, nodeUuid: state.uuid, expectedVersion: 0,
            fields: DopeNodeFields(dataType: .text, clearEnum: true)))

        try store.dbQueue.read { db in
            XCTAssertNil(try String.fetchOne(db, sql:
                "SELECT repo_representative_file FROM dope_persistence_entity WHERE uuid = ?",
                arguments: [entity.uuid]) ?? nil)
            XCTAssertNil(try Int64.fetchOne(db, sql:
                "SELECT auto_increment FROM dope_persistence_entity_property WHERE uuid = ?",
                arguments: [counter.uuid]) ?? nil)
            XCTAssertNil(try Int64.fetchOne(db, sql:
                "SELECT text_char_limit FROM dope_persistence_entity_property WHERE uuid = ?",
                arguments: [note.uuid]) ?? nil)
            let stateRow = try Row.fetchOne(db, sql:
                "SELECT data_type, dope_persistence_enum_uuid FROM dope_persistence_entity_property WHERE uuid = ?",
                arguments: [state.uuid])
            XCTAssertEqual(stateRow?["data_type"] as String?, "text")
            XCTAssertNil(stateRow?["dope_persistence_enum_uuid"] as String?)
        }
    }
}
