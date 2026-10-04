import Foundation
import GRDB

/// Read-side mirror of the `kbite` table.
///
/// Columns map via convertFromSnakeCase.
struct KbiteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var code: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case code
    }
}

extension KbiteRecord {
    static let resources = hasMany(KbiteResourceRecord.self)
        .order(Column("resource_name"))
        .forKey("resources")
    static let keywordJunctions = hasMany(KbiteKeywordJunctionRecord.self)
        .forKey("keywordJunctions")
    static let keywords = hasMany(
        KeywordRecord.self,
        through: keywordJunctions,
        using: KbiteKeywordJunctionRecord.keyword
    )
    .forKey("keywords")
    static let projectActivations = hasMany(ProjectActiveKbiteRecord.self)
        .forKey("projectActivations")
    static let instanceActivations = hasMany(InstanceActiveKbiteRecord.self)
        .forKey("instanceActivations")
    static let sessionActivations = hasMany(SessionActiveKbiteRecord.self)
        .forKey("sessionActivations")
    static let promptActivations = hasMany(PromptActiveKbiteRecord.self)
        .forKey("promptActivations")
}
