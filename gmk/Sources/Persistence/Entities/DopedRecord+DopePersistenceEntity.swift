// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_persistence_entity` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEntityRecord: DopeNodeRecord, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_persistence_entity"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceUuid: String
    var code: String
    var name: String
    var entityType: String
    var description: String
    var sortOrder: Int64
    var repoRepresentativeFile: String?
    var baseComposableUuid: String?
    var deletedOn: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopePersistenceUuid = "dope_persistence_uuid"
        case code
        case name
        case entityType = "entity_type"
        case description
        case sortOrder = "sort_order"
        case repoRepresentativeFile = "repo_representative_file"
        case baseComposableUuid = "base_composable_uuid"
        case deletedOn = "deleted_on"
    }
}

extension DopePersistenceEntityRecord {
    static let dopePersistence = belongsTo(DopePersistenceRecord.self).forKey("dopePersistence")
    static let properties = hasMany(DopePersistenceEntityPropertyRecord.self)
        .order(Column("sort_order"))
        .forKey("properties")
    static let baseComposable = belongsTo(DopePersistenceEntityRecord.self)
        .forKey("baseComposable")
}
