import Foundation
import GRDB

/// Read-side mirror of the `diagram_uml_node` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramUmlNodeRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_uml_node"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case nodeKind = "node_kind"
        case width = "width"
        case height = "height"
        case markdown = "markdown"
        case fontSize = "font_size"
        case textColor = "text_color"
        case strokeColor = "stroke_color"
        case strokeWidth = "stroke_width"
        case fillColor = "fill_color"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var nodeKind: String
    var width: Double
    var height: Double
    var markdown: String
    var fontSize: Double?
    var textColor: String?
    var strokeColor: String?
    var strokeWidth: Double?
    var fillColor: String?
}

extension DiagramUmlNodeRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")
}
