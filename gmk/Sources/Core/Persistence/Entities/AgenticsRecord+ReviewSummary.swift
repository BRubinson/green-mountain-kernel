import Foundation
import GRDB

/// Read-side mirror of the `review_summary` table.
///
/// Columns map via convertFromSnakeCase.
struct ReviewSummaryRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "review_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
    var verdict: String?
    var overview: String
    var agentId: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case status
        case verdict
        case overview
        case agentId = "agent_id"
    }
}

extension ReviewSummaryRecord {
    static let findings = hasMany(ReviewFindingRecord.self).forKey("findings")
}
