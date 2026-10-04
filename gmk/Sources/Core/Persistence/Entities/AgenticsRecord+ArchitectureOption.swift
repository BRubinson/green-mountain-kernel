import Foundation
import GRDB

/// Read-side mirror of the `architecture_option` table (m0025 pen
/// inversion).
///
/// Columns map via convertFromSnakeCase.
struct ArchitectureOptionRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "architecture_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var agentName: String
    var agentId: String?
    var body: String
    var status: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case architectureSummaryUuid = "architecture_summary_uuid"
        case agentName = "agent_name"
        case agentId = "agent_id"
        case body
        case status
    }
}

extension ArchitectureOptionRecord {
    static let summary = belongsTo(ArchitectureSummaryRecord.self).forKey("summary")
}
