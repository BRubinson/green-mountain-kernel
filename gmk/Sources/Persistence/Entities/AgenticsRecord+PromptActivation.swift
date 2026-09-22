// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_activation` table. Columns map via convertFromSnakeCase.
struct PromptActivationRecord: BaseRecordFields {
    static let databaseTableName = "prompt_activation"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String
    var clientKey: String
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
