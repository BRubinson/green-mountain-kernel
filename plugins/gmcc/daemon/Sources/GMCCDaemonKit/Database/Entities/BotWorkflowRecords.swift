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
struct BotWorkflowRecord: BaseRecordFields {
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
}

extension BotWorkflowRecord {
    /// db → wire.
    func wireRow() -> BotWorkflowRow {
        BotWorkflowRow(
            uuid: uuid, version: version, sessionUuid: sessionUuid,
            promptUuid: promptUuid, variant: variant, status: status,
            clientKey: clientKey, lastServedPhase: lastServedPhase,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
