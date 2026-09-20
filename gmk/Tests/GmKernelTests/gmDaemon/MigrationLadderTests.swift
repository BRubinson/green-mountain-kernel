import Foundation
import GRDB
import GmDaemon
import GmDaemonSdk
import XCTest

/// The migration ladder — the one family that CANNOT use the shared environment.
///
/// A migration assertion needs a database built at an OLD schema and stepped
/// forward, while the shared environment holds one database already at head, so
/// these would pass vacuously against it. The ladder runs against an IN-MEMORY
/// `DatabaseQueue` needing no root, no daemon and no filesystem. Opening that
/// database is the ONE exemption from this package's read-only rule, safe only
/// because there is no kernel, no `flock` and no file to be a second writer to.
final class MigrationLadderTests: XCTestCase {

    /// An empty database climbs to head, and the ledger ROW is written.
    ///
    /// Asserting the ledger rather than the constant is deliberate: writing the
    /// `schema_migrations` row is the step a migration can forget, and a
    /// migration that forgot it would pass a `currentSchemaVersion` check.
    func testAnEmptyDatabaseClimbsToHead() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)
        let head = try queue.read {
            try Int.fetchOne($0, sql: "SELECT MAX(version) FROM schema_migrations")
        }
        XCTAssertEqual(head, Migrations.currentSchemaVersion)
    }

    /// Stepping to an intermediate rung leaves the db THERE, not at head.
    ///
    /// This is the capability the whole family rests on — without it there is no
    /// way to build an "old" database to migrate forward from, and every
    /// migration test becomes the empty-database case that always passes.
    func testTheLadderCanStopPartWay() throws {
        let queue = try DatabaseQueue()
        // The FIRST rung, named exactly. GRDB traps on an unknown migration id
        // rather than returning an error, so a typo here is a crash, not a red
        // test — which is why this names m0001 (frozen by contract) rather than
        // a middle rung somebody might later rename.
        try Migrations.migrator.migrate(queue, upTo: "m0001_baseSchema")
        let head = try queue.read {
            try Int.fetchOne($0, sql: "SELECT MAX(version) FROM schema_migrations")
        }
        XCTAssertNotNil(head)
        XCTAssertLessThan(
            head ?? .max,
            Migrations.currentSchemaVersion,
            "upTo: must stop the ladder; if it climbs to head the family is vacuous"
        )
    }

    /// m0029's two tables exist at head, with the constraint that IS the feature.
    ///
    /// `UNIQUE(project_uuid)` on the claim cell is the "one entity per project"
    /// rule expressed in the schema. Asserting it here rather than trusting the
    /// migration text is the point: an inline UNIQUE cannot be dropped without a
    /// twelve-step table rebuild, so its presence is worth a test that fails
    /// loudly if someone rebuilds the table and forgets it.
    func testM0029LandsTheLockTablesWithTheirUniqueness() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)

        try queue.read { db in
            let tables = try Set(
                String.fetchAll(
                    db,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            )
            XCTAssertTrue(tables.contains("test_run"))
            XCTAssertTrue(tables.contains("project_test_lock"))

            // The autoindex SQLite creates to back an inline UNIQUE. Its
            // presence is the constraint's fingerprint.
            let autoindexes = try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT name FROM sqlite_master
                         WHERE type = 'index' AND tbl_name = 'project_test_lock'
                           AND name LIKE 'sqlite_autoindex%'
                        """
                )
            )
            XCTAssertFalse(
                autoindexes.isEmpty,
                "project_test_lock lost its inline UNIQUE — a lock table without "
                    + "uniqueness is not a lock"
            )

            // No CHECK constraints on the enum columns: post-m0021 the
            // vocabulary lives in Swift, because an inline CHECK costs a
            // twelve-step rebuild the first time an arm is added.
            let ddl =
                try String.fetchOne(
                    db,
                    sql: """
                        SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'test_run'
                        """
                ) ?? ""
            XCTAssertFalse(
                ddl.uppercased().contains("CHECK"),
                "test_run must carry no CHECK — states live in TestRunState"
            )
        }
    }

    /// The ledger is APPEND-ONLY and climbs monotonically: every rung from 1 to
    /// head is present exactly once.
    ///
    /// A gap means a migration did not record itself; a duplicate means one ran
    /// twice. Both are silent on a working database and catastrophic on a
    /// migrated one.
    func testTheLedgerIsDenseAndUnique() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)
        let versions = try queue.read {
            try Int.fetchAll($0, sql: "SELECT version FROM schema_migrations ORDER BY version")
        }
        XCTAssertEqual(
            versions,
            Array(1...Migrations.currentSchemaVersion),
            "the ledger must be dense and duplicate-free from 1 to head"
        )
    }
}
