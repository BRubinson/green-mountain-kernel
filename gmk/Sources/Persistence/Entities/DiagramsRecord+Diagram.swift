// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

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

extension DiagramRecord {
    /// db → wire, with the derived instance injected.
    ///
    /// `instanceUuid` is not a diagram column: DiagramRepository.diagramSelect
    /// derives it through a LEFT JOIN onto session, so this record decodes the
    /// `d.*` half and the joined column arrives as a labelled, undefaulted
    /// parameter. `visibility` is passed explicitly rather than leaning on
    /// DiagramRow's "PRIVATE" init default.
    func wireRow(instanceUuid: String?) -> DiagramRow {
        DiagramRow(
            uuid: uuid,
            version: version,
            tier: tier,
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            code: code,
            name: name,
            description: description,
            gmccDiagramPath: gmccDiagramPath,
            dopeScopeCode: dopeScopeCode,
            revision: revision,
            visibility: visibility,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
