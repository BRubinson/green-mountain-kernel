import Foundation
import GRDB

extension Migrations {
    // m0022 — prompt_qualified_diagram: what a prompt understood when it read a
    // rendered diagram. Deliberately not shaped like the report families — it
    // holds one standing fact, not a report built across turns, so no status
    // machine, no findings children, no FTS mirror. Not a prompt_artifact either:
    // an artifact is a POINTER to file content, and this content the db owns.
    // render_fingerprint, not revision alone, is what makes a stale qualification
    // detectable: a bound dope tree moves under the picture without ever touching
    // diagram.revision.
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
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [22, Store.isoNow()]
            )
        }
    }
}
