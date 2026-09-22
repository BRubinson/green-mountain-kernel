// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `bot_workflow` table (m0025): the daemon-held
/// workflow state machine row. Deliberately thin — phase is DERIVED from db
/// evidence at every BOT_NEXT; last_served_phase is observability only.
struct BotWorkflowRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "bot_workflow"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String
    var variant: String
    var status: String
    var clientKey: String?
    var lastServedPhase: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case variant
        case status
        case clientKey = "client_key"
        case lastServedPhase = "last_served_phase"
    }
}
