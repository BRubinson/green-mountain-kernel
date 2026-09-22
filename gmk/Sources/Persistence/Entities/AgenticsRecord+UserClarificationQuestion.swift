// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `user_clarification_question` (m0025 split).
struct UserClarificationQuestionRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "user_clarification_question"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var seq: Int64
    var question: String
    var status: String
    var answerText: String?
    var agentId: String?
    var agentName: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case clarificationSummaryUuid = "clarification_summary_uuid"
        case seq
        case question
        case status
        case answerText = "answer_text"
        case agentId = "agent_id"
        case agentName = "agent_name"
    }
}

extension UserClarificationQuestionRecord {
    static let options = hasMany(UserClarificationOptionRecord.self)
        .order(Column("seq"))
        .forKey("options")
    static let answers = hasMany(UserClarificationAnswerRecord.self).forKey("answers")
    static let summary = belongsTo(ClarificationSummaryRecord.self).forKey("summary")
}

extension UserClarificationQuestionRecord {
    /// db → wire. Options + selections are fetched by the repository and
    /// injected — the record stays a plain single-table mirror.
    func wireRow(
        options: [ClarificationOptionRow],
        selectedOptionUuids: [String]
    ) -> ClarificationQuestionRow {
        ClarificationQuestionRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            seq: seq,
            question: question,
            status: status,
            answerText: answerText,
            agentId: agentId,
            agentName: agentName,
            options: options,
            selectedOptionUuids: selectedOptionUuids
        )
    }
}
