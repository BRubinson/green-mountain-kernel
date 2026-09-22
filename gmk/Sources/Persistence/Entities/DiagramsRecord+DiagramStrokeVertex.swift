// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_stroke_vertex` table. Columns map via convertFromSnakeCase.
struct DiagramStrokeVertexRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "diagram_stroke_vertex"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case strokeElementUuid = "stroke_element_uuid"
        case seq = "seq"
        case x = "x"
        case y = "y"
        case pressure = "pressure"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var strokeElementUuid: String
    var seq: Int64
    var x: Double
    var y: Double
    var pressure: Double?
}

extension DiagramStrokeVertexRecord {
    /// `stroke_element_uuid` points at `diagram_drawing_stroke.element_uuid`,
    /// not at its primary key; the schema foreign key carries that mapping.
    static let stroke = belongsTo(DiagramDrawingStrokeRecord.self).forKey("stroke")
}
