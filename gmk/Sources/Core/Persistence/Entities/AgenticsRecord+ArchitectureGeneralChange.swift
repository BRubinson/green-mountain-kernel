import Foundation
import GRDB

/// Read-side mirror of the `architecture_general_change` table.
///
/// Columns map via convertFromSnakeCase.
struct ArchitectureGeneralChangeRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "architecture_general_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var filePath: String
    var className: String?
    var reasonBrief: String
    var changeDepth: String
    var changeCode: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case architectureSummaryUuid = "architecture_summary_uuid"
        case seq
        case filePath = "file_path"
        case className = "class_name"
        case reasonBrief = "reason_brief"
        case changeDepth = "change_depth"
        case changeCode = "change_code"
    }
}

extension ArchitectureGeneralChangeRecord {
    static let summary = belongsTo(ArchitectureSummaryRecord.self).forKey("summary")
}
