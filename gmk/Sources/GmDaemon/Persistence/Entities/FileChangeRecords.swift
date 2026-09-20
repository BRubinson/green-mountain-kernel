// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `file_change` table. Columns map via convertFromSnakeCase.
struct FileChangeRecord: BaseRecordFields {
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
}

/// Read-side mirror of the `file_change_range` table. Columns map via convertFromSnakeCase.
struct FileChangeRangeRecord: BaseRecordFields {
    static let databaseTableName = "file_change_range"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var fileChangeUuid: String
    var lineStart: Int64
    var lineEnd: Int64
    var changedContent: String?
}
