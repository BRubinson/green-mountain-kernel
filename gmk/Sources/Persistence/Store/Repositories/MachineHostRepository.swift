import Foundation
import GRDB

/// Data access for the seven machine_host tables.
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. Writes append no daemon_event: the mirror is high-frequency
/// local state, and no subscriber reads it.
struct MachineHostRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Column values for `insertBase` and `updateBase`, keyed by column name.
    private typealias ColumnValues = [String: (any DatabaseValueConvertible)?]

    // MARK: - Machine

    /// The machine carrying `hardwareUuid`, inserted with window management off when absent.
    ///
    /// - Parameters:
    ///   - hardwareUuid: The IOPlatformUUID; the lookup key, never sent on the wire.
    ///   - name: The human name, used only when the row is created.
    ///   - code: The short code, used only when the row is created.
    /// - Returns: The existing or newly inserted machine.
    /// - Throws: Database errors.
    func ensureMachine(hardwareUuid: String, name: String, code: String) throws -> MachineRecord {
        if let existing = try MachineRecord.filter(MachineRecord.Columns.hardwareUuid == hardwareUuid).fetchOne(db) {
            return existing
        }
        let uuid = try core.insertBase(
            db,
            table: MachineRecord.databaseTableName,
            extra: [
                "hardware_uuid": hardwareUuid,
                "name": name,
                "code": code,
                "window_management_enabled": false,
            ]
        )
        return try MachineRecord.require(db, uuid: uuid)
    }

    /// Turns window management on or off for a machine at the version the caller read.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine to change.
    ///   - enabled: The new value of the flag.
    ///   - expectedVersion: The version the caller last read.
    /// - Returns: The machine after the write.
    /// - Throws: `StoreError.notFound` or `StoreError.versionConflict` from the version gate.
    func setEnabled(machineUuid: String, enabled: Bool, expectedVersion: Int64) throws -> MachineRecord {
        try core.updateBase(
            db,
            table: MachineRecord.databaseTableName,
            uuid: machineUuid,
            expectedVersion: expectedVersion,
            set: ["window_management_enabled": enabled]
        )
        return try MachineRecord.require(db, uuid: machineUuid)
    }

    // MARK: - Displays

    /// Upserts the enumerated displays on `stableKey` and marks every other display disconnected.
    ///
    /// The workstation for the connected set is minted in the same transaction on first sight.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine the displays belong to.
    ///   - displays: Every display the current enumeration reports.
    /// - Returns: All of the machine's displays, connected or not, oldest first.
    /// - Throws: `StoreError.notFound` when the machine is unknown; database errors.
    func syncDisplays(machineUuid: String, displays: [DisplayInput]) throws -> [DisplayRecord] {
        _ = try MachineRecord.require(db, uuid: machineUuid)
        let now = StoreCore.isoNow()
        let existing = try displayRecords(machineUuid: machineUuid)
        let byKey = Dictionary(existing.map { ($0.stableKey, $0) }, uniquingKeysWith: { first, _ in first })
        for input in displays {
            let values = displayValues(input, seenAt: now)
            if let row = byKey[input.stableKey] {
                try core.updateBase(
                    db,
                    table: DisplayRecord.databaseTableName,
                    uuid: row.uuid,
                    expectedVersion: row.version,
                    set: values
                )
            } else {
                let keys: ColumnValues = ["machine_uuid": machineUuid, "stable_key": input.stableKey]
                try core.insertBase(
                    db,
                    table: DisplayRecord.databaseTableName,
                    extra: values.merging(keys) { current, _ in current }
                )
            }
        }
        let present = Set(displays.map(\.stableKey))
        for row in existing where row.isConnected && !present.contains(row.stableKey) {
            try core.updateBase(
                db,
                table: DisplayRecord.databaseTableName,
                uuid: row.uuid,
                expectedVersion: row.version,
                set: ["is_connected": false]
            )
        }
        let synced = try displayRecords(machineUuid: machineUuid)
        try ensureWorkstation(machineUuid: machineUuid, connected: displays, records: synced)
        return synced
    }

    /// The column values one enumerated display writes, stamped as seen and connected.
    ///
    /// - Parameters:
    ///   - input: The display as enumerated.
    ///   - seenAt: The ISO-8601 stamp for `last_seen_at`.
    /// - Returns: The columns to insert or update.
    private func displayValues(_ input: DisplayInput, seenAt: String) -> ColumnValues {
        [
            "name": input.name,
            "is_builtin": input.isBuiltin,
            "cg_display_id": input.cgDisplayId,
            "frame_x": input.frameX,
            "frame_y": input.frameY,
            "frame_width": input.frameWidth,
            "frame_height": input.frameHeight,
            "visible_x": input.visibleX,
            "visible_y": input.visibleY,
            "visible_width": input.visibleWidth,
            "visible_height": input.visibleHeight,
            "pixel_width": input.pixelWidth,
            "pixel_height": input.pixelHeight,
            "backing_scale": input.backingScale,
            "physical_width_mm": input.physicalWidthMm,
            "physical_height_mm": input.physicalHeightMm,
            "refresh_hz": input.refreshHz,
            "is_connected": true,
            "last_seen_at": seenAt,
        ]
    }

    /// Every display of a machine, oldest first.
    ///
    /// - Parameter machineUuid: The owning machine.
    /// - Returns: The machine's display records.
    /// - Throws: Database errors.
    private func displayRecords(machineUuid: String) throws -> [DisplayRecord] {
        try DisplayRecord
            .filter(DisplayRecord.Columns.machineUuid == machineUuid)
            .order(DisplayRecord.Columns.createdAt, DisplayRecord.Columns.uuid)
            .fetchAll(db)
    }

    // MARK: - Workstations

    /// Mints the workstation for a connected display set unless one already carries its key.
    ///
    /// The workstation, its members and its 21 placement rows are written together from
    /// `MachineHostPlacement.seedPlan`; an empty set mints nothing.
    ///
    /// - Parameters:
    ///   - machineUuid: The owning machine.
    ///   - connected: The displays the current enumeration reports.
    ///   - records: The machine's display records after the upsert, to resolve stable keys to uuids.
    /// - Throws: Database errors, including the per-machine display-set unique index.
    private func ensureWorkstation(machineUuid: String, connected: [DisplayInput], records: [DisplayRecord]) throws {
        guard !connected.isEmpty else { return }
        let key = MachineHostPlacement.displaySetKey(connected.map(\.stableKey))
        guard try workstation(machineUuid: machineUuid, displaySetKey: key) == nil else { return }
        let plan = MachineHostPlacement.seedPlan(
            connected.map {
                MachineHostPlacement.SeedDisplay(stableKey: $0.stableKey, isBuiltin: $0.isBuiltin, originX: $0.frameX)
            }
        )
        let byKey = Dictionary(records.map { ($0.stableKey, $0) }, uniquingKeysWith: { first, _ in first })
        let members = plan.positions.sorted { $0.value < $1.value }.compactMap { byKey[$0.key] }
        let workstationUuid = try core.insertBase(
            db,
            table: WorkstationRecord.databaseTableName,
            extra: [
                "machine_uuid": machineUuid,
                "display_set_key": key,
                "name": members.map(\.name).joined(separator: " + "),
            ]
        )
        for (position, display) in members.enumerated() {
            try core.insertBase(
                db,
                table: WorkstationDisplayRecord.databaseTableName,
                extra: ["workstation_uuid": workstationUuid, "display_uuid": display.uuid, "position": position]
            )
        }
        try insertPlacements(workstationUuid: workstationUuid, plan: plan, displays: byKey)
    }

    /// Inserts one placement row per workspace code, in code order, as the seed plan lays them out.
    ///
    /// - Parameters:
    ///   - workstationUuid: The workstation being minted.
    ///   - plan: The seed plan, keyed by display stable key.
    ///   - displays: The machine's display records keyed by stable key.
    /// - Throws: Database errors, including the one-active-per-display index.
    private func insertPlacements(
        workstationUuid: String,
        plan: MachineHostPlacement.SeedPlan,
        displays: [String: DisplayRecord]
    ) throws {
        for code in MachineHostPlacement.WorkspaceCodes.all {
            guard let stableKey = plan.placement[code], let display = displays[stableKey] else { continue }
            try core.insertBase(
                db,
                table: WorkstationWorkspaceRecord.databaseTableName,
                extra: [
                    "workstation_uuid": workstationUuid,
                    "workspace_code": code,
                    "display_uuid": display.uuid,
                    "is_active": plan.active[stableKey] == code,
                ]
            )
        }
    }

    /// The machine's workstation carrying a display-set key, if any.
    ///
    /// - Parameters:
    ///   - machineUuid: The owning machine.
    ///   - displaySetKey: The key from `MachineHostPlacement.displaySetKey`.
    /// - Returns: The workstation, or nil when the set has never been seen.
    /// - Throws: Database errors.
    private func workstation(machineUuid: String, displaySetKey: String) throws -> WorkstationRecord? {
        try WorkstationRecord
            .filter(WorkstationRecord.Columns.machineUuid == machineUuid)
            .filter(WorkstationRecord.Columns.displaySetKey == displaySetKey)
            .fetchOne(db)
    }

    /// Renames a workstation at the version the caller read.
    ///
    /// - Parameters:
    ///   - uuid: The workstation to rename.
    ///   - name: The new name.
    ///   - expectedVersion: The version the caller last read.
    /// - Returns: The workstation after the write.
    /// - Throws: `StoreError.notFound` or `StoreError.versionConflict` from the version gate.
    func renameWorkstation(uuid: String, name: String, expectedVersion: Int64) throws -> WorkstationRecord {
        try core.updateBase(
            db,
            table: WorkstationRecord.databaseTableName,
            uuid: uuid,
            expectedVersion: expectedVersion,
            set: ["name": name]
        )
        return try WorkstationRecord.require(db, uuid: uuid)
    }

    /// Deletes a workstation at the version the caller read; its members and placements cascade.
    ///
    /// - Parameters:
    ///   - uuid: The workstation to forget.
    ///   - expectedVersion: The version the caller last read.
    /// - Throws: `MachineHostError.cannotForgetActiveWorkstation` when its display set is the connected one;
    ///   `StoreError.notFound` or `StoreError.versionConflict` from the version gate.
    func forgetWorkstation(uuid: String, expectedVersion: Int64) throws {
        let target = try WorkstationRecord.require(db, uuid: uuid)
        let displays = try displayRecords(machineUuid: target.machineUuid)
        guard activeWorkstation([target], displays: displays) == nil else {
            throw MachineHostError.cannotForgetActiveWorkstation(workstation: uuid)
        }
        try core.deleteBase(
            db,
            table: WorkstationRecord.databaseTableName,
            uuid: uuid,
            expectedVersion: expectedVersion
        )
    }

    // MARK: - Snapshot

    /// Every live machine_host row of one machine, read table by table.
    ///
    /// - Parameter machineUuid: The machine to read.
    /// - Returns: The machine with its displays, workstations, members, placements, live processes and
    ///   windows, and the workstation whose key matches the connected set.
    /// - Throws: `StoreError.notFound` when the machine is unknown; database errors.
    func loadSnapshot(machineUuid: String) throws -> MachineHostSnapshotRow {
        let machine = try MachineRecord.require(db, uuid: machineUuid)
        let displays = try displayRecords(machineUuid: machineUuid)
        let workstations =
            try WorkstationRecord
            .filter(WorkstationRecord.Columns.machineUuid == machineUuid)
            .order(WorkstationRecord.Columns.createdAt, WorkstationRecord.Columns.uuid)
            .fetchAll(db)
        let workstationUuids = workstations.map(\.uuid)
        let members =
            try WorkstationDisplayRecord
            .filter(workstationUuids.contains(WorkstationDisplayRecord.Columns.workstationUuid))
            .order(WorkstationDisplayRecord.Columns.workstationUuid, WorkstationDisplayRecord.Columns.position)
            .fetchAll(db)
        let placements = try placementRecords(workstationUuids: workstationUuids)
        let processes = try liveProcesses(machineUuid: machineUuid)
        let windows = try liveWindows(processUuids: processes.map(\.uuid))
        return MachineHostSnapshotRow(
            machine: machine.dto(),
            displays: displays.map { $0.dto() },
            workstations: workstations.map { $0.dto() },
            workstationDisplays: members.map { $0.dto() },
            workstationWorkspaces: placements.map { $0.dto() },
            activeWorkstationUuid: activeWorkstation(workstations, displays: displays)?.uuid,
            appProcesses: processes.map { $0.dto() },
            managedWindows: windows.map { $0.dto() }
        )
    }

    /// The workstation whose display-set key equals the connected displays' key.
    ///
    /// - Parameters:
    ///   - workstations: The machine's workstations.
    ///   - displays: The machine's displays, connected or not.
    /// - Returns: The active workstation, or nil when nothing is connected or the set is unminted.
    private func activeWorkstation(
        _ workstations: [WorkstationRecord],
        displays: [DisplayRecord]
    )
        -> WorkstationRecord?
    {
        let connected = displays.filter(\.isConnected).map(\.stableKey)
        guard !connected.isEmpty else { return nil }
        let key = MachineHostPlacement.displaySetKey(connected)
        return workstations.first { $0.displaySetKey == key }
    }

    /// The placement rows of the given workstations, in workspace-code order within each.
    ///
    /// - Parameter workstationUuids: The owning workstations.
    /// - Returns: The placement records.
    /// - Throws: Database errors.
    private func placementRecords(workstationUuids: [String]) throws -> [WorkstationWorkspaceRecord] {
        let rank = Dictionary(
            uniqueKeysWithValues: MachineHostPlacement.WorkspaceCodes.all.enumerated().map { ($1, $0) }
        )
        return
            try WorkstationWorkspaceRecord
            .filter(workstationUuids.contains(WorkstationWorkspaceRecord.Columns.workstationUuid))
            .fetchAll(db)
            .sorted {
                ($0.workstationUuid, rank[$0.workspaceCode] ?? Int.max)
                    < ($1.workstationUuid, rank[$1.workspaceCode] ?? Int.max)
            }
    }

    /// The non-deleted processes of a machine, oldest first.
    ///
    /// - Parameter machineUuid: The owning machine.
    /// - Returns: The live app-process records.
    /// - Throws: Database errors.
    private func liveProcesses(machineUuid: String) throws -> [AppProcessRecord] {
        try AppProcessRecord
            .filter(AppProcessRecord.Columns.machineUuid == machineUuid)
            .notDeleted()
            .order(AppProcessRecord.Columns.createdAt, AppProcessRecord.Columns.uuid)
            .fetchAll(db)
    }

    /// The non-deleted windows owned by the given processes, oldest first.
    ///
    /// - Parameter processUuids: The owning app-process uuids.
    /// - Returns: The live managed-window records.
    /// - Throws: Database errors.
    private func liveWindows(processUuids: [String]) throws -> [ManagedWindowRecord] {
        try ManagedWindowRecord
            .filter(processUuids.contains(ManagedWindowRecord.Columns.appProcessUuid))
            .notDeleted()
            .order(ManagedWindowRecord.Columns.createdAt, ManagedWindowRecord.Columns.uuid)
            .fetchAll(db)
    }

    // MARK: - Placement

    /// Moves a workspace code to another member display of a workstation, inactive there.
    ///
    /// When the code was active on its source display, active hands off to the first remaining
    /// code there; the move is written before the hand-off so the partial unique index holds.
    ///
    /// - Parameters:
    ///   - workstationUuid: The workstation whose placement changes.
    ///   - code: The workspace code to move.
    ///   - displayUuid: The member display it moves to.
    /// - Returns: The code's placement row after the write.
    /// - Throws: `StoreError.notFound` for an unknown workstation; the refusal from
    ///   `MachineHostPlacement.placementRefusal` (`.unknownWorkspaceCode`, `.displayNotInWorkstation`,
    ///   `.wouldStrandDisplay`); database errors.
    func assignWorkspace(
        workstationUuid: String,
        code: String,
        displayUuid: String
    ) throws
        -> WorkstationWorkspaceRecord
    {
        _ = try WorkstationRecord.require(db, uuid: workstationUuid)
        let placements = try placementRecords(workstationUuids: [workstationUuid])
        let placement = Dictionary(placements.map { ($0.workspaceCode, $0.displayUuid) }) { first, _ in first }
        let members = try memberDisplayUuids(workstationUuid: workstationUuid)
        if let refusal = MachineHostPlacement.placementRefusal(
            code: code,
            from: placement[code] ?? "",
            to: displayUuid,
            placement: placement,
            members: members
        ) {
            throw refusal
        }
        guard let row = placements.first(where: { $0.workspaceCode == code }) else {
            throw MachineHostError.unknownWorkspaceCode(code)
        }
        guard row.displayUuid != displayUuid else { return row }
        try core.updateBase(
            db,
            table: WorkstationWorkspaceRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: ["display_uuid": displayUuid, "is_active": false]
        )
        if row.isActive,
            let heir = MachineHostPlacement.activeHandOff(leaving: code, from: row.displayUuid, placement: placement),
            let heirRow = placements.first(where: { $0.workspaceCode == heir })
        {
            try setActive(heirRow, true)
        }
        return try WorkstationWorkspaceRecord.require(db, uuid: row.uuid)
    }

    /// Makes a workspace code the visible one on a display of a workstation.
    ///
    /// The display's current active row is deactivated before the new one activates, because
    /// the partial unique index allows one active row per display at every statement.
    ///
    /// - Parameters:
    ///   - workstationUuid: The workstation to switch within.
    ///   - displayUuid: The display to switch.
    ///   - code: The workspace code to show; it must already be placed on `displayUuid`.
    /// - Returns: Every placement row on the display after the switch, in code order.
    /// - Throws: `MachineHostError.codeNotOnDisplay` when the code is placed elsewhere or unknown;
    ///   database errors.
    func setActiveWorkspace(
        workstationUuid: String,
        displayUuid: String,
        code: String
    ) throws
        -> [WorkstationWorkspaceRecord]
    {
        let onDisplay = try placementRecords(workstationUuids: [workstationUuid])
            .filter { $0.displayUuid == displayUuid }
        guard let row = onDisplay.first(where: { $0.workspaceCode == code }) else {
            throw MachineHostError.codeNotOnDisplay(code: code, display: displayUuid)
        }
        for other in onDisplay where other.isActive && other.workspaceCode != code {
            try setActive(other, false)
        }
        if !row.isActive { try setActive(row, true) }
        return try placementRecords(workstationUuids: [workstationUuid]).filter { $0.displayUuid == displayUuid }
    }

    /// The display uuids that are members of a workstation.
    ///
    /// - Parameter workstationUuid: The workstation to read.
    /// - Returns: Its member display uuids.
    /// - Throws: Database errors.
    private func memberDisplayUuids(workstationUuid: String) throws -> Set<String> {
        let rows =
            try WorkstationDisplayRecord
            .filter(WorkstationDisplayRecord.Columns.workstationUuid == workstationUuid)
            .fetchAll(db)
        return Set(rows.map(\.displayUuid))
    }

    /// Writes `is_active` on one placement row at the version just read.
    ///
    /// - Parameters:
    ///   - row: The placement row to change.
    ///   - active: The new value.
    /// - Throws: Database errors, including the one-active-per-display index.
    private func setActive(_ row: WorkstationWorkspaceRecord, _ active: Bool) throws {
        try core.updateBase(
            db,
            table: WorkstationWorkspaceRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: ["is_active": active]
        )
    }

    // MARK: - Mirror

    /// Writes one mirror tick: process upserts, then window upserts, then retirements.
    ///
    /// Rows whose mirrored fields are unchanged are not rewritten, so their versions hold still.
    ///
    /// - Parameter batch: The tick to write.
    /// - Returns: The process and window rows the tick inserted or changed.
    /// - Throws: `MachineHostError.unknownProcess` for a window whose process has no live row;
    ///   `StoreError.notFound` for an unknown uuid in a retire list; database errors.
    func applyMirrorBatch(_ batch: MirrorBatch) throws -> MirrorFlushRow {
        var processes: [AppProcessRecord] = []
        for upsert in batch.processes {
            if let row = try upsertProcess(machineUuid: batch.machineUuid, upsert: upsert) { processes.append(row) }
        }
        var windows: [ManagedWindowRecord] = []
        for upsert in batch.windows {
            guard let process = try liveProcess(machineUuid: batch.machineUuid, identity: upsert.process) else {
                throw MachineHostError.unknownProcess(pid: upsert.process.pid, launchedAt: upsert.process.launchedAt)
            }
            if let row = try upsertWindow(processUuid: process.uuid, upsert: upsert) { windows.append(row) }
        }
        let now = StoreCore.isoNow()
        for uuid in batch.retireWindowUuids {
            try retireWindow(ManagedWindowRecord.require(db, uuid: uuid), at: now)
        }
        for uuid in batch.retireProcessUuids {
            try retireProcess(AppProcessRecord.require(db, uuid: uuid), at: now)
        }
        return MirrorFlushRow(appProcesses: processes.map { $0.dto() }, managedWindows: windows.map { $0.dto() })
    }

    /// The live process row carrying an identity on a machine.
    ///
    /// - Parameters:
    ///   - machineUuid: The owning machine.
    ///   - identity: The pid and launch stamp.
    /// - Returns: The live row, or nil when none carries the identity.
    /// - Throws: Database errors.
    private func liveProcess(machineUuid: String, identity: AppProcessIdentity) throws -> AppProcessRecord? {
        try AppProcessRecord
            .filter(AppProcessRecord.Columns.machineUuid == machineUuid)
            .filter(AppProcessRecord.Columns.pid == identity.pid)
            .filter(AppProcessRecord.Columns.launchedAt == identity.launchedAt)
            .notDeleted()
            .fetchOne(db)
    }

    /// Inserts or updates one process row on its identity.
    ///
    /// - Parameters:
    ///   - machineUuid: The owning machine.
    ///   - upsert: The process as the mirror saw it.
    /// - Returns: The written row, or nil when the live row already matched.
    /// - Throws: Database errors.
    private func upsertProcess(machineUuid: String, upsert: AppProcessUpsert) throws -> AppProcessRecord? {
        let values: ColumnValues = ["bundle_id": upsert.bundleId, "name": upsert.name, "is_running": upsert.isRunning]
        guard let row = try liveProcess(machineUuid: machineUuid, identity: upsert.identity) else {
            let identity: ColumnValues = [
                "machine_uuid": machineUuid, "pid": upsert.identity.pid, "launched_at": upsert.identity.launchedAt,
            ]
            let uuid = try core.insertBase(
                db,
                table: AppProcessRecord.databaseTableName,
                extra: values.merging(identity) { current, _ in current }
            )
            return try AppProcessRecord.require(db, uuid: uuid)
        }
        let current = AppProcessUpsert(
            identity: row.identity,
            bundleId: row.bundleId,
            name: row.name,
            isRunning: row.isRunning
        )
        guard current != upsert else { return nil }
        try core.updateBase(
            db,
            table: AppProcessRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: values
        )
        return try AppProcessRecord.require(db, uuid: row.uuid)
    }

    /// Inserts or updates one window row on its process and `cg_window_id`.
    ///
    /// - Parameters:
    ///   - processUuid: The owning process row.
    ///   - upsert: The window as the mirror saw it.
    /// - Returns: The written row, or nil when the live row already matched.
    /// - Throws: Database errors.
    private func upsertWindow(processUuid: String, upsert: ManagedWindowUpsert) throws -> ManagedWindowRecord? {
        let existing =
            try ManagedWindowRecord
            .filter(ManagedWindowRecord.Columns.appProcessUuid == processUuid)
            .filter(ManagedWindowRecord.Columns.cgWindowId == upsert.cgWindowId)
            .notDeleted()
            .fetchOne(db)
        let values = windowValues(upsert)
        guard let row = existing else {
            let keys: ColumnValues = ["app_process_uuid": processUuid, "cg_window_id": upsert.cgWindowId]
            let uuid = try core.insertBase(
                db,
                table: ManagedWindowRecord.databaseTableName,
                extra: values.merging(keys) { current, _ in current }
            )
            return try ManagedWindowRecord.require(db, uuid: uuid)
        }
        guard mirrored(row, process: upsert.process) != upsert else { return nil }
        try core.updateBase(
            db,
            table: ManagedWindowRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: values
        )
        return try ManagedWindowRecord.require(db, uuid: row.uuid)
    }

    /// The mirrored columns of one window upsert.
    ///
    /// - Parameter upsert: The window as the mirror saw it.
    /// - Returns: The columns to insert or update.
    private func windowValues(_ upsert: ManagedWindowUpsert) -> ColumnValues {
        [
            "workspace_code": upsert.workspaceCode,
            "title": upsert.title,
            "column_index": upsert.columnIndex,
            "column_weight": upsert.columnWeight,
            "is_floating": upsert.isFloating,
            "frame_x": upsert.frameX,
            "frame_y": upsert.frameY,
            "frame_width": upsert.frameWidth,
            "frame_height": upsert.frameHeight,
            "pre_park_x": upsert.preParkX,
            "pre_park_y": upsert.preParkY,
            "pre_park_width": upsert.preParkWidth,
            "pre_park_height": upsert.preParkHeight,
        ]
    }

    /// The upsert that would reproduce a stored window, for change detection.
    ///
    /// - Parameters:
    ///   - row: The stored window.
    ///   - process: The owning process's identity.
    /// - Returns: The stored window in upsert form.
    private func mirrored(_ row: ManagedWindowRecord, process: AppProcessIdentity) -> ManagedWindowUpsert {
        ManagedWindowUpsert(
            process: process,
            cgWindowId: Int64(row.cgWindowId),
            workspaceCode: row.workspaceCode,
            title: row.title,
            columnIndex: row.columnIndex.map { Int64($0) },
            columnWeight: row.columnWeight,
            isFloating: row.isFloating,
            frameX: row.frameX,
            frameY: row.frameY,
            frameWidth: row.frameWidth,
            frameHeight: row.frameHeight,
            preParkX: row.preParkX,
            preParkY: row.preParkY,
            preParkWidth: row.preParkWidth,
            preParkHeight: row.preParkHeight
        )
    }

    /// Soft-deletes a window unless it is already retired.
    ///
    /// - Parameters:
    ///   - row: The window to retire.
    ///   - now: The ISO-8601 stamp for `deleted_on`.
    /// - Throws: Database errors.
    private func retireWindow(_ row: ManagedWindowRecord, at now: String) throws {
        guard row.deletedOn == nil else { return }
        try core.updateBase(
            db,
            table: ManagedWindowRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: ["deleted_on": now]
        )
    }

    /// Marks a process stopped and soft-deleted, retiring its live windows with it.
    ///
    /// - Parameters:
    ///   - row: The process to retire.
    ///   - now: The ISO-8601 stamp for `deleted_on`.
    /// - Throws: Database errors.
    private func retireProcess(_ row: AppProcessRecord, at now: String) throws {
        for window in try liveWindows(processUuids: [row.uuid]) {
            try retireWindow(window, at: now)
        }
        guard row.deletedOn == nil else { return }
        try core.updateBase(
            db,
            table: AppProcessRecord.databaseTableName,
            uuid: row.uuid,
            expectedVersion: row.version,
            set: ["is_running": false, "deleted_on": now]
        )
    }

    /// Retires every process not in `live` and returns the parked windows left behind by a crash.
    ///
    /// - Parameters:
    ///   - machineUuid: The machine being booted.
    ///   - live: The identities of the processes running now.
    /// - Returns: The surviving live windows whose pre-park frame is set, the crash-restore candidates.
    /// - Throws: Database errors.
    func reconcileAtBoot(machineUuid: String, live: [AppProcessIdentity]) throws -> [ManagedWindowRecord] {
        let running = Set(live)
        let now = StoreCore.isoNow()
        var survivors: [String] = []
        for process in try liveProcesses(machineUuid: machineUuid) {
            if running.contains(process.identity) {
                survivors.append(process.uuid)
            } else {
                try retireProcess(process, at: now)
            }
        }
        return try liveWindows(processUuids: survivors).filter { $0.preParkX != nil }
    }
}
