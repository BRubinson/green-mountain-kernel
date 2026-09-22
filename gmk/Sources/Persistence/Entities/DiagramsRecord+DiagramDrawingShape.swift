// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_drawing_shape` table. Columns map via convertFromSnakeCase.
struct DiagramDrawingShapeRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_drawing_shape"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case shapeKind = "shape_kind"
        case strokeColor = "stroke_color"
        case strokeWidth = "stroke_width"
        case fillColor = "fill_color"
        case cornerRadius = "corner_radius"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var shapeKind: String
    var strokeColor: String
    var strokeWidth: Double
    var fillColor: String?
    var cornerRadius: Double?
}

extension DiagramDrawingShapeRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")

    static let vertices = hasMany(DiagramShapeVertexRecord.self).order(Column("seq")).forKey("vertices")
}
