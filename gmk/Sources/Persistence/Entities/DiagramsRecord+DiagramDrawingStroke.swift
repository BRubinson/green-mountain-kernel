// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_drawing_stroke` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramDrawingStrokeRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_drawing_stroke"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case tool = "tool"
        case strokeColor = "stroke_color"
        case strokeWidth = "stroke_width"
        case packedVertices = "packed_vertices"
        case vertexCount = "vertex_count"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var tool: String
    var strokeColor: String
    var strokeWidth: Double
    var packedVertices: Data?
    var vertexCount: Int64?
}

extension DiagramDrawingStrokeRecord {
    static let element = belongsTo(DiagramElementRecord.self).forKey("element")

    static let vertices = hasMany(DiagramStrokeVertexRecord.self).order(Column("seq")).forKey("vertices")
}
