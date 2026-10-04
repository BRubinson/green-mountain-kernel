import Foundation
import GRDB

/// Read-side mirror of the `prompt_active_kbite` table.
///
/// Columns map via convertFromSnakeCase.
struct PromptActiveKbiteRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_active_kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var kbiteUuid: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case kbiteUuid = "kbite_uuid"
    }
}

extension PromptActiveKbiteRecord {
    static let kbite = belongsTo(KbiteRecord.self)
        .forKey("kbite")
    static let prompt = belongsTo(PromptRecord.self)
        .forKey("prompt")
}
