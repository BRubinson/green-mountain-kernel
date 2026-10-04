import Foundation
import GRDB

extension Migrations {
    // m0006 — drop the placeholder clarification + architecture summaries
    // m0005 gave to `draft` prompts. Those placeholders land at terminal status
    // and CLARIFY_ASK only accepts rows while the summary is `building`, with no
    // edge back, so a draft prompt could not author its own clarification.
    // Only rows carrying m0005's backstory_note marker are touched, and only
    // while the prompt is still `draft`. Its own migration rather than a fix to
    // m0005's body: the migrator silently skips a changed body on a db that
    // already ran it.
    /// Registers the m0006 migration: drops placeholder summaries from draft prompts.
    ///
    /// - Parameter migrator: The database migrator to register this migration with.
    static func m0006_dropDraftPlaceholderSummaries(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0006_dropDraftPlaceholderSummaries") { db in
            let marker = "Backfilled by m0005; not authored by a bot run."
            try db.execute(
                sql: """
                    DELETE FROM clarification_summary
                     WHERE backstory_note = ?
                       AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                    """,
                arguments: [marker]
            )
            // The architecture placeholder carries no note column, so it is
            // identified by the body m0005 wrote plus the same draft filter.
            try db.execute(
                sql: """
                    DELETE FROM architecture_summary
                     WHERE body LIKE 'm0005 placeholder.%'
                       AND prompt_uuid IN (SELECT uuid FROM prompt WHERE status = 'draft')
                    """
            )
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [6, Store.isoNow()]
            )
        }
    }
}
