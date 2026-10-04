import Foundation
import GRDB

/// Read-side mirror of the `architecture_persistence_change` table.
///
/// Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceChangeRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "architecture_persistence_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var className: String
    var filePath: String
    var reasonBrief: String
    var changeKind: String
    var dopeRef: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case architectureSummaryUuid = "architecture_summary_uuid"
        case seq
        case className = "class_name"
        case filePath = "file_path"
        case reasonBrief = "reason_brief"
        case changeKind = "change_kind"
        case dopeRef = "dope_ref"
    }
}

extension ArchitecturePersistenceChangeRecord {
    static let fields = hasMany(ArchitecturePersistenceFieldChangeRecord.self)
        .order(Column("seq"))
        .forKey("fields")
    static let summary = belongsTo(ArchitectureSummaryRecord.self).forKey("summary")
}
