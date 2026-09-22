// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `internal_clarification_note`.
struct InternalClarificationNoteRecord: BaseRecordFields {
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
}

extension InternalClarificationNoteRecord {
    func wireRow() -> ClarificationNoteRow {
        ClarificationNoteRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            body: body,
            confusedEntityUuid: confusedEntityUuid,
            confusedEntityType: confusedEntityType,
            weight: weight.map(Int.init),
            questionUuid: questionUuid,
            agentId: agentId,
            agentName: agentName
        )
    }
}
