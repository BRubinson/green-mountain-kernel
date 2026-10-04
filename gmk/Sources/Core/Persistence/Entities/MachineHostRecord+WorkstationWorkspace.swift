import Foundation
import GRDB

/// Read-side mirror of the `workstation_workspace` table: where one global code sits in a workstation.
///
/// Each workstation holds one row per code. At most one row per `(workstationUuid, displayUuid)` is
/// active, so deactivations are written before activations inside one transaction.
struct WorkstationWorkspaceRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "workstation_workspace"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case workstationUuid = "workstation_uuid"
        case workspaceCode = "workspace_code"
        case displayUuid = "display_uuid"
        case isActive = "is_active"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var workstationUuid: String
    /// One of the global workspace codes.
    var workspaceCode: String
    /// The member display this code is placed on.
    var displayUuid: String
    /// True for the code currently visible on its display.
    var isActive: Bool
}

extension WorkstationWorkspaceRecord {
    static let workstation = belongsTo(WorkstationRecord.self).forKey("workstation")

    static let display = belongsTo(DisplayRecord.self).forKey("display")
}
