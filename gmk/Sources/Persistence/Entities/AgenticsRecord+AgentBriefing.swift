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
struct AgentBriefingRecord: BaseRecordFields, TableRecord {
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

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case briefingForStep = "briefing_for_step"
        case status
        case agentId = "agent_id"
        case dopeScopeUuid = "dope_scope_uuid"
        case dopeScopeRevision = "dope_scope_revision"
    }
}

extension AgentBriefingRecord {
    static let dopeRefs = hasMany(AgentBriefingDopePersistenceRecord.self)
        .order(Column("seq"))
        .forKey("dopeRefs")
    static let kbiteRefs = hasMany(AgentBriefingDopeKbiteRecord.self)
        .order(Column("seq"))
        .forKey("kbiteRefs")
    static let fileChangeRefs = hasMany(AgentSessionFileChangeRecord.self)
        .order(Column("seq"))
        .forKey("fileChangeRefs")
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
            updatedAt: updatedAt
        )
    }
}
