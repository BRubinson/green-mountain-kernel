import Foundation
import GRDB

/// Read-side mirror of `care_package_exploration_ref` (curated copies).
struct CarePackageExplorationRefRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "care_package_exploration_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var curatedTitle: String
    var curatedBody: String
    var filePath: String?
    var sourceFindingUuid: String?
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case carePackageUuid = "care_package_uuid"
        case curatedTitle = "curated_title"
        case curatedBody = "curated_body"
        case filePath = "file_path"
        case sourceFindingUuid = "source_finding_uuid"
        case seq
    }
}

extension CarePackageExplorationRefRecord {
    static let carePackage = belongsTo(CarePackageRecord.self).forKey("carePackage")
}
