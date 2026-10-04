import Foundation
import GRDB

/// Read-side mirror of `user_clarification_answer` (selection junction).
struct UserClarificationAnswerRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "user_clarification_answer"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var questionUuid: String
    var optionUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case questionUuid = "question_uuid"
        case optionUuid = "option_uuid"
    }
}

extension UserClarificationAnswerRecord {
    static let question = belongsTo(UserClarificationQuestionRecord.self).forKey("question")
    static let option = belongsTo(UserClarificationOptionRecord.self).forKey("option")
}
