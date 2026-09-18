import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0006 — un-backfill the draft prompts m0005 overreached on.
    //
    // m0005 gave a placeholder clarification + architecture summary to
    // EVERY prompt missing one, so that SUMMARY_ABSENT could never again
    // mean "this prompt is legacy, go read a file". For a prompt that has
    // moved through the lifecycle that is right. For one still at `draft`
    // it is not: the placeholders land at terminal status (complete /
    // approved), and CLARIFY_ASK only accepts rows while the summary is
    // `building` — with no edge back to `building` from either later
    // state. A draft prompt would therefore be unable to author its own
    // clarification, which is precisely the work it exists to do.
    //
    // Deleting them restores the correct meaning for that population:
    // SUMMARY_ABSENT on a draft prompt means "not opened yet — open one",
    // which is the ordinary non-legacy case and needs no fork. Only rows
    // m0005 itself wrote are touched (matched on its backstory_note
    // marker), and only while the prompt is still `draft`, so nothing a
    // bot authored can be caught by this. The FTS mirrors stay synced
    // through the live `_ad` delete triggers.
    //
    // Landed as its own migration rather than a fix to m0005's body: the
    // migrator keys on the migration id and silently skips a changed body
    // on a db that already ran it, so an edit would leave already-migrated
    // databases diverged from fresh ones forever.
    static func m0006_dropDraftPlaceholderSummaries(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0006_dropDraftPlaceholderSummaries") { db in
            let marker = "Backfilled by m0005; not authored by a bot run."
            try db.execute(
                sql: """
                    DELETE FROM clarification_summary
                     WHERE backstory_note = ?
                       AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                    """, arguments: [marker])
            // The architecture placeholder carries no note column, so it is
            // identified by the body m0005 wrote plus the same draft filter.
            try db.execute(
                sql: """
                    DELETE FROM architecture_summary
                     WHERE body LIKE 'm0005 placeholder.%'
                       AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                    """)
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [6, Store.isoNow()]
            )
        }
    }
}
