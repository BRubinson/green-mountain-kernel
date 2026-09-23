// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_artifact` table.
///
/// Columns map via convertFromSnakeCase.
struct PromptArtifactRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_artifact"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var filePath: String
    var note: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case filePath = "file_path"
        case note
    }
}

extension PromptArtifactRecord {
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
}
