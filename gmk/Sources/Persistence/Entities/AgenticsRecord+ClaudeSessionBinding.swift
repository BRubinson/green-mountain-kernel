// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `claude_session_binding` table (m0026).
///
/// Columns map via convertFromSnakeCase.
///
/// Two payload columns and no more: `claude_session_id` is Claude Code's
/// conversation uuid, `session_uuid` the gmcc session it was pinned to. A
/// UNIQUE index on `claude_session_id` carries the pin-once rule, so the table
/// holds at most one row per conversation.
struct ClaudeSessionBindingRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "claude_session_binding"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var claudeSessionId: String
    var sessionUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case claudeSessionId = "claude_session_id"
        case sessionUuid = "session_uuid"
    }
}

extension ClaudeSessionBindingRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")
}
