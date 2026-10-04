import Foundation
import GRDB

/// Read-side mirror of `user_clarification_option`.
struct UserClarificationOptionRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "user_clarification_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var questionUuid: String
    var seq: Int64
    var body: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case questionUuid = "question_uuid"
        case seq
        case body
    }
}

extension UserClarificationOptionRecord {
    static let question = belongsTo(UserClarificationQuestionRecord.self).forKey("question")
}
