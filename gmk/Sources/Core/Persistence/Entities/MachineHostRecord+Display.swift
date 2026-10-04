import Foundation
import GRDB

/// Read-side mirror of the `display` table: every monitor the machine has seen.
///
/// Identity is `(machineUuid, stableKey)`; rows outlive an unplug so workstation placements survive.
/// Frames are global Cocoa coordinates.
struct DisplayRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "display"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case machineUuid = "machine_uuid"
        case stableKey = "stable_key"
        case name
        case isBuiltin = "is_builtin"
        case cgDisplayId = "cg_display_id"
        case frameX = "frame_x"
        case frameY = "frame_y"
        case frameWidth = "frame_width"
        case frameHeight = "frame_height"
        case visibleX = "visible_x"
        case visibleY = "visible_y"
        case visibleWidth = "visible_width"
        case visibleHeight = "visible_height"
        case isConnected = "is_connected"
        case lastSeenAt = "last_seen_at"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case backingScale = "backing_scale"
        case physicalWidthMm = "physical_width_mm"
        case physicalHeightMm = "physical_height_mm"
        case refreshHz = "refresh_hz"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var machineUuid: String
    /// The `CGDisplayCreateUUIDFromDisplayID` string.
    var stableKey: String
    var name: String
    var isBuiltin: Bool
    /// The session's `CGDirectDisplayID`; rewritten on every enumeration and never used as identity.
    var cgDisplayId: Int64?
    var frameX: Double?
    var frameY: Double?
    var frameWidth: Double?
    var frameHeight: Double?
    var visibleX: Double?
    var visibleY: Double?
    var visibleWidth: Double?
    var visibleHeight: Double?
    var isConnected: Bool
    var lastSeenAt: String?
    /// Native pixel width of the current display mode.
    var pixelWidth: Int?
    /// Native pixel height of the current display mode.
    var pixelHeight: Int?
    /// Points-to-pixels factor of the screen; 2 on Retina.
    var backingScale: Double?
    /// Physical width in millimetres; nil when EDID reports zero.
    var physicalWidthMm: Double?
    /// Physical height in millimetres; nil when EDID reports zero.
    var physicalHeightMm: Double?
    /// Refresh rate in hertz.
    var refreshHz: Double?
}

extension DisplayRecord {
    static let machine = belongsTo(MachineRecord.self).forKey("machine")
}
