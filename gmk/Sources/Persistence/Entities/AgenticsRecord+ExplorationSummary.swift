// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `exploration_summary` table (m0025: literal
/// per-agent rows keyed UNIQUE(prompt_uuid, agent_type); the prompt-level
/// synthesis/seal is the row with agent_type='synthesis').
struct ExplorationSummaryRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "exploration_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var agentType: String
    var agentId: String?
    var status: String
    var overview: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case agentType = "agent_type"
        case agentId = "agent_id"
        case status
        case overview
    }
}

extension ExplorationSummaryRecord {
    static let findings = hasMany(ExplorationFindingRecord.self).forKey("findings")
}
