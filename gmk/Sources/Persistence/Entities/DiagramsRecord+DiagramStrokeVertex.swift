// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_stroke_vertex` table. Columns map via convertFromSnakeCase.
struct DiagramStrokeVertexRecord: BaseRecordFields {
    static let databaseTableName = "diagram_stroke_vertex"
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
