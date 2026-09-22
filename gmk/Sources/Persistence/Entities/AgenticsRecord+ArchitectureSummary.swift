// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_summary` table. Columns map via convertFromSnakeCase.
struct ArchitectureSummaryRecord: BaseRecordFields {
    static let databaseTableName = "architecture_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var body: String
    var status: String
    var decisionRationale: String
}

extension ArchitectureSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ArchitectureSummaryRow {
        ArchitectureSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            body: body,
            status: status,
            decisionRationale: decisionRationale,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
