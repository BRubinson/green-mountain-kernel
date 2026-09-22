// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_activation` table. Columns map via convertFromSnakeCase.
struct PromptActivationRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_activation"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String
    var clientKey: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case clientKey = "client_key"
    }
}

extension PromptActivationRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
}

extension PromptActivationRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> PromptActivationRow {
        PromptActivationRow(
            uuid: uuid,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            clientKey: clientKey,
            createdAt: createdAt
        )
    }
}
