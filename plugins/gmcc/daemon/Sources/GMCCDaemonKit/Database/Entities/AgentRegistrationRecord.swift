// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `agent_registration` table. Columns map via
/// convertFromSnakeCase.
///
/// Every column but agent_id is optional because the row is written by two
/// parties that never coordinate — the identity half from a payload, the
/// authority half from the spawner — and either may arrive first.
struct AgentRegistrationRecord: BaseRecordFields {
    static let databaseTableName = "agent_registration"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var agentId: String
    var claudeSessionId: String?
    var claudeTurnId: String?
    var sessionUuid: String?
    var promptUuid: String?
    var agentType: String?
    var role: String?
    var methodology: String?
    var workflowPhase: String?
}

extension AgentRegistrationRecord {
    /// db → wire. Total and nullary: every field is already on the row.
    func wireRow() -> AgentRegistrationRow {
        AgentRegistrationRow(
            uuid: uuid,
            version: version,
            agentId: agentId,
            claudeSessionId: claudeSessionId,
            claudeTurnId: claudeTurnId,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            agentType: agentType,
            role: role,
            methodology: methodology,
            workflowPhase: workflowPhase,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}
