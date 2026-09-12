import CryptoKit
import GRDB
import XCTest

@testable import GmDaemon
import GmDaemonSdk

final class SandboxRetargetTests: XCTestCase {

    private var dbPath: String!
    private let oldRepo = "/Users/dev/green-mountain-kernel"
    private let newRepo = "/Users/dev/gmfs/development/local_sandbox/repo/green-mountain-kernel"

    private var oldCode: String {
        InstanceIdentity.code(repoName: "green-mountain-kernel", absolutePath: oldRepo)
    }
    private var newCode: String {
        InstanceIdentity.code(repoName: "green-mountain-kernel", absolutePath: newRepo)
    }

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-retarget-\(UUID().uuidString).db").path
        let store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, gmfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'green-mountain-kernel', 'green-mountain-kernel',
                        'green-mountain-kernel', 'projects/green-mountain-kernel');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, gmfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', '\(oldCode)', '\(oldCode)', '\(oldRepo)',
                        'projects/green-mountain-kernel/instances/\(oldCode)');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, gmfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/green-mountain-kernel/instances/\(oldCode)/sessions/main');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command,
                    status, gmfs_relative_storage_path)
                VALUES (\(base("prompt-1")), 'sess-1', 1, 'p1', 'p1', '', '', '', '',
                        'draft',
                        'projects/green-mountain-kernel/instances/\(oldCode)/sessions/main/prompts/1_p1');
                """)
        }
        try? store.closeDatabase()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func retarget() throws -> SandboxRetarget.Result {
        try SandboxRetarget.run(
            dbPath: dbPath,
            oldRepoPath: oldRepo,
            newRepoPath: newRepo,
            gmFsRoot: "/sandbox/gmfs",
            kbiteRoot: "/sandbox/gmfs/kbites",
            kbiteOpenRoot: "/sandbox/gmfs/kbites/open",
            kbiteDigestedRoot: "/sandbox/gmfs/kbites/digested")
    }

    func testRefusesProdDb() throws {
        XCTAssertThrowsError(
            try SandboxRetarget.run(
                dbPath: SandboxRetarget.prodDbPath,
                oldRepoPath: oldRepo, newRepoPath: newRepo,
                gmFsRoot: "x", kbiteRoot: "x", kbiteOpenRoot: "x", kbiteDigestedRoot: "x")
        ) { error in
            guard case SandboxRetarget.RetargetError.refusedProdDb = error else {
                return XCTFail("expected refusedProdDb, got \(error)")
            }
        }
    }

    func testRewritesConfigInstanceAndStoragePaths() throws {
        let result = try retarget()
        XCTAssertEqual(result.oldInstanceCode, oldCode)
        XCTAssertEqual(result.newInstanceCode, newCode)

        let queue = try DatabaseQueue(path: dbPath)
        try queue.read { db in
            // Config rows re-pointed.
            let gmfs = try String.fetchOne(
                db, sql: "SELECT config_value FROM daemon_config WHERE config_key = 'gmfs_root'")
            XCTAssertEqual(gmfs, "/sandbox/gmfs")
            let digested = try String.fetchOne(
                db,
                sql: "SELECT config_value FROM daemon_config WHERE config_key = 'kbite_digested_root'")
            XCTAssertEqual(digested, "/sandbox/gmfs/kbites/digested")

            // Instance identity rehomed (end-of-path storage form included).
            let inst = try Row.fetchOne(db, sql: "SELECT * FROM instance WHERE uuid = 'inst-1'")!
            XCTAssertEqual(inst["code"] as String, self.newCode)
            XCTAssertEqual(inst["absolute_file_system_path"] as String, self.newRepo)
            XCTAssertEqual(
                inst["gmfs_relative_storage_path"] as String,
                "projects/green-mountain-kernel/instances/\(self.newCode)")

            // Mid-path rewrites across dependent tables.
            let session = try String.fetchOne(
                db, sql: "SELECT gmfs_relative_storage_path FROM session WHERE uuid = 'sess-1'")
            XCTAssertEqual(
                session,
                "projects/green-mountain-kernel/instances/\(self.newCode)/sessions/main")
            let stale = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM prompt
                WHERE gmfs_relative_storage_path LIKE '%instances/\(self.oldCode)%'
                """)
            XCTAssertEqual(stale, 0)
        }
    }

    func testRetargetIsIdempotentOnRerun() throws {
        _ = try retarget()
        // A second run against the SAME staged db must fail cleanly on the
        // instance lookup (old path no longer present) rather than corrupt —
        // the pipeline always re-stages from a fresh backup before retarget.
        XCTAssertThrowsError(try retarget()) { error in
            guard case SandboxRetarget.RetargetError.instanceNotFound = error else {
                return XCTFail("expected instanceNotFound, got \(error)")
            }
        }
    }

    /// DRIFT GUARD: runtime schema discovery must cover every table the
    /// migrations declare with a gmfs_relative_storage_path column. If a
    /// future migration adds a path-bearing table under a DIFFERENT column
    /// name, extend SandboxRetarget and this expectation together.
    func testStoragePathDiscoveryCoversKnownTables() throws {
        let queue = try DatabaseQueue(path: dbPath)
        let tables = try queue.read { try SandboxRetarget.storagePathTables($0) }
        for expected in ["project", "instance", "session", "prompt"] {
            XCTAssertTrue(tables.contains(expected), "discovery missed \(expected)")
        }
        // And discovery must agree with a raw schema scan of the same db.
        let rawCount = try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM sqlite_master
                WHERE type = 'table' AND sql LIKE '%gmfs_relative_storage_path%'
                  AND sql NOT LIKE 'CREATE VIRTUAL%' AND name NOT LIKE '%_fts%'
                """)!
        }
        XCTAssertEqual(tables.count, rawCount, "discovery and raw schema scan disagree")
    }

    func testInstanceIdentityMatchesDetectRepoHash4() throws {
        // gmcc_session_startup.sh: md5 -q -s "<abs path>" | cut -c1-4 appended to repo name.
        let hex = Insecure.MD5.hash(data: Data("/tmp/repo".utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            InstanceIdentity.code(repoName: "repo", absolutePath: "/tmp/repo"),
            "repo_\(hex.prefix(4))")
    }
}
