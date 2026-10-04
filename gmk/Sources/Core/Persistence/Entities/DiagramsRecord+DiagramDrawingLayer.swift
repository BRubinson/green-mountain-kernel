import Foundation
import GRDB

/// Read-side mirror of the `diagram_drawing_layer` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramDrawingLayerRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_drawing_layer"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case opacity = "opacity"
        case visible = "visible"
        case locked = "locked"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var opacity: Double
    var visible: Bool
    var locked: Bool
}

extension DiagramDrawingLayerRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")
}
