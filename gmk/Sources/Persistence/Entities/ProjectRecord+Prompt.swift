// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt` table. Columns map via convertFromSnakeCase.
struct PromptRecord: BaseRecordFields {
    static let databaseTableName = "prompt"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var seq: Int64
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var detail: String
    var command: String
    var status: String
    var gmfsRelativeStoragePath: String
}

extension PromptRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// PromptRow IS field-for-field identical to this record, so the prompt
    /// row assembly the original plan filed under "stays hand-assembled" was
    /// a clean 1:1 all along. What genuinely stays hand-assembled is
    /// PromptGetResponse and PromptStub (the latter folds four grouped report
    /// aggregations over computed columns).
    func wireRow() -> PromptRow {
        PromptRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            seq: seq,
            code: code,
            name: name,
            backstory: backstory,
            goal: goal,
            detail: detail,
            command: command,
            status: status,
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
