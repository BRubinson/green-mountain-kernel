// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_general_change` table. Columns map via convertFromSnakeCase.
struct ArchitectureGeneralChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_general_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var filePath: String
    var className: String?
    var reasonBrief: String
    var changeDepth: String
    var changeCode: String
}

extension ArchitectureGeneralChangeRecord {
    /// db → wire, with the comparison state injected. See the sibling above
    /// for why `implementation` is a labelled, un-defaulted parameter.
    func wireRow(implementation: ChangeImplementationState) -> ArchGeneralChangeRow {
        ArchGeneralChangeRow(
            uuid: uuid,
            seq: seq,
            filePath: filePath,
            className: className,
            reasonBrief: reasonBrief,
            changeDepth: changeDepth,
            changeCode: changeCode,
            implementation: implementation
        )
    }
}
