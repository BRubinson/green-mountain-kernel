// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `session` table.
///
/// Columns map via convertFromSnakeCase.
struct SessionRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "session"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case instanceUuid = "instance_uuid"
        case code = "code"
        case name = "name"
        case backstory = "backstory"
        case goal = "goal"
        case status = "status"
        case gmfsRelativeStoragePath = "gmfs_relative_storage_path"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var status: String
    var gmfsRelativeStoragePath: String
}

extension SessionRecord {
    static let instance = belongsTo(InstanceRecord.self).forKey("instance")

    static let prompts = hasMany(PromptRecord.self).order(Column("seq")).forKey("prompts")

    static let activations = hasMany(PromptActivationRecord.self).forKey("activations")

    static let files = hasMany(SessionFileRecord.self).forKey("files")

    static let fileChanges = hasMany(FileChangeRecord.self).forKey("fileChanges")

    static let activeKbites = hasMany(
        KbiteRecord.self,
        through: hasMany(SessionActiveKbiteRecord.self).forKey("sessionActiveKbites"),
        using: SessionActiveKbiteRecord.kbite
    )
    .forKey("activeKbites")

    static let briefings = hasMany(AgentBriefingRecord.self).forKey("briefings")

    static let claudeBindings = hasMany(ClaudeSessionBindingRecord.self).forKey("claudeBindings")
}
