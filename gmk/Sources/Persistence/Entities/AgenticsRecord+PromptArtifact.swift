// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_artifact` table. Columns map via convertFromSnakeCase.
struct PromptArtifactRecord: BaseRecordFields {
    static let databaseTableName = "prompt_artifact"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var filePath: String
    var note: String?
}

extension PromptArtifactRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ArtifactRow {
        ArtifactRow(
            uuid: uuid,
            promptUuid: promptUuid,
            filePath: filePath,
            note: note,
            createdAt: createdAt
        )
    }
}
