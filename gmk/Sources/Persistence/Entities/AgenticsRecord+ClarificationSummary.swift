// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `clarification_summary` table (m0025: slimmed —
/// backstory_note/refined_goal/refined_detail are gone; clarified intent
/// lives on the care package). Columns map via convertFromSnakeCase.
struct ClarificationSummaryRecord: BaseRecordFields {
    static let databaseTableName = "clarification_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
}

extension ClarificationSummaryRecord {
    /// db → wire.
    func wireRow() -> ClarificationSummaryRow {
        ClarificationSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
