import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0024 — Diagram Studio: the visibility axis, the first diagram FTS
    // mirror, the uml_node subtype, and connector routing/tail vocabulary.
    //
    // visibility is a NEW axis, not a tier: DiagramTier stays pure
    // ownership and --promote-tier is untouched. PRIVATE = db-only;
    // PUBLIC = repo-serializable, legal ONLY on SESSION-tier rows — a
    // Swift store guard mirroring Store+DopeRepo.requireRepoWritableScope
    // (m0016 precedent: the rule crosses tables, so no CHECK can hold
    // it). The column itself is CHECKless like every vocabulary column
    // since m0021: validity lives in DiagramVisibility.
    //
    // diagram_uml_node: ONE table for every UML node kind (node_kind is
    // the vocabulary column, the drawing_shape/shape_kind precedent) —
    // six tables would make reshape a delete+recreate, which ghosts
    // every incoming connector via target_element_uuid's ON DELETE SET
    // NULL. Explicit width/height like drawing_text: markdown wrapping
    // needs a known layout width, and the kit never measures text.
    // Chrome columns are nullable — nil means "theme default" so a node
    // with no explicit colors renders correctly in both schemes.
    //
    // routing_kind/tail_kind defaults reproduce the pre-m0024 render
    // byte-for-byte: orthogonal_step IS today's routed polyline and
    // every existing connector has no tail decoration.
    //
    // diagram_fts: the update trigger is deliberately AFTER UPDATE OF
    // code, name, description — the diagram row is the first FTS source
    // that is HOT on unrelated columns (revision bumps on every stroke),
    // and a plain AFTER UPDATE would churn the index once per pencil
    // gesture. Any future rebuild of the diagram table must recreate
    // this mirror and its triggers (external content binds rowid —
    // m0015's lesson).
    static func m0024_diagramStudio(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0024_diagramStudio") { db in
            try db.execute(
                sql: """
                    ALTER TABLE diagram ADD COLUMN visibility TEXT NOT NULL DEFAULT 'PRIVATE';
                    CREATE INDEX idx_diagram_visibility ON diagram(visibility);

                    ALTER TABLE diagram_connector ADD COLUMN routing_kind TEXT NOT NULL DEFAULT 'orthogonal_step';
                    ALTER TABLE diagram_connector ADD COLUMN tail_kind TEXT NOT NULL DEFAULT 'none';
                    """)

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
                    """)

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
                    """)

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [24, Store.isoNow()]
            )
        }
    }
}
