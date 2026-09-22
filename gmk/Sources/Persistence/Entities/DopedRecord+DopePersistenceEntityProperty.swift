// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_persistence_entity_property` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEntityPropertyRecord: DopeNodeRecord, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_persistence_entity_property"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceEntityUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var dataType: String
    var nullable: Bool
    var isUnique: Bool
    var autoIncrement: Bool?
    var textCharLimit: Int64?
    var dopePersistenceEnumUuid: String?
    var relationshipTargetUuid: String?
    var baseOriginPropertyUuid: String?
    var deletedOn: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopePersistenceEntityUuid = "dope_persistence_entity_uuid"
        case code
        case name
        case description
        case sortOrder = "sort_order"
        case dataType = "data_type"
        case nullable
        case isUnique = "is_unique"
        case autoIncrement = "auto_increment"
        case textCharLimit = "text_char_limit"
        case dopePersistenceEnumUuid = "dope_persistence_enum_uuid"
        case relationshipTargetUuid = "relationship_target_uuid"
        case baseOriginPropertyUuid = "base_origin_property_uuid"
        case deletedOn = "deleted_on"
    }
}

extension DopePersistenceEntityPropertyRecord {
    static let entity = belongsTo(DopePersistenceEntityRecord.self).forKey("entity")
    static let dopeEnum = belongsTo(DopePersistenceEnumRecord.self).forKey("dopeEnum")

    /// Two self-FKs share this destination, so inference would trap: name the column.
    static let relationshipTarget = belongsTo(
        DopePersistenceEntityPropertyRecord.self,
        using: ForeignKey([Column("relationship_target_uuid")])
    )
    .forKey("relationshipTarget")

    static let baseOriginProperty = belongsTo(
        DopePersistenceEntityPropertyRecord.self,
        using: ForeignKey([Column("base_origin_property_uuid")])
    )
    .forKey("baseOriginProperty")
}
