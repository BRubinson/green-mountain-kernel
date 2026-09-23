// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_drawing_text` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramDrawingTextRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_drawing_text"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case markdown = "markdown"
        case width = "width"
        case height = "height"
        case fontSize = "font_size"
        case textColor = "text_color"
        case backgroundColor = "background_color"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var markdown: String
    var width: Double
    var height: Double
    var fontSize: Double
    var textColor: String
    var backgroundColor: String?
}

extension DiagramDrawingTextRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")
}
