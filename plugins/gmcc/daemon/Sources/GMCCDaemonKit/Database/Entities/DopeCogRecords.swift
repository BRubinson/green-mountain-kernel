// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_cog` table. Columns map via convertFromSnakeCase.
struct DopeCogRecord: BaseRecordFields {
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
}

/// Read-side mirror of the `dope_cog_element` table. Columns map via convertFromSnakeCase.
struct DopeCogElementRecord: BaseRecordFields {
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
}

/// Read-side mirror of the `dope_cog_hull` table. Columns map via convertFromSnakeCase.
struct DopeCogHullRecord: BaseRecordFields {
    static let databaseTableName = "dope_cog_hull"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var primaryPath: String
}

/// Read-side mirror of the `dope_cog_persistence_owner` table. Columns map via convertFromSnakeCase.
struct DopeCogPersistenceOwnerRecord: BaseRecordFields {
    static let databaseTableName = "dope_cog_persistence_owner"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var dopePersistenceCode: String
}
