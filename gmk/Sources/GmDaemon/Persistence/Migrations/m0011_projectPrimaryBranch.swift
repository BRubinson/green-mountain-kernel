import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0011 — project.primary_project_branch: the branch whose SESSION_INSTANCE
    // dope scope may promote into the project's BASE_PROJECT scope.
    // Plain ADD COLUMN, NOT NULL with a CONSTANT DEFAULT and no CHECK and no
    // REFERENCES — the shape SQLite accepts without a table rebuild. Existing
    // projects backfill to 'main'.
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
