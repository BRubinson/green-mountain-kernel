import Foundation
import GRDB

/// Read-side mirror of the `workstation_display` table: one member display of a workstation.
///
/// `position` is fixed at creation: 0 is the seed display and the rest run left to right.
struct WorkstationDisplayRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "workstation_display"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case workstationUuid = "workstation_uuid"
        case displayUuid = "display_uuid"
        case position
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var workstationUuid: String
    var displayUuid: String
    /// Grid column order within the workstation; 0 is the seed display.
    var position: Int
}

extension WorkstationDisplayRecord {
    static let workstation = belongsTo(WorkstationRecord.self).forKey("workstation")

    static let display = belongsTo(DisplayRecord.self).forKey("display")
}
