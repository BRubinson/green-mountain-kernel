import Foundation
import GRDB

/// Read-side mirror of `internal_clarification_note`.
struct InternalClarificationNoteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "internal_clarification_note"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var body: String
    var confusedEntityUuid: String?
    var confusedEntityType: String?
    var weight: Int64?
    var questionUuid: String?
    var agentId: String?
    var agentName: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case clarificationSummaryUuid = "clarification_summary_uuid"
        case body
        case confusedEntityUuid = "confused_entity_uuid"
        case confusedEntityType = "confused_entity_type"
        case weight
        case questionUuid = "question_uuid"
        case agentId = "agent_id"
        case agentName = "agent_name"
    }
}

extension InternalClarificationNoteRecord {
    static let summary = belongsTo(ClarificationSummaryRecord.self).forKey("summary")
}
