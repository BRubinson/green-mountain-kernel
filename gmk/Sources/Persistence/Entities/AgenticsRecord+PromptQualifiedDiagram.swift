// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_qualified_diagram` table. Columns map via convertFromSnakeCase.
struct PromptQualifiedDiagramRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "prompt_qualified_diagram"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var diagramUuid: String
    var renderedPath: String
    var renderedRevision: Int64
    var renderFingerprint: String
    var qualification: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case promptUuid = "prompt_uuid"
        case diagramUuid = "diagram_uuid"
        case renderedPath = "rendered_path"
        case renderedRevision = "rendered_revision"
        case renderFingerprint = "render_fingerprint"
        case qualification
    }
}

extension PromptQualifiedDiagramRecord {
    static let prompt = belongsTo(PromptRecord.self).forKey("prompt")
    static let diagram = belongsTo(DiagramRecord.self).forKey("diagram")
}

extension PromptQualifiedDiagramRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> PromptQualifiedDiagramRow {
        PromptQualifiedDiagramRow(
            uuid: uuid,
            promptUuid: promptUuid,
            diagramUuid: diagramUuid,
            renderedPath: renderedPath,
            renderedRevision: renderedRevision,
            renderFingerprint: renderFingerprint,
            qualification: qualification,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
