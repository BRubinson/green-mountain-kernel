// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `user_clarification_question` (m0025 split).
struct UserClarificationQuestionRecord: BaseRecordFields {
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
