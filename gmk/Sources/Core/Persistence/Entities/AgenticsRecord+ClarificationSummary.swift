import Foundation
import GRDB

/// Read-side mirror of the `clarification_summary` table (slimmed —
/// backstory_note/refined_goal/refined_detail are gone; clarified intent
/// lives on the care package).
///
/// Columns map via convertFromSnakeCase.
struct ClarificationSummaryRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "clarification_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case status
    }
}

extension ClarificationSummaryRecord {
    static let questions = hasMany(UserClarificationQuestionRecord.self)
        .order(Column("seq"))
        .forKey("questions")
    static let notes = hasMany(InternalClarificationNoteRecord.self).forKey("notes")
    static let carePackage = hasOne(CarePackageRecord.self).forKey("carePackage")
}
