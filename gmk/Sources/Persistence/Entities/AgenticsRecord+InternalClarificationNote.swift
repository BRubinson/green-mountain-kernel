// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

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
