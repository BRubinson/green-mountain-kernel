import Foundation
import GRDB

/// Read-side mirror of the `diagram_dope_entity` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramDopeEntityRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_dope_entity"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case entityCode = "entity_code"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var entityCode: String
}

extension DiagramDopeEntityRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")
}
