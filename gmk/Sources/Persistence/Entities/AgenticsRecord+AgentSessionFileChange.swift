// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `agent_session_file_change` (uuid FK).
struct AgentSessionFileChangeRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "agent_session_file_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var fileChangeUuid: String
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentBriefingUuid = "agent_briefing_uuid"
        case fileChangeUuid = "file_change_uuid"
        case seq
    }
}

extension AgentSessionFileChangeRecord {
    static let briefing = belongsTo(AgentBriefingRecord.self).forKey("briefing")
}
