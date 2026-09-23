// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_summary` table.
///
/// Columns map via convertFromSnakeCase.
struct ArchitectureSummaryRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "architecture_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var body: String
    var status: String
    var decisionRationale: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case body
        case status
        case decisionRationale = "decision_rationale"
    }
}

extension ArchitectureSummaryRecord {
    static let options = hasMany(ArchitectureOptionRecord.self).forKey("options")
    static let persistenceChanges = hasMany(ArchitecturePersistenceChangeRecord.self)
        .order(Column("seq"))
        .forKey("persistenceChanges")
    static let generalChanges = hasMany(ArchitectureGeneralChangeRecord.self)
        .order(Column("seq"))
        .forKey("generalChanges")
}
