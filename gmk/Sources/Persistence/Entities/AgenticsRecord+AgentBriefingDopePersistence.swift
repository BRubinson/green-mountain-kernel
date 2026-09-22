// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `agent_briefing_dope_persistence` (dot-path CODES).
struct AgentBriefingDopePersistenceRecord: BaseRecordFields {
    static let databaseTableName = "agent_briefing_dope_persistence"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var dopeCode: String
    var brief: String?
    var seq: Int64
}

extension AgentBriefingDopePersistenceRecord {
    func wireRow() -> AgentBriefingDopeRefRow {
        AgentBriefingDopeRefRow(uuid: uuid, dopeCode: dopeCode, brief: brief, seq: Int(seq))
    }
}
