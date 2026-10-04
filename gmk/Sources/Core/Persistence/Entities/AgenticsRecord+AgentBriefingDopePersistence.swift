import Foundation
import GRDB

/// Read-side mirror of `agent_briefing_dope_persistence` (dot-path CODES).
struct AgentBriefingDopePersistenceRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "agent_briefing_dope_persistence"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentBriefingUuid: String
    var dopeCode: String
    var brief: String?
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentBriefingUuid = "agent_briefing_uuid"
        case dopeCode = "dope_code"
        case brief
        case seq
    }
}

extension AgentBriefingDopePersistenceRecord {
    static let briefing = belongsTo(AgentBriefingRecord.self).forKey("briefing")
}
