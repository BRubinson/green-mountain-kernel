import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0011 — project.primary_project_branch (the prompt's
    // BASE_DOPED_BRANCH). The user-configured branch whose
    // SESSION_INSTANCE dope scope is allowed to promote into the
    // project's BASE_PROJECT scope.
    //
    // Plain ADD COLUMN, m0009's precedent: NOT NULL with a CONSTANT
    // DEFAULT and no CHECK and no REFERENCES — the shape SQLite's
    // ALTER TABLE ADD COLUMN accepts without a table rebuild. Every
    // existing project backfills to 'main', which is the documented
    // default behavior ("this starts as main by default").
    //
    // Sequenced FIRST among this prompt's migrations deliberately: it is
    // the only trivially-reversible one, so it lands as a green commit
    // between the SessionStart script rename and the two table rebuilds
    // that follow, and DopePromotion's branch-match predicate has its
    // column long before the promotion machinery exists to read it.
    static func m0011_projectPrimaryBranch(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0011_projectPrimaryBranch") { db in
            try db.execute(
                sql: """
                    ALTER TABLE project
                        ADD COLUMN primary_project_branch TEXT NOT NULL DEFAULT 'main';
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [11, Store.isoNow()]
            )
        }
    }
}
