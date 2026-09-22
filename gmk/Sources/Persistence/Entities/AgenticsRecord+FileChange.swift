// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `file_change` table. Columns map via convertFromSnakeCase.
struct FileChangeRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "file_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionFileUuid: String
    var sessionUuid: String
    var promptUuid: String?
    var changeKind: String
    var agentId: String?
    var agentName: String?
    var workflowPhase: String?
    var origin: String
    /// The captured tool call. claudeTurnId is Claude Code's TURN id (payload
    /// field `prompt_id`) and is NOT a gmcc prompt uuid.
    var claudeSessionId: String?
    var claudeTurnId: String?
    var toolUseId: String?
    var toolName: String?
    var agentType: String?
    var permissionMode: String?
    var durationMs: Int64?
    var transcriptPath: String?
    /// NULL for a PRIMARY write — the primary carries no agent_id at all.
    var agentRegistrationUuid: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionFileUuid = "session_file_uuid"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case changeKind = "change_kind"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case workflowPhase = "workflow_phase"
        case origin
        case claudeSessionId = "claude_session_id"
        case claudeTurnId = "claude_turn_id"
        case toolUseId = "tool_use_id"
        case toolName = "tool_name"
        case agentType = "agent_type"
        case permissionMode = "permission_mode"
        case durationMs = "duration_ms"
        case transcriptPath = "transcript_path"
        case agentRegistrationUuid = "agent_registration_uuid"
    }
}

extension FileChangeRecord {
    static let sessionFile = belongsTo(SessionFileRecord.self).forKey("sessionFile")
    static let ranges = hasMany(FileChangeRangeRecord.self).forKey("ranges")
    static let session = belongsTo(SessionRecord.self).forKey("session")
}
