import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0010 — DIAGRAM domain modeling in m0007's grammar: baseColumns identity,
    // an index per FK, CHECK-coupled discriminators, and PARTIAL unique indexes
    // wherever a nullable FK joins a uniqueness rule. Ownership is a chain-non-
    // null tier ladder: each tier fills its own FK and every ancestor's, and
    // project_uuid is ALWAYS NOT NULL. dope bindings are TEXT codes, not SQL
    // FKs: DOPE_INGEST re-mints every child uuid, so a uuid FK would dangle, and
    // a dangling code is a legal renderable state. Vertex FKs target the subtype
    // table's UNIQUE element_uuid, so a vertex can only hang off a stroke.
    static func m0010_diagramDomainModel(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0010_diagramDomainModel") { db in
            try db.execute(
                sql: """
                    CREATE TABLE diagram (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                        instance_uuid TEXT REFERENCES instance(uuid) ON DELETE CASCADE,
                        session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                        tier TEXT NOT NULL
                            CHECK (tier IN ('PROJECT', 'INSTANCE', 'SESSION', 'PROMPT')),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        gmcc_diagram_path TEXT,
                        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                        CHECK ((instance_uuid IS NOT NULL) = (tier IN ('INSTANCE', 'SESSION', 'PROMPT'))),
                        CHECK ((session_uuid IS NOT NULL) = (tier IN ('SESSION', 'PROMPT'))),
                        CHECK ((prompt_uuid IS NOT NULL) = (tier = 'PROMPT')),
                        CHECK (gmcc_diagram_path IS NULL OR tier != 'PROJECT')
                    );

                    CREATE TABLE diagram_element (
                        \(baseColumns),
                        diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                        parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        element_type TEXT NOT NULL
                            CHECK (element_type IN ('drawing_layer', 'drawing_stroke',
                                                    'drawing_shape', 'dope_scope', 'dope_entity')),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        center_x REAL NOT NULL DEFAULT 0,
                        center_y REAL NOT NULL DEFAULT 0,
                        element_z REAL NOT NULL DEFAULT 0,
                        scale REAL NOT NULL DEFAULT 1 CHECK (scale > 0),
                        UNIQUE(diagram_uuid, code),
                        CHECK ((element_type IN ('dope_scope', 'drawing_layer'))
                                = (parent_element_uuid IS NULL)),
                        CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                    );

                    CREATE TABLE diagram_drawing_layer (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        opacity REAL NOT NULL DEFAULT 1
                            CHECK (opacity >= 0 AND opacity <= 1),
                        visible INTEGER NOT NULL DEFAULT 1 CHECK (visible IN (0, 1)),
                        locked INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0, 1))
                    );

                    CREATE TABLE diagram_drawing_stroke (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        tool TEXT NOT NULL DEFAULT 'pencil'
                            CHECK (tool IN ('pencil', 'marker', 'highlighter')),
                        stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                        stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0)
                    );

                    CREATE TABLE diagram_drawing_shape (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        shape_kind TEXT NOT NULL
                            CHECK (shape_kind IN ('rectangle', 'ellipse', 'line',
                                                  'arrow', 'polygon')),
                        stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                        stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0),
                        fill_color TEXT,
                        corner_radius REAL CHECK (corner_radius IS NULL OR corner_radius >= 0),
                        CHECK (corner_radius IS NULL OR shape_kind = 'rectangle')
                    );

                    CREATE TABLE diagram_dope_scope (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        dope_scope_code TEXT NOT NULL
                    );

                    CREATE TABLE diagram_dope_entity (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        entity_code TEXT NOT NULL
                    );

                    CREATE TABLE diagram_stroke_vertex (
                        \(baseColumns),
                        stroke_element_uuid TEXT NOT NULL
                            REFERENCES diagram_drawing_stroke(element_uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL CHECK (seq >= 0),
                        x REAL NOT NULL,
                        y REAL NOT NULL,
                        pressure REAL CHECK (pressure IS NULL OR (pressure >= 0 AND pressure <= 1)),
                        UNIQUE(stroke_element_uuid, seq)
                    );

                    CREATE TABLE diagram_shape_vertex (
                        \(baseColumns),
                        shape_element_uuid TEXT NOT NULL
                            REFERENCES diagram_drawing_shape(element_uuid) ON DELETE CASCADE,
                        seq INTEGER NOT NULL CHECK (seq >= 0),
                        x REAL NOT NULL,
                        y REAL NOT NULL,
                        UNIQUE(shape_element_uuid, seq)
                    );

                    CREATE UNIQUE INDEX idx_diagram_project_code
                        ON diagram(project_uuid, code) WHERE tier = 'PROJECT';
                    CREATE UNIQUE INDEX idx_diagram_instance_code
                        ON diagram(instance_uuid, code) WHERE tier = 'INSTANCE';
                    CREATE UNIQUE INDEX idx_diagram_session_code
                        ON diagram(session_uuid, code) WHERE tier = 'SESSION';
                    CREATE UNIQUE INDEX idx_diagram_prompt_code
                        ON diagram(prompt_uuid, code) WHERE tier = 'PROMPT';

                    CREATE INDEX idx_diagram_project_fk ON diagram(project_uuid);
                    CREATE INDEX idx_diagram_instance_fk ON diagram(instance_uuid);
                    CREATE INDEX idx_diagram_session_fk ON diagram(session_uuid);
                    CREATE INDEX idx_diagram_prompt_fk ON diagram(prompt_uuid);
                    CREATE INDEX idx_diagram_element_diagram_fk
                        ON diagram_element(diagram_uuid);
                    CREATE INDEX idx_diagram_element_parent_fk
                        ON diagram_element(parent_element_uuid);
                    CREATE INDEX idx_diagram_drawing_layer_element_fk
                        ON diagram_drawing_layer(element_uuid);
                    CREATE INDEX idx_diagram_drawing_stroke_element_fk
                        ON diagram_drawing_stroke(element_uuid);
                    CREATE INDEX idx_diagram_drawing_shape_element_fk
                        ON diagram_drawing_shape(element_uuid);
                    CREATE INDEX idx_diagram_dope_scope_element_fk
                        ON diagram_dope_scope(element_uuid);
                    CREATE INDEX idx_diagram_dope_entity_element_fk
                        ON diagram_dope_entity(element_uuid);
                    CREATE INDEX idx_diagram_stroke_vertex_stroke_fk
                        ON diagram_stroke_vertex(stroke_element_uuid);
                    CREATE INDEX idx_diagram_shape_vertex_shape_fk
                        ON diagram_shape_vertex(shape_element_uuid);
                    """
            )

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [10, Store.isoNow()]
            )
        }
    }
}
