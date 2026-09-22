// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource_file` table. Columns map via convertFromSnakeCase.
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

extension KbiteResourceFileRecord {
    /// db → wire.
    ///
    /// This is the FULL-CONTENT read (KBITE_FILE_GET, one file by uuid) and is
    /// the only place resource_file_content is meant to be loaded. The stub
    /// listing path deliberately uses KbiteResourceFileStubRecord instead.
    func wireRow() -> KbiteResourceFileRow {
        KbiteResourceFileRow(
            uuid: uuid,
            kbiteResourceUuid: kbiteResourceUuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            resourceFileContent: resourceFileContent,
            createdAt: createdAt
        )
    }
}
