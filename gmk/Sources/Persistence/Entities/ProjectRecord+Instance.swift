// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `instance` table. Columns map via convertFromSnakeCase.
struct InstanceRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "instance"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case code = "code"
        case name = "name"
        case absoluteFileSystemPath = "absolute_file_system_path"
        case gmfsRelativeStoragePath = "gmfs_relative_storage_path"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var code: String
    var name: String
    var absoluteFileSystemPath: String
    var gmfsRelativeStoragePath: String
}

extension InstanceRecord {
    static let project = belongsTo(ProjectRecord.self).forKey("project")

    static let sessions = hasMany(SessionRecord.self).forKey("sessions")

    static let activeKbites = hasMany(
        KbiteRecord.self,
        through: hasMany(InstanceActiveKbiteRecord.self).forKey("instanceActiveKbites"),
        using: InstanceActiveKbiteRecord.kbite
    )
    .forKey("activeKbites")
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
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
