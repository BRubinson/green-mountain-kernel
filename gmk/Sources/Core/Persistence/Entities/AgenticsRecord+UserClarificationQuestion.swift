import Foundation
import GRDB

/// Read-side mirror of `user_clarification_question`.
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
