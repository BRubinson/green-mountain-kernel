// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_option` table (m0025 pen
/// inversion). Columns map via convertFromSnakeCase.
struct ArchitectureOptionRecord: BaseRecordFields {
    static let databaseTableName = "architecture_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var agentName: String
    var agentId: String?
    var body: String
    var status: String
}

extension ArchitectureOptionRecord {
    /// db → wire.
    func wireRow() -> ArchitectureOptionRow {
        ArchitectureOptionRow(
            uuid: uuid,
            version: version,
            architectureSummaryUuid: architectureSummaryUuid,
            agentName: agentName,
            agentId: agentId,
            body: body,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
