import Foundation
import GRDB

/// Read-side mirror of the `session_active_kbite` table.
///
/// Columns map via convertFromSnakeCase.
struct SessionActiveKbiteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "session_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var kbiteUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case kbiteUuid = "kbite_uuid"
    }
}

extension SessionActiveKbiteRecord {
    static let kbite = belongsTo(KbiteRecord.self)
        .forKey("kbite")
    static let session = belongsTo(SessionRecord.self)
        .forKey("session")
}
