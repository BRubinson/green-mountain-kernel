// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

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
