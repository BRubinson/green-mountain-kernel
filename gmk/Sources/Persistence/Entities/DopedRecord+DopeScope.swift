// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_scope` table. Columns map via convertFromSnakeCase.
struct DopeScopeRecord: BaseRecordFields, TableRecord, SoftDeletable {
    static let databaseTableName = "dope_scope"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var instanceUuid: String?
    var sessionUuid: String?
    var promptUuid: String?
    var scopeType: String
    var code: String
    var name: String
    var description: String
    var revision: Int64
    var deletedOn: String?
    var promotedFromScopeUuid: String?
    var promotedFromRevision: Int64?
    var promotedFromUpdatedAt: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case instanceUuid = "instance_uuid"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case scopeType = "scope_type"
        case code
        case name
        case description
        case revision
        case deletedOn = "deleted_on"
        case promotedFromScopeUuid = "promoted_from_scope_uuid"
        case promotedFromRevision = "promoted_from_revision"
        case promotedFromUpdatedAt = "promoted_from_updated_at"
    }
}

extension DopeScopeRecord {
    static let project = belongsTo(ProjectRecord.self).forKey("project")
    static let instance = belongsTo(InstanceRecord.self).forKey("instance")
    static let session = belongsTo(SessionRecord.self).forKey("session")
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
    static let persistences = hasMany(DopePersistenceRecord.self)
        .order(Column("sort_order"))
        .forKey("persistences")
    static let cogs = hasMany(DopeCogRecord.self)
        .order(Column("sort_order"))
        .forKey("cogs")
    static let provenance = hasMany(DopeElementProvenanceRecord.self).forKey("provenance")
}
