import Foundation
import GRDB

/// Read-side mirror of `care_package_dope_ref` (dot-path CODES).
struct CarePackageDopeRefRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "care_package_dope_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var dopeCode: String
    var note: String?
    var seq: Int64

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case carePackageUuid = "care_package_uuid"
        case dopeCode = "dope_code"
        case note
        case seq
    }
}

extension CarePackageDopeRefRecord {
    static let carePackage = belongsTo(CarePackageRecord.self).forKey("carePackage")
}
