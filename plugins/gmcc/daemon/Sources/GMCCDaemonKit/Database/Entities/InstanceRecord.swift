// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `instance` table. Columns map via convertFromSnakeCase.
struct InstanceRecord: BaseRecordFields {
    static let databaseTableName = "instance"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var code: String
    var name: String
    var absoluteFileSystemPath: String
    var ckfsRelativeStoragePath: String
}

extension InstanceRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> InstanceRow {
        InstanceRow(
            uuid: uuid,
            version: version,
            projectUuid: projectUuid,
            code: code,
            name: name,
            absoluteFileSystemPath: absoluteFileSystemPath,
            ckfsRelativeStoragePath: ckfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
