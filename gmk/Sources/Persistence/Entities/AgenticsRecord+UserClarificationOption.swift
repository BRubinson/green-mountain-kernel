// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `user_clarification_option`.
struct UserClarificationOptionRecord: BaseRecordFields {
    static let databaseTableName = "user_clarification_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var questionUuid: String
    var seq: Int64
    var body: String
}

extension UserClarificationOptionRecord {
    func wireRow() -> ClarificationOptionRow {
        ClarificationOptionRow(uuid: uuid, seq: seq, body: body)
    }
}
