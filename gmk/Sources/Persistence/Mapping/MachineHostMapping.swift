// db → wire for the machine_host records.
//
// This is the only place a persistence type and a wire DTO meet. Wire types
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension MachineRecord {
    /// Converts a machine record to its wire row, leaving the hardware UUID behind.
    ///
    /// - Returns: The wire machine row.
    func dto() -> MachineRow {
        MachineRow(
            uuid: uuid,
            version: version,
            code: code,
            name: name,
            windowManagementEnabled: windowManagementEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension DisplayRecord {
    /// Converts a display record to its wire row.
    ///
    /// - Returns: The wire display row.
    func dto() -> DisplayRow {
        DisplayRow(
            uuid: uuid,
            version: version,
            machineUuid: machineUuid,
            stableKey: stableKey,
            name: name,
            isBuiltin: isBuiltin,
            cgDisplayId: cgDisplayId.map { Int64($0) },
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            visibleX: visibleX,
            visibleY: visibleY,
            visibleWidth: visibleWidth,
            visibleHeight: visibleHeight,
            isConnected: isConnected,
            lastSeenAt: lastSeenAt,
            createdAt: createdAt,
            pixelWidth: pixelWidth.map { Int64($0) },
            pixelHeight: pixelHeight.map { Int64($0) },
            backingScale: backingScale,
            physicalWidthMm: physicalWidthMm,
            physicalHeightMm: physicalHeightMm,
            refreshHz: refreshHz
        )
    }
}

extension WorkstationRecord {
    /// Converts a workstation record to its wire row.
    ///
    /// - Returns: The wire workstation row.
    func dto() -> WorkstationRow {
        WorkstationRow(
            uuid: uuid,
            version: version,
            machineUuid: machineUuid,
            displaySetKey: displaySetKey,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension WorkstationDisplayRecord {
    /// Converts a workstation membership record to its wire row.
    ///
    /// - Returns: The wire workstation-display row.
    func dto() -> WorkstationDisplayRow {
        WorkstationDisplayRow(
            uuid: uuid,
            workstationUuid: workstationUuid,
            displayUuid: displayUuid,
            position: Int64(position)
        )
    }
}

extension WorkstationWorkspaceRecord {
    /// Converts a workstation placement record to its wire row.
    ///
    /// - Returns: The wire workstation-workspace row.
    func dto() -> WorkstationWorkspaceRow {
        WorkstationWorkspaceRow(
            uuid: uuid,
            workstationUuid: workstationUuid,
            workspaceCode: workspaceCode,
            displayUuid: displayUuid,
            isActive: isActive
        )
    }
}

extension AppProcessRecord {
    /// Converts an app-process record to its wire row.
    ///
    /// - Returns: The wire app-process row.
    func dto() -> AppProcessRow {
        AppProcessRow(
            uuid: uuid,
            version: version,
            machineUuid: machineUuid,
            pid: Int64(pid),
            launchedAt: launchedAt,
            bundleId: bundleId,
            name: name,
            isRunning: isRunning,
            deletedOn: deletedOn
        )
    }

    /// The process identity this record carries, in the wire's integer width.
    var identity: AppProcessIdentity {
        AppProcessIdentity(pid: Int64(pid), launchedAt: launchedAt)
    }
}

extension ManagedWindowRecord {
    /// Converts a managed-window record to its wire row.
    ///
    /// - Returns: The wire managed-window row.
    func dto() -> ManagedWindowRow {
        ManagedWindowRow(
            uuid: uuid,
            version: version,
            appProcessUuid: appProcessUuid,
            workspaceCode: workspaceCode,
            cgWindowId: Int64(cgWindowId),
            title: title,
            columnIndex: columnIndex.map { Int64($0) },
            columnWeight: columnWeight,
            isFloating: isFloating,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            preParkX: preParkX,
            preParkY: preParkY,
            preParkWidth: preParkWidth,
            preParkHeight: preParkHeight,
            deletedOn: deletedOn
        )
    }
}
