// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_cog` table. Columns map via convertFromSnakeCase.
struct DopeCogRecord: BaseRecordFields, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_cog"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopeScopeUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var contentRevision: Int64
    var deletedOn: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopeScopeUuid = "dope_scope_uuid"
        case code
        case name
        case description
        case sortOrder = "sort_order"
        case contentRevision = "content_revision"
        case deletedOn = "deleted_on"
    }
}

extension DopeCogRecord {
    static let scope = belongsTo(DopeScopeRecord.self).forKey("scope")
    static let elements = hasMany(DopeCogElementRecord.self)
        .order(Column("sort_order"))
        .forKey("elements")
}
