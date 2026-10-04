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
