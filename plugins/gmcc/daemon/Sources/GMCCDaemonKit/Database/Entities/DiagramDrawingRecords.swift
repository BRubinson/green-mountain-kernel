// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_drawing_layer` table. Columns map via convertFromSnakeCase.
struct DiagramDrawingLayerRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_drawing_layer"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var opacity: Double
    var visible: Bool
    var locked: Bool
}

/// Read-side mirror of the `diagram_drawing_shape` table. Columns map via convertFromSnakeCase.
struct DiagramDrawingShapeRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_drawing_shape"
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

/// Read-side mirror of the `diagram_drawing_stroke` table. Columns map via convertFromSnakeCase.
struct DiagramDrawingStrokeRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_drawing_stroke"
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

/// Read-side mirror of the `diagram_drawing_text` table. Columns map via convertFromSnakeCase.
struct DiagramDrawingTextRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_drawing_text"
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
