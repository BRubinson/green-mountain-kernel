import Foundation
import GRDB

/// Read-side mirror of the `diagram_dope_scope_persistence_layer` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramDopeScopePersistenceLayerRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_dope_scope_persistence_layer"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case dopeScopeCode = "dope_scope_code"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var dopeScopeCode: String
}

extension DiagramDopeScopePersistenceLayerRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")
}
