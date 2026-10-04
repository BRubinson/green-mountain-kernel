import Foundation
import GRDB

/// Read-side mirror of the `prompt_activation` table.
///
/// Columns map via convertFromSnakeCase.
struct PromptActivationRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_activation"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String
    var clientKey: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case promptUuid = "prompt_uuid"
        case clientKey = "client_key"
    }
}

extension PromptActivationRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
}
