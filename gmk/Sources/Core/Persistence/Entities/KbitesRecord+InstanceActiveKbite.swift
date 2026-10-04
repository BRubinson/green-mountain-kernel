import Foundation
import GRDB

/// Read-side mirror of the `instance_active_kbite` table.
///
/// Columns map via convertFromSnakeCase.
struct InstanceActiveKbiteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "instance_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var kbiteUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case instanceUuid = "instance_uuid"
        case kbiteUuid = "kbite_uuid"
    }
}

extension InstanceActiveKbiteRecord {
    static let kbite = belongsTo(KbiteRecord.self)
        .forKey("kbite")
    static let instance = belongsTo(InstanceRecord.self)
        .forKey("instance")
}
