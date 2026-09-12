import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The adopt gate (dope boot sync's store half): virgin seed, forward gap,
/// backward refusal, strict-contract preservation, and the files-never-
/// written invariant. Same temp-checkout scaffolding as DopeRepoVerbTests,
/// plus a SECOND session on the same instance so a virgin scope can face a
/// populated on-disk tree the way a fresh branch checkout does.
final class DopeBootSyncTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true)
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-boot-\(UUID().uuidString).db").path
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
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1',
                        '\(repoRoot.path)', 'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-2")), 'inst-1', 'feature', 'feature', '', '', 'active', 'y');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(at: repoRoot)
    }

    /// Build a real tree in sess-1's scope and project it to the repo files.
    /// Returns the on-disk version.
    @discardableResult
    private func writeRepoTree() throws -> Int64 {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .uuid,
                                   nullable: false, isUnique: true)))
        let written = try store.dopeWriteRepo(DopeWriteRepoRequest(
            scopeUuid: scope.uuid))
        return written.revision
    }

    private func mainFileBytes() throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent(
            ".gmcc/\(DopeDocumentCodec.scopeFileName)"))
    }

    /// Rewrite the on-disk bundle at a new version (content unchanged).
    private func bumpFiles(to version: Int64) throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let bumped = DopeDocumentBundle(
            main: DopeScopeDocument(version: version, scope: read.main.scope,
                                    persistence: read.main.persistence,
                                    cogs: read.main.cogs),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: version, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            })
        _ = try sandbox.writeAtomically(bumped)
    }

    // MARK: - virgin seed (the fresh-branch case)

    func testVirginScopeSeedsWithAdoptAndRefusesStrict() throws {
        let disk = try writeRepoTree()  // sess-1's tree at revision 4
        XCTAssertGreaterThan(disk, 1)

        // sess-2 = the fresh branch: same instance, virgin scope at 0.
        let virgin = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-2", code: "gmcc", name: "GMCC")).scope
        XCTAssertEqual(virgin.revision, 0)

        // Strict gate is unsatisfiable by construction (0 != disk - 1).
        XCTAssertThrowsError(try store.dopeIngest(
            DopeIngestRequest(scopeUuid: virgin.uuid))) { error in
            guard case StoreError.revisionConflict = error else {
                return XCTFail("expected revisionConflict, got \(error)")
            }
        }

        let before = try mainFileBytes()
        let seeded = try store.dopeIngest(DopeIngestRequest(
            scopeUuid: virgin.uuid, adopt: true))
        XCTAssertEqual(seeded.scope.revision, disk)
        XCTAssertEqual(seeded.previousRevision, 0)
        XCTAssertEqual(seeded.counts.entities, 1)
        // Direction is strictly files -> db.
        XCTAssertEqual(try mainFileBytes(), before)
    }

    // MARK: - forward gap (the returning-branch case)

    func testForwardGapAdoptsAndReportsGap() throws {
        let disk = try writeRepoTree()
        let virgin = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-2", code: "gmcc", name: "GMCC")).scope
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true))

        // Files leap ahead by more than one (another branch's edits landed).
        try bumpFiles(to: disk + 5)

        XCTAssertThrowsError(try store.dopeIngest(
            DopeIngestRequest(scopeUuid: virgin.uuid))) { error in
            guard case StoreError.revisionConflict = error else {
                return XCTFail("expected revisionConflict, got \(error)")
            }
        }
        let adopted = try store.dopeIngest(DopeIngestRequest(
            scopeUuid: virgin.uuid, adopt: true))
        XCTAssertEqual(adopted.scope.revision, disk + 5)
        XCTAssertEqual(adopted.previousRevision, disk)
        XCTAssertEqual(adopted.gapCrossed, 4)
    }

    // MARK: - monotonicity (never backward)

    func testAdoptRefusesBackwardAndWritesNothing() throws {
        let disk = try writeRepoTree()
        let virgin = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-2", code: "gmcc", name: "GMCC")).scope
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true))

        // Stale checkout: files go BEHIND the db.
        try bumpFiles(to: disk - 1)
        let before = try mainFileBytes()

        XCTAssertThrowsError(try store.dopeIngest(
            DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true))) { error in
            guard case StoreError.badRequest = error else {
                return XCTFail("expected badRequest, got \(error)")
            }
        }
        XCTAssertEqual(try mainFileBytes(), before)
        let scopeAfter = try store.dbQueue.read { db in
            try self.store.fetchDopeScope(db, uuid: virgin.uuid)!
        }
        XCTAssertEqual(scopeAfter.revision, disk)

        // Same-version adopt is also refused (nothing to take).
        try bumpFiles(to: disk)
        XCTAssertThrowsError(try store.dopeIngest(
            DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true)))
    }

    // MARK: - strict contract untouched

    func testStrictPlusOneStillWorksWithoutAdopt() throws {
        let disk = try writeRepoTree()
        let virgin = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-2", code: "gmcc", name: "GMCC")).scope
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true))

        try bumpFiles(to: disk + 1)
        let strict = try store.dopeIngest(DopeIngestRequest(scopeUuid: virgin.uuid))
        XCTAssertEqual(strict.scope.revision, disk + 1)
        XCTAssertNil(strict.gapCrossed)
    }

    // MARK: - event honesty

    func testAdoptEventsRecordSeedAndAdoptActions() throws {
        _ = try writeRepoTree()
        let virgin = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-2", code: "gmcc", name: "GMCC")).scope
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: virgin.uuid, adopt: true))

        let payloads = try store.dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT payload FROM daemon_event WHERE kind = 'DOPE_CHANGE'
                 AND subject_uuid = ? ORDER BY id
                """, arguments: [virgin.uuid])
        }
        XCTAssertTrue(payloads.contains { $0.contains("\"boot_seed\"") },
                      "seed adopt should record action boot_seed; payloads=\(payloads)")
    }
}
