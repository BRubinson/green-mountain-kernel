// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

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
