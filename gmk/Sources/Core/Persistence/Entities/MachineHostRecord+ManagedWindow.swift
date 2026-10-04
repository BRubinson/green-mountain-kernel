import Foundation
import GRDB

/// Read-side mirror of the `managed_window` table: one row per observed window.
///
/// Frames are global Cocoa coordinates. The pre-park frame is non-nil only while the window is
/// parked, and crash recovery reads it before falling back to geometry.
struct ManagedWindowRecord: BaseRecordFields, TableRecord, SoftDeletable {
    static let databaseTableName = "managed_window"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case appProcessUuid = "app_process_uuid"
        case workspaceCode = "workspace_code"
        case cgWindowId = "cg_window_id"
        case title
        case columnIndex = "column_index"
        case columnWeight = "column_weight"
        case isFloating = "is_floating"
        case frameX = "frame_x"
        case frameY = "frame_y"
        case frameWidth = "frame_width"
        case frameHeight = "frame_height"
        case preParkX = "pre_park_x"
        case preParkY = "pre_park_y"
        case preParkWidth = "pre_park_width"
        case preParkHeight = "pre_park_height"
        case deletedOn = "deleted_on"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var appProcessUuid: String
    /// The global workspace code the window belongs to under every workstation; nil for floating or
    /// unassigned windows.
    var workspaceCode: String?
    /// The `CGWindowID`; stable only for the life of its process.
    var cgWindowId: Int64
    var title: String?
    /// Column order in the workspace strip; nil when floating.
    var columnIndex: Int?
    /// Relative width: a column spans `visibleWidth × weight / Σweight`.
    var columnWeight: Double
    var isFloating: Bool
    var frameX: Double?
    var frameY: Double?
    var frameWidth: Double?
    var frameHeight: Double?
    var preParkX: Double?
    var preParkY: Double?
    var preParkWidth: Double?
    var preParkHeight: Double?
    var deletedOn: String?
}

extension ManagedWindowRecord {
    static let appProcess = belongsTo(AppProcessRecord.self).forKey("appProcess")
}
