// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

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
