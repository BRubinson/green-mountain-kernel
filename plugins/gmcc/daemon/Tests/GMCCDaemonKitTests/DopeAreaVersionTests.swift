import GRDB
import XCTest
@testable import GMCCDaemonKit

/// Sub-loadable dope: per-area content counters that sit BESIDE
/// dope_scope.revision rather than replacing it.
///
/// The invariant these tests defend is the one that made the "split the
/// revision" reading wrong: dope_scope.revision stays the single whole-tree
/// counter and the sole CAS gate, so ingest, write-repo and boot sync are
/// untouched by sub-versioning.
final class DopeAreaVersionTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var scopeUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-area-\(UUID().uuidString).db").path
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
                """)
        }
        scopeUuid = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: nil, code: "gmcc", name: "GMCC")).scope.uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func areas() throws -> [String: Int64] {
        try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).areaVersions ?? [:]
    }

    func testBothAreasStartAtZero() throws {
        XCTAssertEqual(try areas(), ["persistence": 0, "cogs": 0])
    }

    /// The point of sub-loading: touching persistence must not make a client
    /// believe cogs changed.
    func testPersistenceEditsDoNotMoveTheCogsCounter() throws {
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let a = try areas()
        XCTAssertGreaterThan(a["persistence"] ?? 0, 0)
        XCTAssertEqual(a["cogs"], 0, "a persistence edit moved the cogs counter")
    }

    func testCogEditsDoNotMoveThePersistenceCounter() throws {
        _ = try store.dopeCogAdd(DopeCogAddRequest(
            scopeUuid: scopeUuid, code: "systems", name: "Systems"))
        let a = try areas()
        XCTAssertGreaterThan(a["cogs"] ?? 0, 0)
        XCTAssertEqual(a["persistence"], 0, "a cog edit moved the persistence counter")
    }

    /// A deep edit still attributes to its owning domain, so a client
    /// watching one area sees it.
    func testDeepPersistenceEditsAttributeToTheOwningDomain() throws {
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let after = try areas()["persistence"] ?? 0
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        XCTAssertGreaterThan(try areas()["persistence"] ?? 0, after)
        let afterEntity = try areas()["persistence"] ?? 0
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .text)))
        XCTAssertGreaterThan(try areas()["persistence"] ?? 0, afterEntity,
                             "a property edit must move its domain's counter")
    }

    /// THE invariant. Splitting dope_scope.revision would have broken every
    /// CAS gate at once; the area counters are additive and it still counts
    /// the whole tree.
    func testWholeTreeRevisionStillCountsEveryAreaAndRemainsTheGate() throws {
        let before = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree.revision
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        _ = try store.dopeCogAdd(DopeCogAddRequest(
            scopeUuid: scopeUuid, code: "systems", name: "Systems"))
        let after = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree.revision
        XCTAssertEqual(after, before + 2,
                       "the whole-tree counter must advance for BOTH areas")
    }

    /// Area counters must never disturb the optimistic lock — that split is
    /// what keeps a GMVibes editor's held version valid across deep edits.
    func testAreaBumpsDoNotTouchTheScopeRowVersion() throws {
        let v0 = try store.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT version FROM dope_scope WHERE uuid = ?",
                               arguments: [self.scopeUuid!])!
        }
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        _ = try store.dopeCogAdd(DopeCogAddRequest(
            scopeUuid: scopeUuid, code: "systems", name: "Systems"))
        let v1 = try store.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT version FROM dope_scope WHERE uuid = ?",
                               arguments: [self.scopeUuid!])!
        }
        XCTAssertEqual(v0, v1, "the split-counter invariant was broken")
    }
}
