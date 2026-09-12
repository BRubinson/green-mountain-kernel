import GRDB
import XCTest
@testable import GMCCDaemonKit

/// BASE_PROJECT promotion: the db -> db, cross-tier, branch-conditioned sync.
///
/// The tests that matter most are the two the high-water mark exists for.
/// A naive "is the source newer than the base" predicate passes a simple
/// round-trip test and still ping-pongs forever between two instances.
final class DopePromotionTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-promote-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String { "NULL, '\(uuid)', 0, '\(now)', '\(now)'" }
            // Two instances of ONE project, each with a session on the same
            // branch code 'main' -- the concurrent-checkout shape.
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path,
                    ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/r1', 'x');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path,
                    ckfs_relative_storage_path)
                VALUES (\(base("inst-2")), 'proj-1', 'repo_2', 'repo_2', '/tmp/r2', 'y');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("sess-a")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("sess-b")), 'inst-2', 'main', 'main', '', '', 'active', 'y');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("sess-side")), 'inst-1', 'feature__x', 'feature/x', '', '',
                        'active', 'z');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @discardableResult
    private func seed(session: String, domains: Int) throws -> DopeScopeRow {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: session, promptUuid: nil, code: "gmcc", name: "GMCC")).scope
        for i in 0..<domains {
            _ = try store.dopeNodeAdd(DopeNodeAddRequest(
                level: .persistence, parentUuid: scope.uuid,
                fields: DopeNodeFields(code: "d\(i)", name: "D\(i)")))
        }
        return try store.dbQueue.read { try self.store.fetchDopeScope($0, uuid: scope.uuid)! }
    }

    private func baseScope() throws -> DopeScopeRow? {
        try store.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM dope_scope WHERE scope_type = 'BASE_PROJECT'
                """).map(Store.dopeScopeRow)
        }
    }

    func testPromotionCreatesTheBaseAndCopiesTheTree() throws {
        try seed(session: "sess-a", domains: 2)
        let r = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        XCTAssertEqual(r.promoted.count, 1)
        XCTAssertEqual(r.promoted[0].counts.domains, 2)
        let base = try baseScope()
        XCTAssertNotNil(base)
        XCTAssertNil(base?.sessionUuid, "a BASE_PROJECT scope is project-tier only")
        XCTAssertEqual(base?.projectUuid, "proj-1")
    }

    /// Without a recorded high-water, this re-publishes identical content at
    /// every SessionStart and storms DOPE_CHANGE.
    func testPromotionIsIdempotentAcrossRepeatedBoots() throws {
        try seed(session: "sess-a", domains: 2)
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        let first = try baseScope()!.revision
        for _ in 0..<3 {
            let again = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
            XCTAssertTrue(again.promoted.isEmpty, "re-promoted unchanged content")
            XCTAssertEqual(again.skipped, "up_to_date")
        }
        XCTAssertEqual(try baseScope()!.revision, first)
    }

    /// THE failure a base-revision predicate does not catch: instance A at a
    /// high revision and instance B at a low one would each look "newer than
    /// the base" right after the other landed, forever.
    func testPromotionNeverPingPongsBetweenTwoInstancesOnTheSameBranch() throws {
        try seed(session: "sess-a", domains: 5)   // the ahead instance
        try seed(session: "sess-b", domains: 1)   // the behind instance
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        let afterA = try baseScope()!
        let domainsAfterA = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_persistence WHERE dope_scope_uuid = ?
                """, arguments: [afterA.uuid])
        }
        XCTAssertEqual(domainsAfterA, 5)

        // B is behind the recorded high-water, so it must not publish...
        let b = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-b"))
        XCTAssertTrue(b.promoted.isEmpty, "a behind instance clobbered the base")
        // ...and A must not re-publish either. Stable, not alternating.
        let a2 = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        XCTAssertTrue(a2.promoted.isEmpty)
        XCTAssertEqual(try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_persistence WHERE dope_scope_uuid = ?
                """, arguments: [afterA.uuid])
        }, 5)
    }

    func testOnlyThePrimaryBranchMayPromote() throws {
        try seed(session: "sess-side", domains: 2)
        let r = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-side"))
        XCTAssertEqual(r.skipped, "branch_mismatch")
        XCTAssertNil(try baseScope())
    }

    /// The project setting is what selects the branch, so changing it changes
    /// who may publish.
    func testChangingPrimaryProjectBranchChangesWhoMayPromote() throws {
        try seed(session: "sess-side", domains: 2)
        _ = try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 0,
            primaryProjectBranch: "feature/x"))
        let r = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-side"))
        XCTAssertEqual(r.promoted.count, 1, "the newly-primary branch must publish")
    }

    /// A virgin scope must never blank a populated base.
    func testPromotionRefusesToOverwriteAPopulatedBaseWithAnEmptyTree() throws {
        try seed(session: "sess-a", domains: 3)
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        // sess-b has a scope with no domains, but bump its revision past the
        // high-water so ONLY the emptiness guard can stop it.
        let empty = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-b", promptUuid: nil, code: "gmcc", name: "GMCC")).scope
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE dope_scope SET revision = 9999 WHERE uuid = ?",
                           arguments: [empty.uuid])
        }
        XCTAssertThrowsError(
            try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-b")))
        let baseUuid = try baseScope()!.uuid
        XCTAssertEqual(try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_persistence WHERE dope_scope_uuid = ?
                """, arguments: [baseUuid])
        }, 3, "the populated base was blanked")
    }

    /// Republishing after real work advances the base and its high-water.
    func testAdvancingTheSessionRepublishes() throws {
        let scope = try seed(session: "sess-a", domains: 1)
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        let r1 = try baseScope()!.revision
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "later", name: "Later")))
        let r = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        XCTAssertEqual(r.promoted.count, 1)
        XCTAssertEqual(r.promoted[0].counts.domains, 2)
        XCTAssertGreaterThan(try baseScope()!.revision, r1)
    }

    /// gm doctor calls promotion as a DRY RUN, so it must report what would
    /// happen and write absolutely nothing. A doctor that published as a side
    /// effect of being run would be a trap.
    func testDryRunReportsWithoutWriting() throws {
        try seed(session: "sess-a", domains: 2)
        let preview = try store.dopePromote(DopePromoteRequest(
            sessionUuid: "sess-a", dryRun: true))
        XCTAssertEqual(preview.promoted.count, 1, "dry run must report the pending publish")
        XCTAssertNil(try baseScope(), "dry run created a BASE_PROJECT scope")

        // And the real run still works afterwards.
        let real = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        XCTAssertEqual(real.promoted.count, 1)
        XCTAssertNotNil(try baseScope())

        // A second dry run now reports nothing pending.
        XCTAssertTrue(try store.dopePromote(DopePromoteRequest(
            sessionUuid: "sess-a", dryRun: true)).promoted.isEmpty)
    }

    /// A dry run must not advance the high-water either, or the real
    /// promotion that follows would be skipped.
    func testDryRunDoesNotAdvanceTheHighWater() throws {
        try seed(session: "sess-a", domains: 1)
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a"))
        let rev = try baseScope()!.revision
        _ = try store.dopePromote(DopePromoteRequest(sessionUuid: "sess-a", dryRun: true))
        XCTAssertEqual(try baseScope()!.revision, rev)
    }
}
