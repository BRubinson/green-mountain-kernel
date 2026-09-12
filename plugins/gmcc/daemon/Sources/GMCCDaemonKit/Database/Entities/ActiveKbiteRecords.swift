// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `project_active_kbite` table. Columns map via convertFromSnakeCase.
struct ProjectActiveKbiteRecord: BaseRecordFields {
    static let databaseTableName = "project_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var kbiteUuid: String
}

/// Read-side mirror of the `instance_active_kbite` table. Columns map via convertFromSnakeCase.
struct InstanceActiveKbiteRecord: BaseRecordFields {
    static let databaseTableName = "instance_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var kbiteUuid: String
}

/// Read-side mirror of the `session_active_kbite` table. Columns map via convertFromSnakeCase.
struct SessionActiveKbiteRecord: BaseRecordFields {
    static let databaseTableName = "session_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var kbiteUuid: String
}

/// Read-side mirror of the `prompt_active_kbite` table. Columns map via convertFromSnakeCase.
struct PromptActiveKbiteRecord: BaseRecordFields {
    static let databaseTableName = "prompt_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var kbiteUuid: String
}
