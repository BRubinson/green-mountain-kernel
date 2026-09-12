// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `agent_briefing` table (m0025 shape: opinion-free
/// ref set — body/dope_refs/kbite_refs TEXT columns are gone, refs are child
/// rows). Columns map via convertFromSnakeCase.
struct AgentBriefingRecord: BaseRecordFields {
    static let databaseTableName = "agent_briefing"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String?
    var briefingForStep: String
    var status: String
    var agentId: String?
    var dopeScopeUuid: String?
    var dopeScopeRevision: Int64?
}

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

/// Read-side mirror of `agent_briefing_dope_kbite` (uuid FK + denorm brief).
struct AgentBriefingDopeKbiteRecord: BaseRecordFields {
    static let databaseTableName = "agent_briefing_dope_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var kbiteResourceFileUuid: String
    var brief: String?
    var seq: Int64
}

/// Read-side mirror of `agent_session_file_change` (uuid FK).
struct AgentSessionFileChangeRecord: BaseRecordFields {
    static let databaseTableName = "agent_session_file_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var fileChangeUuid: String
    var seq: Int64
}

extension AgentBriefingRecord {
    /// db → wire. The children are fetched by the repository and injected —
    /// the record itself stays a plain single-table mirror.
    func wireRow(
        dopeRefs: [AgentBriefingDopeRefRow],
        kbiteRefs: [AgentBriefingKbiteRefRow],
        fileChangeRefs: [AgentBriefingFileChangeRefRow]
    ) -> AgentBriefingRow {
        AgentBriefingRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            briefingForStep: briefingForStep,
            status: status,
            agentId: agentId,
            dopeScopeUuid: dopeScopeUuid,
            dopeScopeRevision: dopeScopeRevision,
            dopeRefs: dopeRefs,
            kbiteRefs: kbiteRefs,
            fileChangeRefs: fileChangeRefs,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

extension AgentBriefingDopePersistenceRecord {
    func wireRow() -> AgentBriefingDopeRefRow {
        AgentBriefingDopeRefRow(uuid: uuid, dopeCode: dopeCode, brief: brief, seq: Int(seq))
    }
}

extension AgentBriefingDopeKbiteRecord {
    func wireRow() -> AgentBriefingKbiteRefRow {
        AgentBriefingKbiteRefRow(
            uuid: uuid, kbiteResourceFileUuid: kbiteResourceFileUuid, brief: brief, seq: Int(seq))
    }
}

extension AgentSessionFileChangeRecord {
    func wireRow() -> AgentBriefingFileChangeRefRow {
        AgentBriefingFileChangeRefRow(uuid: uuid, fileChangeUuid: fileChangeUuid, seq: Int(seq))
    }
}
