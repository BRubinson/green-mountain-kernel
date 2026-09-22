// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_element` table. Columns map via convertFromSnakeCase.
struct DiagramElementRecord: BaseRecordFields {
    static let databaseTableName = "diagram_element"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var diagramUuid: String
    var parentElementUuid: String?
    var elementType: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var centerX: Double
    var centerY: Double
    var elementZ: Double
    var scale: Double
}
