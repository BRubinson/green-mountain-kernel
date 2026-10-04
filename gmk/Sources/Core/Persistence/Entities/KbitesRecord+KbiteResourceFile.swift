import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource_file` table.
///
/// Columns map via convertFromSnakeCase.
struct KbiteResourceFileRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "kbite_resource_file"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteResourceUuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var resourceFileContent: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case kbiteResourceUuid = "kbite_resource_uuid"
        case resourceFileName = "resource_file_name"
        case resourceFileSummary = "resource_file_summary"
        case resourceFileContent = "resource_file_content"
    }
}

extension KbiteResourceFileRecord {
    static let resource = belongsTo(KbiteResourceRecord.self)
        .forKey("resource")
    static let keywordJunctions = hasMany(ResourceFileKeywordJunctionRecord.self)
        .forKey("keywordJunctions")
    static let keywords = hasMany(
        KeywordRecord.self,
        through: keywordJunctions,
        using: ResourceFileKeywordJunctionRecord.keyword
    )
    .forKey("keywords")
}
