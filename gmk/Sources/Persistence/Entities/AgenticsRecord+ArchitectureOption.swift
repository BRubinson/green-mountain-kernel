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
struct ArchitectureOptionRecord: BaseRecordFields, TableRecord {
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

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case architectureSummaryUuid = "architecture_summary_uuid"
        case agentName = "agent_name"
        case agentId = "agent_id"
        case body
        case status
    }
}

extension ArchitectureOptionRecord {
    static let summary = belongsTo(ArchitectureSummaryRecord.self).forKey("summary")
}
