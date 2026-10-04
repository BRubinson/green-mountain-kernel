import Foundation
import GRDB

extension Migrations {
    // m0031 — the machine_host domain: machine, display, workstation,
    // workstation_display, workstation_workspace, app_process and managed_window,
    // all starting empty, so no BACKUP precondition. Every uniqueness rule is a separate
    // (often partial) UNIQUE INDEX so a later change never needs a table rebuild.
    // NO CHECKs: the workspace codes and flag vocabularies live in Swift.
    /// Creates the seven machine_host tables and their indexes.
    /// - Parameter migrator: The database migrator.
    static func m0031_machineHost(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("m0031_machineHost") { db in
            try m0031_createMachineAndDisplays(db)
            try m0031_createWorkstations(db)
            try m0031_createMirror(db)
            try db.execute(
                sql: "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                arguments: [31, Store.isoNow()]
            )
        }
    }

    /// Creates `machine` and `display` with their unique indexes.
    /// - Parameter db: The database being migrated.
    /// - Throws: Any SQLite error from the DDL.
    private static func m0031_createMachineAndDisplays(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE machine (
                    \(baseColumns),
                    hardware_uuid TEXT NOT NULL,
                    name TEXT NOT NULL,
                    code TEXT NOT NULL,
                    window_management_enabled INTEGER NOT NULL DEFAULT 0
                );
                CREATE UNIQUE INDEX idx_machine_hardware_uuid
                    ON machine(hardware_uuid);

                CREATE TABLE display (
                    \(baseColumns),
                    machine_uuid TEXT NOT NULL REFERENCES machine(uuid) ON DELETE CASCADE,
                    stable_key TEXT NOT NULL,
                    name TEXT NOT NULL,
                    is_builtin INTEGER NOT NULL DEFAULT 0,
                    cg_display_id INTEGER,
                    frame_x REAL,
                    frame_y REAL,
                    frame_width REAL,
                    frame_height REAL,
                    visible_x REAL,
                    visible_y REAL,
                    visible_width REAL,
                    visible_height REAL,
                    is_connected INTEGER NOT NULL DEFAULT 0,
                    last_seen_at TEXT,
                    pixel_width INTEGER,
                    pixel_height INTEGER,
                    backing_scale REAL,
                    physical_width_mm REAL,
                    physical_height_mm REAL,
                    refresh_hz REAL
                );
                CREATE UNIQUE INDEX idx_display_machine_key
                    ON display(machine_uuid, stable_key);
                """
        )
    }

    /// Creates `workstation`, `workstation_display` and `workstation_workspace` with their indexes.
    /// - Parameter db: The database being migrated.
    /// - Throws: Any SQLite error from the DDL.
    private static func m0031_createWorkstations(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE workstation (
                    \(baseColumns),
                    machine_uuid TEXT NOT NULL REFERENCES machine(uuid) ON DELETE CASCADE,
                    display_set_key TEXT NOT NULL,
                    name TEXT NOT NULL
                );
                CREATE UNIQUE INDEX idx_workstation_machine_set
                    ON workstation(machine_uuid, display_set_key);

                CREATE TABLE workstation_display (
                    \(baseColumns),
                    workstation_uuid TEXT NOT NULL REFERENCES workstation(uuid) ON DELETE CASCADE,
                    display_uuid TEXT NOT NULL REFERENCES display(uuid) ON DELETE CASCADE,
                    position INTEGER NOT NULL
                );
                CREATE UNIQUE INDEX idx_workstation_display_member
                    ON workstation_display(workstation_uuid, display_uuid);
                CREATE UNIQUE INDEX idx_workstation_display_position
                    ON workstation_display(workstation_uuid, position);
                CREATE INDEX idx_workstation_display_display
                    ON workstation_display(display_uuid);

                CREATE TABLE workstation_workspace (
                    \(baseColumns),
                    workstation_uuid TEXT NOT NULL REFERENCES workstation(uuid) ON DELETE CASCADE,
                    workspace_code TEXT NOT NULL,
                    display_uuid TEXT NOT NULL REFERENCES display(uuid) ON DELETE CASCADE,
                    is_active INTEGER NOT NULL DEFAULT 0
                );
                CREATE UNIQUE INDEX idx_workstation_workspace_code
                    ON workstation_workspace(workstation_uuid, workspace_code);
                CREATE UNIQUE INDEX idx_workstation_workspace_active
                    ON workstation_workspace(workstation_uuid, display_uuid) WHERE is_active = 1;
                CREATE INDEX idx_workstation_workspace_display
                    ON workstation_workspace(display_uuid);
                """
        )
    }

    /// Creates the `app_process` and `managed_window` mirror tables with their indexes.
    /// - Parameter db: The database being migrated.
    /// - Throws: Any SQLite error from the DDL.
    private static func m0031_createMirror(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE app_process (
                    \(baseColumns),
                    machine_uuid TEXT NOT NULL REFERENCES machine(uuid) ON DELETE CASCADE,
                    pid INTEGER NOT NULL,
                    launched_at TEXT NOT NULL,
                    bundle_id TEXT,
                    name TEXT NOT NULL,
                    is_running INTEGER NOT NULL DEFAULT 1,
                    deleted_on TEXT
                );
                CREATE UNIQUE INDEX idx_app_process_live
                    ON app_process(machine_uuid, pid, launched_at) WHERE deleted_on IS NULL;
                CREATE INDEX idx_app_process_bundle
                    ON app_process(bundle_id);

                CREATE TABLE managed_window (
                    \(baseColumns),
                    app_process_uuid TEXT NOT NULL REFERENCES app_process(uuid) ON DELETE CASCADE,
                    workspace_code TEXT,
                    cg_window_id INTEGER NOT NULL,
                    title TEXT,
                    column_index INTEGER,
                    column_weight REAL NOT NULL DEFAULT 1.0,
                    is_floating INTEGER NOT NULL DEFAULT 0,
                    frame_x REAL,
                    frame_y REAL,
                    frame_width REAL,
                    frame_height REAL,
                    pre_park_x REAL,
                    pre_park_y REAL,
                    pre_park_width REAL,
                    pre_park_height REAL,
                    deleted_on TEXT
                );
                CREATE UNIQUE INDEX idx_managed_window_live
                    ON managed_window(app_process_uuid, cg_window_id) WHERE deleted_on IS NULL;
                CREATE INDEX idx_managed_window_workspace
                    ON managed_window(workspace_code, column_index);
                CREATE INDEX idx_managed_window_cg
                    ON managed_window(cg_window_id);
                """
        )
    }
}
