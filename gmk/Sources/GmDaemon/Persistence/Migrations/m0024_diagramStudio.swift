import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0024 — Diagram Studio: the visibility axis, the first diagram FTS mirror,
    // the uml_node subtype, and connector routing/tail vocabulary.
    // visibility is an axis, not a tier: PRIVATE is db-only, PUBLIC is
    // repo-serializable and legal ONLY on SESSION-tier rows, guarded in Swift
    // because the rule crosses tables. ONE diagram_uml_node table for every node
    // kind: six would make reshape a delete+recreate, ghosting every incoming
    // connector. The diagram_fts update trigger fires AFTER UPDATE OF code, name,
    // description only — revision bumps on every stroke would churn the index.
    static func m0024_diagramStudio(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0024_diagramStudio") { db in
            try db.execute(
                sql: """
                    ALTER TABLE diagram ADD COLUMN visibility TEXT NOT NULL DEFAULT 'PRIVATE';
                    CREATE INDEX idx_diagram_visibility ON diagram(visibility);

                    ALTER TABLE diagram_connector ADD COLUMN routing_kind TEXT NOT NULL DEFAULT 'orthogonal_step';
                    ALTER TABLE diagram_connector ADD COLUMN tail_kind TEXT NOT NULL DEFAULT 'none';
                    """
            )

            try db.execute(
                sql: """
                    CREATE TABLE diagram_uml_node (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        node_kind TEXT NOT NULL,
                        width REAL NOT NULL CHECK (width > 0),
                        height REAL NOT NULL CHECK (height > 0),
                        markdown TEXT NOT NULL DEFAULT '',
                        font_size REAL CHECK (font_size IS NULL OR font_size > 0),
                        text_color TEXT,
                        stroke_color TEXT,
                        stroke_width REAL CHECK (stroke_width IS NULL OR stroke_width > 0),
                        fill_color TEXT
                    );

                    CREATE INDEX idx_diagram_uml_node_element_fk
                        ON diagram_uml_node(element_uuid);
                    """
            )

            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE diagram_fts USING fts5(
                        code, name, description,
                        content='diagram', content_rowid='id'
                    );

                    CREATE TRIGGER diagram_ai AFTER INSERT ON diagram BEGIN
                        INSERT INTO diagram_fts(rowid, code, name, description)
                        VALUES (new.id, new.code, new.name, new.description);
                    END;
                    CREATE TRIGGER diagram_ad AFTER DELETE ON diagram BEGIN
                        INSERT INTO diagram_fts(diagram_fts, rowid, code, name, description)
                        VALUES ('delete', old.id, old.code, old.name, old.description);
                    END;
                    CREATE TRIGGER diagram_au AFTER UPDATE OF code, name, description ON diagram BEGIN
                        INSERT INTO diagram_fts(diagram_fts, rowid, code, name, description)
                        VALUES ('delete', old.id, old.code, old.name, old.description);
                        INSERT INTO diagram_fts(rowid, code, name, description)
                        VALUES (new.id, new.code, new.name, new.description);
                    END;

                    INSERT INTO diagram_fts(diagram_fts) VALUES ('rebuild');
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [24, Store.isoNow()]
            )
        }
    }
}
