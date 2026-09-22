// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_connector` table. Columns map via convertFromSnakeCase.
struct DiagramConnectorRecord: DiagramSubtypeRecord, TableRecord {
    static let databaseTableName = "diagram_connector"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case elementUuid = "element_uuid"
        case targetElementUuid = "target_element_uuid"
        case strokeColor = "stroke_color"
        case strokeWidth = "stroke_width"
        case lineStyle = "line_style"
        case headKind = "head_kind"
        case label = "label"
        case routingKind = "routing_kind"
        case tailKind = "tail_kind"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var targetElementUuid: String?
    var strokeColor: String
    var strokeWidth: Double
    var lineStyle: String
    var headKind: String
    var label: String
    var routingKind: String
    var tailKind: String
}

extension DiagramConnectorRecord {
    /// Two foreign keys reach diagram_element from this table, so neither
    /// association can be inferred: GRDB fatalErrors on the ambiguity.
    static let elementForeignKey = ForeignKey([Columns.elementUuid])

    static let targetElementForeignKey = ForeignKey([Columns.targetElementUuid])

    static let element = belongsTo(
        DiagramElementRecord.self,
        using: elementForeignKey
    )
    .forKey("element")

    static let targetElement = belongsTo(
        DiagramElementRecord.self,
        using: targetElementForeignKey
    )
    .forKey("targetElement")
}
