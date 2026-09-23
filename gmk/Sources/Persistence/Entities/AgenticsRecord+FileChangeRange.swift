// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `file_change_range` table.
///
/// Columns map via convertFromSnakeCase.
struct FileChangeRangeRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "file_change_range"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var fileChangeUuid: String
    var lineStart: Int64
    var lineEnd: Int64
    var changedContent: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case fileChangeUuid = "file_change_uuid"
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case changedContent = "changed_content"
    }
}

extension FileChangeRangeRecord {
    static let fileChange = belongsTo(FileChangeRecord.self).forKey("fileChange")
}
