import Foundation
import GRDB

extension Migrations {
    /// Adds the project primary branch column to the database.
    ///
    /// Adds the `primary_project_branch` column to the project table, which
    /// identifies the branch whose SESSION_INSTANCE dope scope may promote
    /// into the project's BASE_PROJECT scope. Existing projects backfill to
    /// 'main'.
    ///
    /// - Parameter migrator: The database migrator to register this migration.
    static func m0011_projectPrimaryBranch(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0011_projectPrimaryBranch") { db in
            try db.execute(
                sql: """
                    ALTER TABLE project
                        ADD COLUMN primary_project_branch TEXT NOT NULL DEFAULT 'main';
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [11, Store.isoNow()]
            )
        }
    }
}
