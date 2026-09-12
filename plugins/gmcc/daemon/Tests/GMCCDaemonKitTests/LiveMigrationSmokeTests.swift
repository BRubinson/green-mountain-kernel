import GRDB
import XCTest
@testable import GMCCDaemonKit

/// Runs the real migrator against a COPY of the production database when one
/// is present. Guards the migrations that move data (m0012's five-table
/// rebuild) against the only dataset that actually matters. Silently skips
/// when the copy is absent, so CI on a clean machine stays green.
final class LiveMigrationSmokeTests: XCTestCase {
    func testMigratesACopyOfTheLiveDatabaseWithoutLosingRows() throws {
        let copy = ProcessInfo.processInfo.environment["GMCC_LIVE_DB_COPY"]
        try XCTSkipIf(copy == nil, "set GMCC_LIVE_DB_COPY to exercise this")
        let path = copy!
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path))

        let store = try Store(path: path)
        // The copy may be pre- or post-rename depending on when it was taken:
        // once the live db has been migrated, the dope_domain* tables are gone.
        // Compare against whichever vocabulary the copy actually has.
        let preRename = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'table' AND name = 'dope_domain'
                """) == 1
        }
        let sourceTables = preRename
            ? ["dope_domain", "dope_domain_entity", "dope_domain_enum",
               "dope_domain_enum_option", "dope_domain_entity_property"]
            : ["dope_persistence", "dope_persistence_entity", "dope_persistence_enum",
               "dope_persistence_enum_option", "dope_persistence_entity_property"]
        let scopesBefore = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1
        }
        let before = try store.dbQueue.read { db in
            try [
            ].map { _ in 0 }
        }
        let beforeCounts = try store.dbQueue.read { db in
            try sourceTables.map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        _ = before
        try store.migrate()
        XCTAssertEqual(try store.schemaVersion(), Migrations.currentSchemaVersion)

        let after = try store.dbQueue.read { db in
            try [
                "dope_persistence", "dope_persistence_entity", "dope_persistence_enum",
                "dope_persistence_enum_option", "dope_persistence_entity_property",
            ].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        XCTAssertEqual(beforeCounts, after, "the rename lost or duplicated rows")
        XCTAssertEqual(
            try store.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dope_scope") ?? -1
            }, scopesBefore, "m0013 lost or duplicated scope rows")

        try store.dbQueue.read { db in
            // The whole db still passes an FK sweep after the rebuild.
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            // Every project backfilled to a real branch (m0011).
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM project
                    WHERE primary_project_branch IS NULL OR primary_project_branch = ''
                    """), 0)
            // Refs survived the rebuild rather than being NULLed.
            XCTAssertGreaterThan(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM dope_persistence_entity_property
                    WHERE base_origin_property_uuid IS NOT NULL
                    """) ?? 0, 0)
            // m0013: every scope carries a resolvable project, the two legacy
            // scope types became the session tiers, and no row was dropped by
            // the lineage join.
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM dope_scope WHERE project_uuid IS NULL
                    """), 0)
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM dope_scope
                    WHERE scope_type NOT IN ('BASE_PROJECT', 'PROJECT_ITEM',
                                             'SESSION_INSTANCE', 'SESSION_INSTANCE_ITEM')
                    """), 0)
            // m0017: the relationship target is renamed and mask_kind is gone.
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM pragma_table_info('dope_persistence_entity_property')
                     WHERE name = 'relationship_target_uuid'
                    """), 1)
            for table in ["dope_persistence", "dope_persistence_entity",
                          "dope_persistence_entity_property", "dope_cog_element"] {
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM pragma_table_info('\(table)')
                         WHERE name = 'mask_kind'
                        """), 0, "mask_kind survived on \(table)")
            }
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM dope_scope ds JOIN session s ON s.uuid = ds.session_uuid
                    JOIN instance i ON i.uuid = s.instance_uuid
                    WHERE ds.project_uuid != i.project_uuid
                       OR ds.instance_uuid != s.instance_uuid
                    """), 0, "m0013 backfilled a wrong lineage")
        }
    }
}
