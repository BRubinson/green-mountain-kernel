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
