import Foundation
import GRDB

/// Read-side mirror of the `prompt_artifact` table.
///
/// Columns map via convertFromSnakeCase.
struct PromptArtifactRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_artifact"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var filePath: String
    var note: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case filePath = "file_path"
        case note
    }
}

extension PromptArtifactRecord {
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
}
