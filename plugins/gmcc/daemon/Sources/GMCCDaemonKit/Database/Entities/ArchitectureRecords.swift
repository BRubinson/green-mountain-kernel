// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `architecture_summary` table. Columns map via convertFromSnakeCase.
struct ArchitectureSummaryRecord: BaseRecordFields {
    static let databaseTableName = "architecture_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var body: String
    var status: String
    var decisionRationale: String
}

/// Read-side mirror of the `architecture_option` table (m0025 pen
/// inversion). Columns map via convertFromSnakeCase.
struct ArchitectureOptionRecord: BaseRecordFields {
    static let databaseTableName = "architecture_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var architectureSummaryUuid: String
    var agentName: String
    var agentId: String?
    var body: String
    var status: String
}

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

/// Read-side mirror of the `architecture_persistence_field_change` table. Columns map via convertFromSnakeCase.
struct ArchitecturePersistenceFieldChangeRecord: BaseRecordFields {
    static let databaseTableName = "architecture_persistence_field_change"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var persistenceChangeUuid: String
    var seq: Int64
    var fieldName: String
    var changeReason: String
    var changePurpose: String
    var dataType: String
    var nullable: Bool
    var isForeignKey: Bool
    var fkTarget: String?
    var isIndexed: Bool
    var changeKind: String
    var renamedFrom: String?
    var dopePropertyRef: String?
}

extension ArchitectureSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ArchitectureSummaryRow {
        ArchitectureSummaryRow(
            uuid: uuid, version: version, promptUuid: promptUuid,
            body: body, status: status, decisionRationale: decisionRationale,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension ArchitecturePersistenceFieldChangeRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// nullable / isForeignKey / isIndexed are decoded as Bool by GRDB, so the
    /// three `(row[...] as Int64) != 0` casts this retires now happen once in
    /// the decoder instead of once per field here.
    func wireRow() -> ArchPersistenceFieldChangeRow {
        ArchPersistenceFieldChangeRow(
            uuid: uuid, seq: seq, fieldName: fieldName,
            changeReason: changeReason, changePurpose: changePurpose,
            dataType: dataType, nullable: nullable, isForeignKey: isForeignKey,
            fkTarget: fkTarget, isIndexed: isIndexed, changeKind: changeKind,
            renamedFrom: renamedFrom, dopePropertyRef: dopePropertyRef)
    }
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
            uuid: uuid, seq: seq, className: className, filePath: filePath,
            reasonBrief: reasonBrief, changeKind: changeKind, dopeRef: dopeRef,
            fields: fields, implementation: implementation)
    }
}

extension ArchitectureGeneralChangeRecord {
    /// db → wire, with the comparison state injected. See the sibling above
    /// for why `implementation` is a labelled, un-defaulted parameter.
    func wireRow(implementation: ChangeImplementationState) -> ArchGeneralChangeRow {
        ArchGeneralChangeRow(
            uuid: uuid, seq: seq, filePath: filePath, className: className,
            reasonBrief: reasonBrief, changeDepth: changeDepth,
            changeCode: changeCode, implementation: implementation)
    }
}

extension ArchitectureOptionRecord {
    /// db → wire.
    func wireRow() -> ArchitectureOptionRow {
        ArchitectureOptionRow(
            uuid: uuid, version: version,
            architectureSummaryUuid: architectureSummaryUuid,
            agentName: agentName, agentId: agentId, body: body, status: status,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
