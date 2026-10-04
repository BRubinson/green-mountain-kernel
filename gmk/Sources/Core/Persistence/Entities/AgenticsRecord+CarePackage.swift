import Foundation
import GRDB

/// Read-side mirror of `care_package`.
struct CarePackageRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "care_package"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var clarifiedIntent: String
    var status: String
    var dopeScopeUuid: String?
    var dopeScopeRevision: Int64?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case clarificationSummaryUuid = "clarification_summary_uuid"
        case clarifiedIntent = "clarified_intent"
        case status
        case dopeScopeUuid = "dope_scope_uuid"
        case dopeScopeRevision = "dope_scope_revision"
    }
}

extension CarePackageRecord {
    static let dopeRefs = hasMany(CarePackageDopeRefRecord.self)
        .order(Column("seq"))
        .forKey("dopeRefs")
    static let kbiteRefs = hasMany(CarePackageKbiteRefRecord.self)
        .order(Column("seq"))
        .forKey("kbiteRefs")
    static let explorationRefs = hasMany(CarePackageExplorationRefRecord.self)
        .order(Column("seq"))
        .forKey("explorationRefs")
}
