import Foundation
import GRDB

/// Read-side mirror of the `dope_cog_persistence_owner` table.
///
/// Columns map via convertFromSnakeCase.
struct DopeCogPersistenceOwnerRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "dope_cog_persistence_owner"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var dopePersistenceCode: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case dopePersistenceCode = "dope_persistence_code"
    }
}

extension DopeCogPersistenceOwnerRecord {
    static let element = belongsTo(DopeCogElementRecord.self).forKey("element")
}
