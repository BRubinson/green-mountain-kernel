// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt_qualified_diagram` table. Columns map via convertFromSnakeCase.
struct PromptQualifiedDiagramRecord: BaseRecordFields {
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
