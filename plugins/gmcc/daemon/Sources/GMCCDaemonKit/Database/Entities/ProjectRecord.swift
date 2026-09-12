// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `project` table. Columns map via convertFromSnakeCase.
struct ProjectRecord: BaseRecordFields {
    static let databaseTableName = "project"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var gitRepoName: String
    var code: String
    var name: String
    var ckfsRelativeStoragePath: String
    var primaryProjectBranch: String
}

extension ProjectRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ProjectRow {
        ProjectRow(
            uuid: uuid,
            version: version,
            gitRepoName: gitRepoName,
            code: code,
            name: name,
            ckfsRelativeStoragePath: ckfsRelativeStoragePath,
            primaryProjectBranch: primaryProjectBranch,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
