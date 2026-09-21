import Foundation
import GRDB

extension Migrations {
    // m0020 — the merge base for per-element dope reconciliation. At a session,
    // branch or merge boundary the rule is per-element: files win for anything
    // this session never touched, and an element edited here that also moved on
    // disk is a conflict. A three-way merge needs a base; this table is it.
    // KEYED BY DOT-PATH, NEVER BY UUID — dopeIngest is a whole-tree wipe and
    // reinsert that re-mints every child uuid, so a uuid-keyed provenance row
    // would be destroyed by the very operation it exists to inform.
    static func m0020_dopeElementProvenance(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0020_dopeElementProvenance") { db in
            try db.execute(
                sql: """
                    CREATE TABLE dope_element_provenance (
                        \(baseColumns),
                        dope_scope_uuid TEXT NOT NULL
                            REFERENCES dope_scope(uuid) ON DELETE CASCADE,
                        dot_path TEXT NOT NULL,
                        element_kind TEXT NOT NULL,
                        -- Content hash at the last files -> db sync. NULL means
                        -- "this element has never been synced from a file", which
                        -- is different from "synced and unchanged".
                        synced_content_hash TEXT,
                        -- Set by every granular dope mutation, cleared on sync.
                        locally_modified INTEGER NOT NULL DEFAULT 0
                            CHECK (locally_modified IN (0, 1)),
                        UNIQUE(dope_scope_uuid, dot_path)
                    );

                    CREATE INDEX idx_dope_element_provenance_scope_fk
                        ON dope_element_provenance(dope_scope_uuid);
                    CREATE INDEX idx_dope_element_provenance_dirty
                        ON dope_element_provenance(dope_scope_uuid, locally_modified)
                        WHERE locally_modified = 1;
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [20, Store.isoNow()]
            )
        }
    }
}
