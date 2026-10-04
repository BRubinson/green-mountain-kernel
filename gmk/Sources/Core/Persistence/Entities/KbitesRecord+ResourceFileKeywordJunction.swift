import Foundation
import GRDB

/// Read-side mirror of the `resource_file_keyword_junction` table.
///
/// Columns map via convertFromSnakeCase.
struct ResourceFileKeywordJunctionRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "resource_file_keyword_junction"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var fileUuid: String
    var keywordUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case fileUuid = "file_uuid"
        case keywordUuid = "keyword_uuid"
    }
}

extension ResourceFileKeywordJunctionRecord {
    static let file = belongsTo(KbiteResourceFileRecord.self)
        .forKey("file")
    static let keyword = belongsTo(KeywordRecord.self)
        .forKey("keyword")
}
