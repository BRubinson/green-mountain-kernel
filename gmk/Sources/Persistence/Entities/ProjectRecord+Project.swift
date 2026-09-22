// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `project` table. Columns map via convertFromSnakeCase.
struct ProjectRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "project"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case gitRepoName = "git_repo_name"
        case code = "code"
        case name = "name"
        case gmfsRelativeStoragePath = "gmfs_relative_storage_path"
        case primaryProjectBranch = "primary_project_branch"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var gitRepoName: String
    var code: String
    var name: String
    var gmfsRelativeStoragePath: String
    var primaryProjectBranch: String
}

extension ProjectRecord {
    static let instances = hasMany(InstanceRecord.self).forKey("instances")

    static let activeKbites = hasMany(
        KbiteRecord.self,
        through: hasMany(ProjectActiveKbiteRecord.self).forKey("projectActiveKbites"),
        using: ProjectActiveKbiteRecord.kbite
    )
    .forKey("activeKbites")

    static let diagrams = hasMany(DiagramRecord.self).forKey("diagrams")

    static let dopeScopes = hasMany(DopeScopeRecord.self).forKey("dopeScopes")
}
