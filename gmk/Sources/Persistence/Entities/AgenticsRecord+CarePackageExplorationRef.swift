// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `care_package_exploration_ref` (curated copies).
struct CarePackageExplorationRefRecord: BaseRecordFields {
    static let databaseTableName = "care_package_exploration_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var curatedTitle: String
    var curatedBody: String
    var filePath: String?
    var sourceFindingUuid: String?
    var seq: Int64
}

extension CarePackageExplorationRefRecord {
    func wireRow() -> CarePackageExplorationRefRow {
        CarePackageExplorationRefRow(
            uuid: uuid,
            curatedTitle: curatedTitle,
            curatedBody: curatedBody,
            filePath: filePath,
            sourceFindingUuid: sourceFindingUuid,
            seq: Int(seq)
        )
    }
}
