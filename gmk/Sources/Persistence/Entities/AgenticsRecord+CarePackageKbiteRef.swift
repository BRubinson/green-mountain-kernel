// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `care_package_kbite_ref`.
struct CarePackageKbiteRefRecord: BaseRecordFields {
    static let databaseTableName = "care_package_kbite_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var kbiteResourceFileUuid: String
    var brief: String?
    var seq: Int64
}

extension CarePackageKbiteRefRecord {
    func wireRow() -> CarePackageKbiteRefRow {
        CarePackageKbiteRefRow(
            uuid: uuid,
            kbiteResourceFileUuid: kbiteResourceFileUuid,
            brief: brief,
            seq: Int(seq)
        )
    }
}
