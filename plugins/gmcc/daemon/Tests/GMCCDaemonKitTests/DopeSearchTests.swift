import GRDB
import XCTest
@testable import GMCCDaemonKit

/// gm dope search over m0015's FTS5 mirrors, at all three scopes, plus the
/// --only-masks provenance post-filter.
final class DopeSearchTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var sessionScope: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-search-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String { "NULL, '\(uuid)', 0, '\(now)', '\(now)'" }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path,
                    ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/r', 'x');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command,
                    status, ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '',
                        'draft', '');
                """)
        }
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: nil, code: "gmcc", name: "GMCC")).scope
        sessionScope = scope.uuid
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "billing", name: "Billing",
                                   description: "invoices and payments")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "invoice", name: "Invoice",
                                   description: "a customer invoice")))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testSessionScopeFindsEntitiesAndDomains() throws {
        let r = try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .session, sessionUuid: "sess-1"))
        XCTAssertFalse(r.hits.isEmpty)
        XCTAssertTrue(r.hits.contains { $0.path == "billing.invoice" },
                      "the dot-path must identify the hit")
    }

    func testProjectScopeSpansTheWholeProject() throws {
        let r = try store.dopeSearch(DopeSearchRequest(
            query: "payments", scope: .project, projectUuid: "proj-1"))
        XCTAssertTrue(r.hits.contains { $0.kind == "persistence" && $0.path == "billing" })
    }

    func testPromptScopeIncludesTheSessionBaseItReadsThrough() throws {
        let r = try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .prompt, promptUuid: "prompt-a"))
        XCTAssertFalse(r.hits.isEmpty, "a prompt search must see the session base")
    }

    func testFtsTriggersKeepMirrorsCurrent() throws {
        // m0015's _au trigger: a rename must be searchable immediately.
        let hits0 = try store.dopeSearch(DopeSearchRequest(
            query: "renamed", scope: .session, sessionUuid: "sess-1")).hits
        XCTAssertTrue(hits0.isEmpty)
        let scope = try store.dbQueue.read { try self.store.fetchDopeScope($0, uuid: self.sessionScope)! }
        let domainUuid = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM dope_persistence WHERE dope_scope_uuid = ? AND code = 'billing'
                """, arguments: [scope.uuid])!
        }
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .persistence, nodeUuid: domainUuid, expectedVersion: 0,
            fields: DopeNodeFields(name: "Renamed")))
        let hits1 = try store.dopeSearch(DopeSearchRequest(
            query: "renamed", scope: .session, sessionUuid: "sess-1")).hits
        XCTAssertFalse(hits1.isEmpty, "the FTS update trigger did not fire")
    }

    func testWhitespaceQueryIsARefusalNotAnEmptyList() throws {
        XCTAssertThrowsError(try store.dopeSearch(DopeSearchRequest(
            query: "   ", scope: .session, sessionUuid: "sess-1")))
    }

    func testUnknownOwnerIsNotFound() throws {
        XCTAssertThrowsError(try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .session, sessionUuid: "nope")))
    }

    func testMissingOwnerForScopeIsABadRequest() throws {
        XCTAssertThrowsError(try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .project)))
    }

    /// --only-masks keeps overlay-origin hits and drops base ones, using the
    /// resolver's provenance rather than a SQL join.
    func testOnlyMasksKeepsOverlayHitsAndDropsBaseHits() throws {
        // An overlay that overrides billing.invoice and adds a new entity.
        let overlay = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: "prompt-a", code: "gmcc", name: "GMCC")).scope
        let od = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: overlay.uuid,
            fields: DopeNodeFields(code: "billing", name: "Billing")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: od.uuid,
            fields: DopeNodeFields(code: "invoice", name: "Invoice",
                                   description: "my overridden invoice")))

        let all = try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .prompt, promptUuid: "prompt-a")).hits
        XCTAssertTrue(all.count >= 2, "both layers should be searchable unfiltered")

        let masked = try store.dopeSearch(DopeSearchRequest(
            query: "invoice", scope: .prompt, promptUuid: "prompt-a",
            onlyMasks: true)).hits
        XCTAssertFalse(masked.isEmpty)
        XCTAssertTrue(masked.allSatisfy { $0.scopeUuid == overlay.uuid },
                      "--only-masks returned a base-scope hit")
        XCTAssertTrue(masked.allSatisfy { $0.origin != nil })
        XCTAssertTrue(masked.contains { $0.path == "billing.invoice" && $0.origin == "overridden" })
    }
}
