import XCTest
@testable import GMCCDaemonKit

/// m0011 + PROJECT_UPDATE: the project's primary_project_branch
/// (BASE_DOPED_BRANCH), the first project-level mutation in the CLI.
final class ProjectUpdateTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-update-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (NULL, 'proj-1', 0, '\(now)', '\(now)',
                        'repo', 'repo', 'repo', 'projects/repo');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    /// m0011 backfills every pre-existing project rather than leaving NULL —
    /// the promotion predicate must never compare against a missing branch.
    func testMigrationBackfillsMainAsTheDefaultBranch() throws {
        let projects = try store.listProjects().projects
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].primaryProjectBranch, "main")
    }

    func testUpdateSetsBranchAndBumpsVersion() throws {
        let row = try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 0,
            primaryProjectBranch: "develop"))
        XCTAssertEqual(row.primaryProjectBranch, "develop")
        XCTAssertEqual(row.version, 1)
        XCTAssertEqual(try store.listProjects().projects[0].primaryProjectBranch,
                       "develop")
    }

    func testUpdateIsOptimisticallyLocked() throws {
        XCTAssertThrowsError(try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 99,
            primaryProjectBranch: "develop")))
    }

    func testUnknownProjectIsNotFound() throws {
        XCTAssertThrowsError(try store.updateProject(ProjectUpdateRequest(
            projectUuid: "nope", expectedVersion: 0,
            primaryProjectBranch: "develop")))
    }

    /// An all-nil request is EMPTY_UPDATE, never a silent no-op that still
    /// bumps the version.
    func testEmptyUpdateIsRefused() throws {
        XCTAssertThrowsError(try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 0)))
    }

    /// A branch name is an identity, not prose: a blank value would be a
    /// branch the promotion predicate could never match.
    func testBlankBranchIsRefusedAndWhitespaceIsTrimmed() throws {
        XCTAssertThrowsError(try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 0,
            primaryProjectBranch: "   ")))
        let row = try store.updateProject(ProjectUpdateRequest(
            projectUuid: "proj-1", expectedVersion: 0,
            primaryProjectBranch: "  release/1.0  "))
        XCTAssertEqual(row.primaryProjectBranch, "release/1.0")
    }

    /// The additive-OPTIONAL wire convention: a pre-m0011 peer omits the key
    /// entirely and must still decode, defaulting to "main".
    func testProjectRowDecodesWithoutTheNewKey() throws {
        let legacy = """
            {"uuid":"p","version":0,"git_repo_name":"r","code":"r","name":"r",
             "ckfs_relative_storage_path":"projects/r",
             "created_at":"t","updated_at":"t"}
            """.data(using: .utf8)!
        let row = try WireCodec.decoder.decode(ProjectRow.self, from: legacy)
        XCTAssertEqual(row.primaryProjectBranch, "main")
    }
}
