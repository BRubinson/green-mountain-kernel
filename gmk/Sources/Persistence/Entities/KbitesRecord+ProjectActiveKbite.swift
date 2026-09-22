// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `project_active_kbite` table. Columns map via convertFromSnakeCase.
struct ProjectActiveKbiteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "project_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var kbiteUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case kbiteUuid = "kbite_uuid"
    }
}

extension ProjectActiveKbiteRecord {
    static let kbite = belongsTo(KbiteRecord.self)
        .forKey("kbite")
    static let project = belongsTo(ProjectRecord.self)
        .forKey("project")
}
