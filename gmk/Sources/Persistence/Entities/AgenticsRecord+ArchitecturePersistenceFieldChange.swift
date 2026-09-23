// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_persistence_field_change` table.
///
/// Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceFieldChangeRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "architecture_persistence_field_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var persistenceChangeUuid: String
    var seq: Int64
    var fieldName: String
    var changeReason: String
    var changePurpose: String
    var dataType: String
    var nullable: Bool
    var isForeignKey: Bool
    var fkTarget: String?
    var isIndexed: Bool
    var changeKind: String
    var renamedFrom: String?
    var dopePropertyRef: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case persistenceChangeUuid = "persistence_change_uuid"
        case seq
        case fieldName = "field_name"
        case changeReason = "change_reason"
        case changePurpose = "change_purpose"
        case dataType = "data_type"
        case nullable
        case isForeignKey = "is_foreign_key"
        case fkTarget = "fk_target"
        case isIndexed = "is_indexed"
        case changeKind = "change_kind"
        case renamedFrom = "renamed_from"
        case dopePropertyRef = "dope_property_ref"
    }
}

extension ArchitecturePersistenceFieldChangeRecord {
    static let change = belongsTo(ArchitecturePersistenceChangeRecord.self).forKey("change")
}
