// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "diagram"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case tier = "tier"
        case code = "code"
        case name = "name"
        case description = "description"
        case gmccDiagramPath = "gmcc_diagram_path"
        case dopeScopeCode = "dope_scope_code"
        case kbiteCode = "kbite_code"
        case revision = "revision"
        case visibility = "visibility"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var sessionUuid: String?
    var promptUuid: String?
    var tier: String
    var code: String
    var name: String
    var description: String
    var gmccDiagramPath: String?
    var dopeScopeCode: String?
    var kbiteCode: String?
    var revision: Int64
    var visibility: String
}

extension DiagramRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")

    static let project = belongsTo(ProjectRecord.self).forKey("project")

    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")

    static let elements = hasMany(DiagramElementRecord.self).order(Column("sort_order")).forKey("elements")
}
