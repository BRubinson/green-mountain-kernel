import Foundation

// Row and input shapes for the machine_host tables — what the Store facades
// return to the app's window manager and what it hands back to be written.
// Same lowering conventions as Rows.swift: camelCase here, snake_case on the
// wire. No verb carries these yet.

// MARK: - Rows

/// One physical host, keyed locally on its hardware UUID, which never leaves the db.
struct MachineRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let code: String
    let name: String
    let windowManagementEnabled: Bool
    let createdAt: String
    let updatedAt: String
}

/// One monitor the machine has ever seen, with its last known arrangement in global Cocoa coordinates.
struct DisplayRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let machineUuid: String
    let stableKey: String
    let name: String
    let isBuiltin: Bool
    let cgDisplayId: Int64?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let visibleX: Double?
    let visibleY: Double?
    let visibleWidth: Double?
    let visibleHeight: Double?
    let isConnected: Bool
    let lastSeenAt: String?
    /// When the machine first saw this display, as an ISO-8601 Z string.
    let createdAt: String
    /// Native pixel width of the current mode; nil when unread.
    let pixelWidth: Int64?
    /// Native pixel height of the current mode; nil when unread.
    let pixelHeight: Int64?
    /// Points-to-pixels factor (2 on Retina); nil when unread.
    let backingScale: Double?
    /// Physical width in millimetres; nil when EDID reports none.
    let physicalWidthMm: Double?
    /// Physical height in millimetres; nil when EDID reports none.
    let physicalHeightMm: Double?
    /// Refresh rate in hertz; nil when unread.
    let refreshHz: Double?
}

/// One connected-display set of a machine, minted on first sight and nameable.
///
/// `displaySetKey` is the sorted, comma-joined stable keys of the member displays; the workstation
/// whose key equals the connected set is the active one.
struct WorkstationRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let machineUuid: String
    let displaySetKey: String
    let name: String
    let createdAt: String
    let updatedAt: String
}

/// One member display of a workstation; `position` 0 is the seed display and the rest run left to right.
struct WorkstationDisplayRow: Codable, Hashable, Sendable {
    let uuid: String
    let workstationUuid: String
    let displayUuid: String
    let position: Int64
}

/// Where one global workspace code sits in a workstation, and whether it is the one visible there.
struct WorkstationWorkspaceRow: Codable, Hashable, Sendable {
    let uuid: String
    let workstationUuid: String
    let workspaceCode: String
    let displayUuid: String
    let isActive: Bool
}

/// A running GUI app the window manager observes, identified by `pid` together with `launchedAt`.
struct AppProcessRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let machineUuid: String
    let pid: Int64
    let launchedAt: String
    let bundleId: String?
    let name: String
    let isRunning: Bool
    let deletedOn: String?
}

/// One observed window: its workspace code, column, live frame and, while parked, its pre-park frame.
struct ManagedWindowRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let appProcessUuid: String
    let workspaceCode: String?
    let cgWindowId: Int64
    let title: String?
    let columnIndex: Int64?
    let columnWeight: Double
    let isFloating: Bool
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let preParkX: Double?
    let preParkY: Double?
    let preParkWidth: Double?
    let preParkHeight: Double?
    let deletedOn: String?
}

/// Every live machine_host row of one machine, read in one transaction.
struct MachineHostSnapshotRow: Codable, Hashable, Sendable {
    let machine: MachineRow
    let displays: [DisplayRow]
    let workstations: [WorkstationRow]
    let workstationDisplays: [WorkstationDisplayRow]
    let workstationWorkspaces: [WorkstationWorkspaceRow]
    /// The workstation whose display set equals the connected set; nil when none is connected.
    let activeWorkstationUuid: String?
    let appProcesses: [AppProcessRow]
    let managedWindows: [ManagedWindowRow]
}

/// The rows one mirror flush inserted or changed, so the writer learns their uuids.
struct MirrorFlushRow: Codable, Hashable, Sendable {
    let appProcesses: [AppProcessRow]
    let managedWindows: [ManagedWindowRow]
}

// MARK: - Inputs

/// One display as the current enumeration reports it; upserted on `stableKey` within the machine.
struct DisplayInput: Codable, Hashable, Sendable {
    let stableKey: String
    let name: String
    let isBuiltin: Bool
    let cgDisplayId: Int64?
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double
    let visibleX: Double
    let visibleY: Double
    let visibleWidth: Double
    let visibleHeight: Double
    /// Native pixel width of the current mode.
    let pixelWidth: Int64?
    /// Native pixel height of the current mode.
    let pixelHeight: Int64?
    /// Points-to-pixels factor of the screen.
    let backingScale: Double?
    /// Physical width in millimetres; nil when EDID reports zero.
    let physicalWidthMm: Double?
    /// Physical height in millimetres; nil when EDID reports zero.
    let physicalHeightMm: Double?
    /// Refresh rate in hertz.
    let refreshHz: Double?
}

/// The identity of a process within one boot of the machine; a recycled `pid` differs in `launchedAt`.
struct AppProcessIdentity: Codable, Hashable, Sendable {
    let pid: Int64
    let launchedAt: String
}

/// A live process as the mirror last saw it, upserted on its identity within the machine.
struct AppProcessUpsert: Codable, Hashable, Sendable {
    let identity: AppProcessIdentity
    let bundleId: String?
    let name: String
    let isRunning: Bool
}

/// A live window as the mirror last saw it, upserted on its process identity and `cgWindowId`.
struct ManagedWindowUpsert: Codable, Hashable, Sendable {
    let process: AppProcessIdentity
    let cgWindowId: Int64
    let workspaceCode: String?
    let title: String?
    let columnIndex: Int64?
    let columnWeight: Double
    let isFloating: Bool
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let preParkX: Double?
    let preParkY: Double?
    let preParkWidth: Double?
    let preParkHeight: Double?
}

/// One debounced mirror tick, written in a single transaction: upserts first, then retirements.
struct MirrorBatch: Codable, Hashable, Sendable {
    let machineUuid: String
    let processes: [AppProcessUpsert]
    let windows: [ManagedWindowUpsert]
    let retireProcessUuids: [String]
    let retireWindowUuids: [String]
}

// MARK: - Errors

/// A machine_host write refused for a reason the caller can branch on.
enum MachineHostError: Error, Hashable, Sendable {
    /// The code is not one of the global workspace codes.
    case unknownWorkspaceCode(String)
    /// Moving `code` off `display` would leave that display with no workspace code placed on it.
    case wouldStrandDisplay(code: String, display: String)
    /// The code is not placed on `display` in the workstation the write names.
    case codeNotOnDisplay(code: String, display: String)
    /// `display` is not a member of the workstation the write names.
    case displayNotInWorkstation(display: String)
    /// `workstation` is the active one, so forgetting it would strand the connected displays.
    case cannotForgetActiveWorkstation(workstation: String)
    /// A mirror window named a process identity with no live row on the machine.
    case unknownProcess(pid: Int64, launchedAt: String)
}
