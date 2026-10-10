import Foundation

// The machine_host facades: the app's window manager reads and writes its
// eight tables only through these. No verb reaches them. Bodies live in
// MachineHostRepository; these wrappers own the transaction.

extension Store {
    /// The machine carrying `hardwareUuid`, created with window management off when absent.
    /// - Parameters:
    ///   - hardwareUuid: The IOPlatformUUID; stays in the db.
    ///   - name: The human name, used only on create.
    ///   - code: The short code, used only on create.
    /// - Returns: The machine row.
    /// - Throws: `StoreError` if the write fails.
    func machineHostEnsureMachine(hardwareUuid: String, name: String, code: String) throws -> MachineRow {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .ensureMachine(hardwareUuid: hardwareUuid, name: name, code: code).dto()
        }
    }

    /// Turns window management on or off for a machine at the version the caller read.
    /// - Parameters:
    ///   - machineUuid: The machine to change.
    ///   - enabled: The new value of the flag.
    ///   - expectedVersion: The version the caller last read.
    /// - Returns: The machine row after the write.
    /// - Throws: `StoreError.notFound` or `StoreError.versionConflict`.
    func machineHostSetEnabled(machineUuid: String, enabled: Bool, expectedVersion: Int64) throws -> MachineRow {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .setEnabled(machineUuid: machineUuid, enabled: enabled, expectedVersion: expectedVersion).dto()
        }
    }

    /// Upserts the enumerated displays, marks the rest disconnected and mints a new set's workstation.
    /// - Parameters:
    ///   - machineUuid: The machine the displays belong to.
    ///   - displays: Every display the current enumeration reports.
    /// - Returns: All of the machine's display rows, connected or not.
    /// - Throws: `StoreError.notFound` when the machine is unknown; other store errors.
    func machineHostSyncDisplays(machineUuid: String, displays: [DisplayInput]) throws -> [DisplayRow] {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .syncDisplays(machineUuid: machineUuid, displays: displays).map { $0.dto() }
        }
    }

    /// Every live machine_host row of one machine, read in one transaction.
    /// - Parameter machineUuid: The machine to read.
    /// - Returns: The machine's snapshot.
    /// - Throws: `StoreError.notFound` when the machine is unknown; other store errors.
    func machineHostLoad(machineUuid: String) throws -> MachineHostSnapshotRow {
        try boundaryRead { db in
            try MachineHostRepository(db: db, core: core).loadSnapshot(machineUuid: machineUuid)
        }
    }

    /// Moves a workspace code to another member display of a workstation, inactive there.
    /// - Parameters:
    ///   - workstationUuid: The workstation whose placement changes.
    ///   - code: The workspace code to move.
    ///   - displayUuid: The member display it moves to.
    /// - Returns: The code's placement row after the write.
    /// - Throws: `MachineHostError.unknownWorkspaceCode`, `.displayNotInWorkstation` or `.wouldStrandDisplay`;
    ///   `StoreError.notFound` for an unknown workstation; other store errors.
    func machineHostAssignWorkspace(
        workstationUuid: String,
        code: String,
        displayUuid: String
    ) throws
        -> WorkstationWorkspaceRow
    {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .assignWorkspace(workstationUuid: workstationUuid, code: code, displayUuid: displayUuid).dto()
        }
    }

    /// Makes a workspace code the visible one on a display of a workstation.
    /// - Parameters:
    ///   - workstationUuid: The workstation to switch within.
    ///   - displayUuid: The display to switch.
    ///   - code: The workspace code to show; it must already be placed on `displayUuid`.
    /// - Returns: Every placement row on the display after the switch.
    /// - Throws: `MachineHostError.codeNotOnDisplay`; other store errors.
    func machineHostSetActiveWorkspace(
        workstationUuid: String,
        displayUuid: String,
        code: String
    ) throws
        -> [WorkstationWorkspaceRow]
    {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .setActiveWorkspace(workstationUuid: workstationUuid, displayUuid: displayUuid, code: code)
                .map { $0.dto() }
        }
    }

    /// Renames a workstation at the version the caller read.
    /// - Parameters:
    ///   - uuid: The workstation to rename.
    ///   - name: The new name.
    ///   - expectedVersion: The version the caller last read.
    /// - Returns: The workstation row after the write.
    /// - Throws: `StoreError.notFound` or `StoreError.versionConflict`.
    func machineHostRenameWorkstation(uuid: String, name: String, expectedVersion: Int64) throws -> WorkstationRow {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .renameWorkstation(uuid: uuid, name: name, expectedVersion: expectedVersion).dto()
        }
    }

    /// Deletes an inactive workstation at the version the caller read, with its members and placements.
    /// - Parameters:
    ///   - uuid: The workstation to forget.
    ///   - expectedVersion: The version the caller last read.
    /// - Throws: `MachineHostError.cannotForgetActiveWorkstation`; `StoreError.notFound` or
    ///   `StoreError.versionConflict`.
    func machineHostForgetWorkstation(uuid: String, expectedVersion: Int64) throws {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .forgetWorkstation(uuid: uuid, expectedVersion: expectedVersion)
        }
    }

    /// Writes one mirror tick in a single transaction.
    /// - Parameter batch: The process and window upserts and the retire lists.
    /// - Returns: The process and window rows the tick inserted or changed.
    /// - Throws: `MachineHostError.unknownProcess`; `StoreError.notFound` for an unknown retire uuid.
    func machineHostMirrorFlush(_ batch: MirrorBatch) throws -> MirrorFlushRow {
        try boundary { db in try MachineHostRepository(db: db, core: core).applyMirrorBatch(batch) }
    }

    /// Retires every process not running now and returns the parked windows a crash left behind.
    /// - Parameters:
    ///   - machineUuid: The machine being booted.
    ///   - live: The identities of the processes running now.
    /// - Returns: The surviving windows whose pre-park frame is set.
    /// - Throws: `StoreError` if the write fails.
    func machineHostReconcileMirror(machineUuid: String, live: [AppProcessIdentity]) throws -> [ManagedWindowRow] {
        try boundary { db in
            try MachineHostRepository(db: db, core: core).reconcileAtBoot(machineUuid: machineUuid, live: live)
                .map { $0.dto() }
        }
    }

    /// Sets the tile or float rule for one app on a machine, inserting it or updating it in place.
    /// - Parameters:
    ///   - machineUuid: The machine the rule belongs to.
    ///   - bundleId: The app's bundle identifier.
    ///   - appName: The app's display name, refreshed on every write.
    ///   - disposition: Whether the app's windows tile or float.
    /// - Returns: The rule row after the write.
    /// - Throws: `StoreError.notFound` when the machine is unknown; other store errors.
    func machineHostSetWindowRule(
        machineUuid: String,
        bundleId: String,
        appName: String,
        disposition: WindowRuleDisposition
    ) throws
        -> WindowRuleRow
    {
        try boundary { db in
            try MachineHostRepository(db: db, core: core)
                .setWindowRule(machineUuid: machineUuid, bundleId: bundleId, appName: appName, disposition: disposition)
                .dto()
        }
    }

    /// Deletes the rule for one app on a machine, so the classifier decides again; absent is a no-op.
    /// - Parameters:
    ///   - machineUuid: The machine the rule belongs to.
    ///   - bundleId: The app's bundle identifier.
    /// - Throws: `StoreError.versionConflict`; other store errors.
    func machineHostClearWindowRule(machineUuid: String, bundleId: String) throws {
        try boundary { db in
            try MachineHostRepository(db: db, core: core).clearWindowRule(machineUuid: machineUuid, bundleId: bundleId)
        }
    }
}
