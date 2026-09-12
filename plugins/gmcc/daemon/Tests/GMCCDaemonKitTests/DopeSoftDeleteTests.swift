import GRDB
import XCTest
@testable import GMCCDaemonKit

/// m0012's soft delete: `deleted_on` plus the partial-unique-index
/// conversion, and the `--soft` write path.
///
/// The load-bearing property proven here is the INVERSE of what it might
/// first seem: a tombstone must NEVER reach the saved `.doped.json`. The
/// committed format records REAL STATE only. A tombstone is a masking
/// artifact that rides on the overlay tiers (PROJECT_ITEM /
/// SESSION_INSTANCE_ITEM), which are db-only and never serialized -- so it
/// lives on the wire identity layer, which DopeProjection drops by
/// construction. Soft-deleting inside a base scope is refused outright.
final class DopeSoftDeleteTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-soft-\(UUID().uuidString).db").path
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
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
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
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    /// A SESSION_INSTANCE_ITEM (overlay) scope -- the only tier where a
    /// tombstone is meaningful.
    private func overlayScopeAndDomain() throws -> (scope: String, domain: DopeNodeResponse) {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: "prompt-a", code: "gmcc", name: "GMCC")).scope
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        return (scope.uuid, domain)
    }

    /// The whole reason the UNIQUE(parent, code) table constraints had to
    /// become partial indexes.
    func testSoftDeleteThenReAddSameCodeSucceeds() throws {
        let (scopeUuid, domain) = try overlayScopeAndDomain()
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version, soft: true))
        // Same code again: the tombstone no longer occupies the slot.
        let reAdded = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Core Again")))
        XCTAssertNotEqual(reAdded.uuid, domain.uuid)
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM dope_persistence WHERE dope_scope_uuid = ?
                    """, arguments: [scopeUuid]), 2, "the tombstone must still be a row")
        }
    }

    /// Uniqueness is narrowed, not abandoned.
    func testTwoLiveSiblingsWithTheSameCodeAreStillRejected() throws {
        let (scopeUuid, _) = try overlayScopeAndDomain()
        XCTAssertThrowsError(try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scopeUuid,
            fields: DopeNodeFields(code: "core", name: "Dup"))))
    }

    func testSoftDeleteIsNotRepeatable() throws {
        let (_, domain) = try overlayScopeAndDomain()
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version, soft: true))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version + 1, soft: true)))
    }

    /// Reads deliberately do NOT filter tombstones — communicating the
    /// intended delete is the entire point of the feature.
    func testReadsStillReturnTombstonedNodes() throws {
        let (scopeUuid, domain) = try overlayScopeAndDomain()
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version, soft: true))
        let tree = try store.dbQueue.read { db -> DopeScopeTree in
            let scope = try self.store.fetchDopeScope(db, uuid: scopeUuid)!
            return try self.store.fetchDopeTree(db, scope: scope)
        }
        XCTAssertEqual(tree.domains.count, 1)
        XCTAssertNotNil(tree.domains[0].identity.deletedOn,
                        "the tombstone must be visible to readers")
    }

    /// A tombstone is still a row, so every RESTRICT FK pointing at it still
    /// resolves — which is why soft delete skips the referrer guard that a
    /// hard delete must run.
    func testSoftDeleteSkipsTheReferrerGuardAHardDeleteWouldTrip() throws {
        let (scopeUuid, domain) = try overlayScopeAndDomain()
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        let en = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .enumeration, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "status", name: "Status")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "st", name: "St", dataType: .enumeration,
                                   enumUuid: en.uuid)))
        // Hard delete of the still-referenced enum is refused...
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: en.uuid, expectedVersion: en.version)))
        // ...but tombstoning it is legal: the row, and therefore the FK, stays.
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .enumeration, nodeUuid: en.uuid,
            expectedVersion: en.version, soft: true))
        try store.dbQueue.read { db in
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        _ = scopeUuid
    }

    /// THE critical property, and the one that was wrong first time round:
    /// a tombstone must NOT appear in the document projection at all. The
    /// saved format is real state; a masked-away node is not real state.
    func testTombstoneNeverReachesTheDocumentProjection() throws {
        let (scopeUuid, domain) = try overlayScopeAndDomain()
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version, soft: true))

        let (tree, bundle) = try store.dbQueue.read { db -> (DopeScopeTree, DopeDocumentBundle) in
            let scope = try self.store.fetchDopeScope(db, uuid: scopeUuid)!
            let tree = try self.store.fetchDopeTree(db, scope: scope)
            return (tree, DopeProjection.documents(from: tree))
        }
        // The WIRE tree knows (that is how the resolver applies the whiteout)...
        XCTAssertNotNil(tree.domains[0].identity.deletedOn)
        // ...but nothing in the saved bundle mentions it.
        let json = String(
            data: try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0]), encoding: .utf8)!
        XCTAssertFalse(json.contains("deleted_on"),
                       "the saved format must record real state only")
        let mainJson = String(
            data: try DopeDocumentCodec.encoder.encode(bundle.main), encoding: .utf8)!
        XCTAssertFalse(mainJson.contains("deleted_on"))
    }

    /// A base scope records what exists. Tombstoning inside one would write a
    /// value that describes nothing real, so it is refused.
    func testSoftDeleteIsRefusedInABaseScope() throws {
        let base = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: nil, code: "base", name: "Base")).scope
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: base.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        XCTAssertThrowsError(try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid,
            expectedVersion: domain.version, soft: true)))
        // The hard delete remains available there.
        _ = try store.dopeNodeDelete(DopeNodeDeleteRequest(
            level: .persistence, nodeUuid: domain.uuid, expectedVersion: domain.version))
    }

    /// An untombstoned tree encodes byte-identically to before m0012, so a
    /// no-op `write-repo` leaves `git status` clean.
    func testUntombstonedTreeEmitsNoNewKeys() throws {
        let (scopeUuid, _) = try overlayScopeAndDomain()
        let bundle = try store.dbQueue.read { db -> DopeDocumentBundle in
            let scope = try self.store.fetchDopeScope(db, uuid: scopeUuid)!
            return DopeProjection.documents(from: try self.store.fetchDopeTree(db, scope: scope))
        }
        let json = String(
            data: try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0]), encoding: .utf8)!
        XCTAssertFalse(json.contains("deleted_on"), "nil tombstone must not serialize")
    }
}
