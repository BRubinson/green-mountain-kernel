import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0022 — prompt_qualified_diagram: what a prompt UNDERSTOOD when it
    // read a rendered diagram.
    //
    // Deliberately NOT modelled on the clarify/arch/explore/review
    // families. Those carry a status machine, findings rows and an FTS
    // mirror because a report is BUILT across many turns and needs to say
    // when it became trustworthy. This surface holds one sentence's worth
    // of standing fact — this prompt looked at this diagram at this
    // revision, and here is what it means — so a machine around it would
    // be ceremony, not safety. The restraint is the design.
    //
    // Nor is it a prompt_artifact row with a new kind: an artifact is a
    // POINTER whose content stays in a file, and the qualification is
    // content the db owns.
    //
    // rendered_revision and render_fingerprint are what make a stale
    // qualification detectable at all. The fingerprint is the same
    // serialized DiagramRenderFingerprint the renderer drops beside the
    // PNG, so a reader compares against a current render without
    // re-deriving anything — and it has to be the fingerprint rather than
    // the revision alone, because a bound dope tree moves under the
    // picture without ever touching diagram.revision.
    static func m0022_promptQualifiedDiagram(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0022_promptQualifiedDiagram") { db in
            try db.execute(
                sql: """
                    CREATE TABLE prompt_qualified_diagram (
                        \(baseColumns),
                        prompt_uuid TEXT NOT NULL REFERENCES prompt(uuid) ON DELETE CASCADE,
                        diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                        rendered_path TEXT NOT NULL,
                        rendered_revision INTEGER NOT NULL,
                        render_fingerprint TEXT NOT NULL,
                        qualification TEXT NOT NULL,
                        -- One row per pair: re-qualifying UPSERTS, so a prompt's
                        -- reading of a diagram is always its CURRENT reading and
                        -- never a pile of drafts a reader has to disambiguate.
                        UNIQUE(prompt_uuid, diagram_uuid)
                    );

                    CREATE INDEX idx_prompt_qualified_diagram_prompt_fk
                        ON prompt_qualified_diagram(prompt_uuid);
                    CREATE INDEX idx_prompt_qualified_diagram_diagram_fk
                        ON prompt_qualified_diagram(diagram_uuid);
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [22, Store.isoNow()]
            )
        }
    }
}
