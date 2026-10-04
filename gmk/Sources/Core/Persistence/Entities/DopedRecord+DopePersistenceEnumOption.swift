import Foundation
import GRDB

/// Read-side mirror of the `dope_persistence_enum_option` table.
///
/// Columns map via convertFromSnakeCase.
struct DopePersistenceEnumOptionRecord: DopeNodeRecord, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_persistence_enum_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceEnumUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var deletedOn: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopePersistenceEnumUuid = "dope_persistence_enum_uuid"
        case code
        case name
        case description
        case sortOrder = "sort_order"
        case deletedOn = "deleted_on"
    }
}

extension DopePersistenceEnumOptionRecord {
    static let dopeEnum = belongsTo(DopePersistenceEnumRecord.self).forKey("dopeEnum")
}
