import Foundation
import GRDB
import GmDaemonSdk

extension Migrations {
    // m0018 — diagram_element.element_type 'dope_scope' becomes
    // 'dope_scope_persistence_layer', and the subtype table renames with it. The
    // value appears in TWO CHECKs and SQLite cannot ALTER a CHECK, so this is a
    // create-copy-drop-rename rebuild on the m0013 precedent.
    static func m0018_diagramDopeScopePersistenceLayer(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0018_diagramDopeScopePersistenceLayer") { db in
            let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let bindingsBefore =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_dope_scope") ?? -1

            try db.execute(
                sql: """
                    CREATE TABLE diagram_element_new (
                        \(baseColumns),
                        diagram_uuid TEXT NOT NULL REFERENCES diagram(uuid) ON DELETE CASCADE,
                        parent_element_uuid TEXT REFERENCES diagram_element(uuid) ON DELETE CASCADE,
                        element_type TEXT NOT NULL
                            CHECK (element_type IN ('drawing_layer', 'drawing_stroke',
                                                    'drawing_shape', 'dope_scope_persistence_layer',
                                                    'dope_entity')),
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
                        CHECK ((element_type IN ('dope_scope_persistence_layer', 'drawing_layer'))
                                = (parent_element_uuid IS NULL)),
                        CHECK (parent_element_uuid IS NULL OR parent_element_uuid != uuid)
                    );

                    INSERT INTO diagram_element_new
                        (id, uuid, version, created_at, updated_at, diagram_uuid,
                         parent_element_uuid, element_type, code, name, description,
                         sort_order, center_x, center_y, element_z, scale)
                    SELECT id, uuid, version, created_at, updated_at, diagram_uuid,
                           parent_element_uuid,
                           CASE element_type
                                WHEN 'dope_scope' THEN 'dope_scope_persistence_layer'
                                ELSE element_type END,
                           code, name, description, sort_order,
                           center_x, center_y, element_z, scale
                      FROM diagram_element;

                    DROP TABLE diagram_element;
                    ALTER TABLE diagram_element_new RENAME TO diagram_element;

                    ALTER TABLE diagram_dope_scope
                        RENAME TO diagram_dope_scope_persistence_layer;

                    CREATE INDEX idx_diagram_element_diagram_fk
                        ON diagram_element(diagram_uuid);
                    CREATE INDEX idx_diagram_element_parent_fk
                        ON diagram_element(parent_element_uuid);
                    """
            )

            let after = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
            let bindingsAfter =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM diagram_dope_scope_persistence_layer"
                ) ?? -1
            guard before == after, bindingsBefore == bindingsAfter else {
                throw StoreError.corruptState(
                    entity: "diagram_element",
                    detail: "m0018 row-count mismatch: elements \(before)->\(after), "
                        + "bindings \(bindingsBefore)->\(bindingsAfter)"
                )
            }

            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [18, Store.isoNow()]
            )
        }
    }
}
