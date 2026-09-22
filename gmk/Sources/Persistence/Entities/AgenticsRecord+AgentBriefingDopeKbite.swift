// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `agent_briefing_dope_kbite` (uuid FK + denorm brief).
struct AgentBriefingDopeKbiteRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "agent_briefing_dope_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var kbiteResourceFileUuid: String
    var brief: String?
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentBriefingUuid = "agent_briefing_uuid"
        case kbiteResourceFileUuid = "kbite_resource_file_uuid"
        case brief
        case seq
    }
}

extension AgentBriefingDopeKbiteRecord {
    static let briefing = belongsTo(AgentBriefingRecord.self).forKey("briefing")
}

extension AgentBriefingDopeKbiteRecord {
    func wireRow() -> AgentBriefingKbiteRefRow {
        AgentBriefingKbiteRefRow(
            uuid: uuid,
            kbiteResourceFileUuid: kbiteResourceFileUuid,
            brief: brief,
            seq: Int(seq)
        )
    }
}
