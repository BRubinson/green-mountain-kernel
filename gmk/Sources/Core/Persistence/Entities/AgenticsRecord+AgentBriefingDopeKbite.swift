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
