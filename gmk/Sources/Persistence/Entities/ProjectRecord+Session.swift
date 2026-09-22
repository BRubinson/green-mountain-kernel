// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `session` table. Columns map via convertFromSnakeCase.
struct SessionRecord: BaseRecordFields {
    static let databaseTableName = "session"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var status: String
    var gmfsRelativeStoragePath: String
}

extension SessionRecord {
    /// db → wire, with the activation registry injected.
    ///
    /// Parameterized because activations are a second query against
    /// prompt_activation. Labelled and un-defaulted deliberately: SessionRow's
    /// own init defaults `activations` to [], so a nullary wireRow() that
    /// forgot them would compile and silently report every session as
    /// unclaimed.
    func wireRow(activations: [PromptActivationRow]) -> SessionRow {
        SessionRow(
            uuid: uuid,
            version: version,
            code: code,
            name: name,
            backstory: backstory,
            goal: goal,
            createdAt: createdAt,
            updatedAt: updatedAt,
            activations: activations
        )
    }
}
