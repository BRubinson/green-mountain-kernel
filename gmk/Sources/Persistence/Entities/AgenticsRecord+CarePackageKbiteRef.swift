// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `care_package_kbite_ref`.
struct CarePackageKbiteRefRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "care_package_kbite_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var kbiteResourceFileUuid: String
    var brief: String?
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case carePackageUuid = "care_package_uuid"
        case kbiteResourceFileUuid = "kbite_resource_file_uuid"
        case brief
        case seq
    }
}

extension CarePackageKbiteRefRecord {
    static let carePackage = belongsTo(CarePackageRecord.self).forKey("carePackage")
}
