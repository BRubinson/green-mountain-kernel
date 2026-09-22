// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_persistence_change` table. Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_persistence_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var seq: Int64
    var className: String
    var filePath: String
    var reasonBrief: String
    var changeKind: String
    var dopeRef: String?
}

extension ArchitecturePersistenceChangeRecord {
    /// db → wire, with the children and the comparison state injected.
    ///
    /// Parameterized because neither comes from this table: `fields` is a
    /// second query, and `implementation` is computed against the file-change
    /// trail. Both are labelled and un-defaulted on purpose — a default here
    /// would let a caller silently drop them.
    func wireRow(
        fields: [ArchPersistenceFieldChangeRow],
        implementation: ChangeImplementationState
    ) -> ArchPersistenceChangeRow {
        ArchPersistenceChangeRow(
            uuid: uuid,
            seq: seq,
            className: className,
            filePath: filePath,
            reasonBrief: reasonBrief,
            changeKind: changeKind,
            dopeRef: dopeRef,
            fields: fields,
            implementation: implementation
        )
    }
}
