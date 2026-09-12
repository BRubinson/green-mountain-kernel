// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt` table. Columns map via convertFromSnakeCase.
struct PromptRecord: BaseRecordFields {
    static let databaseTableName = "prompt"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var seq: Int64
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var detail: String
    var command: String
    var status: String
    var ckfsRelativeStoragePath: String
}

/// Read-side mirror of the `prompt_activation` table. Columns map via convertFromSnakeCase.
struct PromptActivationRecord: BaseRecordFields {
    static let databaseTableName = "prompt_activation"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var promptUuid: String
    var clientKey: String
}

/// Read-side mirror of the `prompt_artifact` table. Columns map via convertFromSnakeCase.
struct PromptArtifactRecord: BaseRecordFields {
    static let databaseTableName = "prompt_artifact"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var filePath: String
    var note: String?
}

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

extension PromptArtifactRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ArtifactRow {
        ArtifactRow(
            uuid: uuid,
            promptUuid: promptUuid,
            filePath: filePath,
            note: note,
            createdAt: createdAt)
    }
}

extension PromptRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// PromptRow IS field-for-field identical to this record, so the prompt
    /// row assembly the original plan filed under "stays hand-assembled" was
    /// a clean 1:1 all along. What genuinely stays hand-assembled is
    /// PromptGetResponse and PromptStub (the latter folds four grouped report
    /// aggregations over computed columns).
    func wireRow() -> PromptRow {
        PromptRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            seq: seq,
            code: code,
            name: name,
            backstory: backstory,
            goal: goal,
            detail: detail,
            command: command,
            status: status,
            ckfsRelativeStoragePath: ckfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
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
            updatedAt: updatedAt)
    }
}

extension PromptActivationRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> PromptActivationRow {
        PromptActivationRow(
            uuid: uuid, sessionUuid: sessionUuid, promptUuid: promptUuid,
            clientKey: clientKey, createdAt: createdAt)
    }
}
