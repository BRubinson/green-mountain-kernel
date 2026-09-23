// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `session_file` table.
///
/// Columns map via convertFromSnakeCase.
struct SessionFileRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "session_file"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var relativePath: String
    var active: Bool

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case relativePath = "relative_path"
        case active
    }
}

extension SessionFileRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")
    static let fileChanges = hasMany(FileChangeRecord.self).forKey("fileChanges")
}
