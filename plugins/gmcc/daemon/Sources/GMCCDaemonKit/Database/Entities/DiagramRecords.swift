// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// The eight diagram element subtype tables share one shape: a row keyed to
/// its parent element. This lets fetchDiagramTree hydrate all eight through a
/// single generic helper instead of eight copies, and lets the helper derive
/// its own table name rather than taking it as a string.
protocol DiagramSubtypeRecord: BaseRecordFields {
    var elementUuid: String { get }
}

/// Read-side mirror of the `diagram` table. Columns map via convertFromSnakeCase.
struct DiagramRecord: BaseRecordFields {
    static let databaseTableName = "diagram"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var sessionUuid: String?
    var promptUuid: String?
    var tier: String
    var code: String
    var name: String
    var description: String
    var gmccDiagramPath: String?
    var dopeScopeCode: String?
    var kbiteCode: String?
    var revision: Int64
    var visibility: String
}

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

/// Read-side mirror of the `diagram_connector` table. Columns map via convertFromSnakeCase.
struct DiagramConnectorRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_connector"
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

/// Read-side mirror of the `diagram_uml_node` table. Columns map via convertFromSnakeCase.
struct DiagramUmlNodeRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_uml_node"
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

/// Read-side mirror of the `diagram_shape_vertex` table. Columns map via convertFromSnakeCase.
struct DiagramShapeVertexRecord: BaseRecordFields {
    static let databaseTableName = "diagram_shape_vertex"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var shapeElementUuid: String
    var seq: Int64
    var x: Double
    var y: Double
}

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

extension DiagramRecord {
    /// db → wire, with the derived instance injected.
    ///
    /// `instanceUuid` is NOT a diagram column — m0021 dropped it when INSTANCE
    /// stopped being an ownership tier — so DiagramRepository.diagramSelect
    /// derives it through a LEFT JOIN onto session. That makes diagramSelect a
    /// PROJECTION join rather than a filter-only one: this record decodes the
    /// `d.*` half and the joined column arrives here as a labelled, undefaulted
    /// parameter.
    ///
    /// `visibility` is passed explicitly rather than relying on DiagramRow's
    /// "PRIVATE" init default. It also retires a hasColumn("visibility")
    /// fallback at the call site, which has been dead since m0024 made the
    /// column NOT NULL DEFAULT 'PRIVATE' and every reader started selecting d.*
    /// — the guard could only ever take its true branch.
    func wireRow(instanceUuid: String?) -> DiagramRow {
        DiagramRow(
            uuid: uuid, version: version, tier: tier,
            projectUuid: projectUuid, instanceUuid: instanceUuid,
            sessionUuid: sessionUuid, promptUuid: promptUuid,
            code: code, name: name, description: description,
            gmccDiagramPath: gmccDiagramPath,
            dopeScopeCode: dopeScopeCode, revision: revision,
            visibility: visibility,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
