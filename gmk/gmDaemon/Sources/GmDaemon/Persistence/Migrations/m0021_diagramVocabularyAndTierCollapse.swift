import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0021 — the diagram vocabulary migration, and the LAST rebuild of
    // diagram_element this schema should ever need.
    //
    // Four things ride together because they are one table rebuild each
    // and SQLite cannot ALTER a CHECK:
    //
    // 1. diagram_element loses BOTH literal-list CHECKs. This is the
    //    debt DopeCogElement.swift:11-19 already named in writing:
    //
    //      "The registry below is the whole extensibility story, and it
    //       exists because of a specific piece of debt. m0010's
    //       `diagram_element.element_type` carries a `CHECK
    //       (element_type IN (...))`, so adding a type there means
    //       rebuilding the table ... Adding a second element type is:
    //       one case, one registry entry, one subtype table. Never a
    //       migration."
    //
    //    Prompt 9 adds two types at once, which is the moment that debt
    //    comes due twice. Validity moves wholly into
    //    DiagramElementTypeSpec: both write paths validate against the
    //    registry, fetchElementInfo THROWS corruptState on an unknown
    //    element_type at read, and the subtype tables' UNIQUE
    //    element_uuid remains the structural proof that exactly one
    //    subtype row exists per element. That is the COGS mitigation
    //    verbatim, applied to the family COGS was written about.
    //
    //    The parent-nullability CHECK goes with it: top-levelness is now
    //    `spec.allowedParentTypes == nil`, a registry fact, so a new
    //    top-level type is also no longer a migration.
    //
    // 2. diagram drops the INSTANCE tier. The ladder is
    //    project/session/prompt; instance_uuid and its chain CHECK go
    //    away, and session/prompt still reach an instance transitively
    //    via session -> instance where anything needs one.
    //
    // 3. The `gmcc_diagram_path IS NULL OR tier != 'PROJECT'` CHECK goes
    //    away. It existed because only an instance carried a checkout
    //    path; screenshots now materialize under CKFS storage, which
    //    every tier has, so a PROJECT-tier diagram finally has a
    //    resolvable storage root.
    //
    // 4. The two new element types get their subtype tables, and strokes
    //    get their packed representation as plain ADD COLUMNs.
    //
    // Live blast radius: 2 diagram rows, 27 diagram_element rows, and 0
    // rows in every drawing/vertex table. Cheapest this will ever be.
    static func m0021_diagramVocabularyAndTierCollapse(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0021_diagramVocabularyAndTierCollapse") { db in
            let elementsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let diagramsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram") ?? -1

            // INSTANCE-tier rows become PROJECT-tier rather than being
            // deleted — this db is append-only history. project_uuid is
            // already NOT NULL on every row, so the chain stays valid. A
            // (project_uuid, code) collision would break the partial unique
            // index, so collided codes take a suffix instead of failing the
            // migration. Zero such rows live today; the SQL still has to be
            // correct on any database.
            try db.execute(
                sql: """
                    UPDATE diagram
                       SET code = code || '_from_instance_' || substr(uuid, 1, 8)
                     WHERE tier = 'INSTANCE'
                       AND EXISTS (SELECT 1 FROM diagram other
                                    WHERE other.tier = 'PROJECT'
                                      AND other.project_uuid = diagram.project_uuid
                                      AND other.code = diagram.code);
                    """)

            try db.execute(
                sql: """
                    CREATE TABLE diagram_new (
                        \(baseColumns),
                        project_uuid TEXT NOT NULL REFERENCES project(uuid) ON DELETE CASCADE,
                        session_uuid TEXT REFERENCES session(uuid) ON DELETE CASCADE,
                        prompt_uuid TEXT REFERENCES prompt(uuid) ON DELETE CASCADE,
                        tier TEXT NOT NULL
                            CHECK (tier IN ('PROJECT', 'SESSION', 'PROMPT')),
                        code TEXT NOT NULL,
                        name TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT ''
                            CHECK (length(description) <= 512),
                        gmcc_diagram_path TEXT,
                        dope_scope_code TEXT,
                        -- Ghost-tolerant kbite binding, on the dope_scope_code
                        -- precedent: a CODE resolved at read time, never an FK,
                        -- so a kbite can evolve out from under a diagram.
                        kbite_code TEXT,
                        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
                        CHECK ((session_uuid IS NOT NULL) = (tier IN ('SESSION', 'PROMPT'))),
                        CHECK ((prompt_uuid IS NOT NULL) = (tier = 'PROMPT'))
                    );

                    INSERT INTO diagram_new
                        (id, uuid, version, created_at, updated_at, project_uuid,
                         session_uuid, prompt_uuid, tier, code, name, description,
                         gmcc_diagram_path, dope_scope_code, revision)
                    SELECT id, uuid, version, created_at, updated_at, project_uuid,
                           session_uuid, prompt_uuid,
                           CASE tier WHEN 'INSTANCE' THEN 'PROJECT' ELSE tier END,
                           code, name, description, gmcc_diagram_path,
                           dope_scope_code, revision
                      FROM diagram;

                    DROP TABLE diagram;
                    ALTER TABLE diagram_new RENAME TO diagram;

                    CREATE UNIQUE INDEX idx_diagram_project_code
                        ON diagram(project_uuid, code) WHERE tier = 'PROJECT';
                    CREATE UNIQUE INDEX idx_diagram_session_code
                        ON diagram(session_uuid, code) WHERE tier = 'SESSION';
                    CREATE UNIQUE INDEX idx_diagram_prompt_code
                        ON diagram(prompt_uuid, code) WHERE tier = 'PROMPT';
                    CREATE INDEX idx_diagram_project_fk ON diagram(project_uuid);
                    CREATE INDEX idx_diagram_session_fk ON diagram(session_uuid);
                    CREATE INDEX idx_diagram_prompt_fk ON diagram(prompt_uuid);
                    CREATE INDEX idx_diagram_dope_scope_code ON diagram(dope_scope_code);
                    CREATE INDEX idx_diagram_kbite_code ON diagram(kbite_code);
                    """)

            // diagram_element: same shape, minus both literal-list CHECKs.
            // The self-reference guard STAYS — it is a structural fact, not
            // a vocabulary one, and no registry can express it.
            try db.execute(
                sql: """
                    CREATE TABLE diagram_element_new (
                        \(baseColumns),
                        diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                        parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        -- NO CHECK: validity is DiagramElementTypeSpec's, enforced
                        -- on both write paths and thrown on at read. See the
                        -- migration comment above and DopeCogElement.swift:11-19.
                        element_type TEXT NOT NULL,
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
                        CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                    );

                    INSERT INTO diagram_element_new
                        (id, uuid, version, created_at, updated_at, diagram_uuid,
                         parent_element_uuid, element_type, code, name, description,
                         sort_order, center_x, center_y, element_z, scale)
                    SELECT id, uuid, version, created_at, updated_at, diagram_uuid,
                           parent_element_uuid, element_type, code, name, description,
                           sort_order, center_x, center_y, element_z, scale
                      FROM diagram_element;

                    DROP TABLE diagram_element;
                    ALTER TABLE diagram_element_new RENAME TO diagram_element;

                    CREATE INDEX idx_diagram_element_diagram_fk
                        ON diagram_element(diagram_uuid);
                    CREATE INDEX idx_diagram_element_parent_fk
                        ON diagram_element(parent_element_uuid);
                    """)

            // drawing_text — the first bounded element that is NOT
            // vertex-derived. Markdown wrapping needs a known layout width,
            // so the size is explicit here rather than re-derived from a
            // vertex bounding box on every render. It lives on the SUBTYPE,
            // so diagram_element gains no width/height and the composing
            // `scale` is untouched.
            try db.execute(
                sql: """
                    CREATE TABLE diagram_drawing_text (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        markdown TEXT NOT NULL DEFAULT '',
                        width REAL NOT NULL CHECK (width > 0),
                        height REAL NOT NULL CHECK (height > 0),
                        font_size REAL NOT NULL DEFAULT 13 CHECK (font_size > 0),
                        text_color TEXT NOT NULL DEFAULT '#1a1a1a',
                        background_color TEXT
                    );

                    CREATE INDEX idx_diagram_drawing_text_element_fk
                        ON diagram_drawing_text(element_uuid);
                    """)

            // connector — the diagram subsystem's FIRST element-to-element
            // reference.
            //
            // target_element_uuid is NULLABLE with ON DELETE SET NULL, and
            // that is load-bearing: ON DELETE CASCADE here would delete this
            // SUBTYPE row while its diagram_element row survived with no
            // subtype row at all, which is corruptState on every subsequent
            // read of the whole diagram. SET NULL degrades a deleted target
            // to a renderable ghost instead, matching the ghost-tolerant
            // doctrine the dope code bindings already use.
            //
            // The self-reference half of the containment rule is cheap
            // enough to state in SQL. The sibling half ("may target a peer
            // of its own parent") cannot be: a CHECK cannot reference
            // another table, which is the same reason m0016's binding rule
            // is a Swift guard. It lives in DiagramContainment, called by
            // both write paths.
            try db.execute(
                sql: """
                    CREATE TABLE diagram_connector (
                        \(baseColumns),
                        element_uuid TEXT NOT NULL UNIQUE
                            REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        target_element_uuid TEXT
                            REFERENCES diagram_element(uuid) ON DELETE SET NULL,
                        stroke_color TEXT NOT NULL DEFAULT '#1a1a1a',
                        stroke_width REAL NOT NULL DEFAULT 2 CHECK (stroke_width > 0),
                        line_style TEXT NOT NULL DEFAULT 'solid',
                        head_kind TEXT NOT NULL DEFAULT 'arrow',
                        label TEXT NOT NULL DEFAULT '',
                        CHECK (target_element_uuid IS NULL
                               OR target_element_uuid != element_uuid)
                    );

                    CREATE INDEX idx_diagram_connector_element_fk
                        ON diagram_connector(element_uuid);
                    CREATE INDEX idx_diagram_connector_target_fk
                        ON diagram_connector(target_element_uuid);
                    """)

            // Packed strokes, purely additive. diagram_stroke_vertex and
            // diagram_shape_vertex are untouched and their
            // FK-to-subtype-unique-column proof is undisturbed; the two
            // representations coexist behind DiagramElementTypeSpec's
            // storage axis. Read precedence: packed_vertices when non-NULL,
            // else the vertex rows. The write path writes the blob AND
            // deletes that element's vertex rows, so a contradictory pair
            // cannot exist. No backfill — 0 rows.
            try db.execute(
                sql: """
                    ALTER TABLE diagram_drawing_stroke ADD COLUMN packed_vertices BLOB;
                    ALTER TABLE diagram_drawing_stroke ADD COLUMN vertex_count INTEGER;
                    """)

            let elementsAfter =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let diagramsAfter =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram") ?? -1
            guard elementsBefore == elementsAfter, diagramsBefore == diagramsAfter else {
                throw StoreError.corruptState(
                    entity: "diagram",
                    detail: "m0021 row-count mismatch: elements "
                        + "\(elementsBefore)->\(elementsAfter), diagrams "
                        + "\(diagramsBefore)->\(diagramsAfter)")
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [21, Store.isoNow()]
            )
        }
    }
}
