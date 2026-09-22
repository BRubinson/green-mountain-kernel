// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `review_summary` table. Columns map via convertFromSnakeCase.
struct ReviewSummaryRecord: BaseRecordFields {
    static let databaseTableName = "review_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
    var verdict: String?
    var overview: String
    var agentId: String?
}

extension ReviewSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ReviewSummaryRow {
        ReviewSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            verdict: verdict,
            overview: overview,
            agentId: agentId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
