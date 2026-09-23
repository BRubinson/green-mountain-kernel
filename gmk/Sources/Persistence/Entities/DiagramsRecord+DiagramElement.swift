// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_element` table.
///
/// Columns map via convertFromSnakeCase.
struct DiagramElementRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "diagram_element"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case diagramUuid = "diagram_uuid"
        case parentElementUuid = "parent_element_uuid"
        case elementType = "element_type"
        case code = "code"
        case name = "name"
        case description = "description"
        case sortOrder = "sort_order"
        case centerX = "center_x"
        case centerY = "center_y"
        case elementZ = "element_z"
        case scale = "scale"
    }

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

extension DiagramElementRecord {
    static let diagram = belongsTo(DiagramRecord.self).forKey("diagram")

    static let parent = belongsTo(DiagramElementRecord.self).forKey("parent")

    static let children = hasMany(DiagramElementRecord.self).forKey("children")
}
