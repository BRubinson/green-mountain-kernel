// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_cog_element` table.
///
/// Columns map via convertFromSnakeCase.
struct DopeCogElementRecord: BaseRecordFields, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_cog_element"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopeCogUuid: String
    var parentElementUuid: String?
    var elementType: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var dopeScopeCode: String?
    var deletedOn: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopeCogUuid = "dope_cog_uuid"
        case parentElementUuid = "parent_element_uuid"
        case elementType = "element_type"
        case code
        case name
        case description
        case sortOrder = "sort_order"
        case dopeScopeCode = "dope_scope_code"
        case deletedOn = "deleted_on"
    }
}

extension DopeCogElementRecord {
    static let cog = belongsTo(DopeCogRecord.self).forKey("cog")
    static let parent = belongsTo(DopeCogElementRecord.self).forKey("parent")
    static let children = hasMany(DopeCogElementRecord.self)
        .order(Column("sort_order"))
        .forKey("children")
    static let hull = hasOne(DopeCogHullRecord.self).forKey("hull")
    static let persistenceOwner = hasOne(DopeCogPersistenceOwnerRecord.self)
        .forKey("persistenceOwner")
}
