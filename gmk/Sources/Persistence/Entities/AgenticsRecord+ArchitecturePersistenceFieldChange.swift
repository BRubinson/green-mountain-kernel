// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

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

extension ArchitecturePersistenceFieldChangeRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// nullable / isForeignKey / isIndexed are decoded as Bool by GRDB, so the
    /// three `(row[...] as Int64) != 0` casts this retires now happen once in
    /// the decoder instead of once per field here.
    func wireRow() -> ArchPersistenceFieldChangeRow {
        ArchPersistenceFieldChangeRow(
            uuid: uuid,
            seq: seq,
            fieldName: fieldName,
            changeReason: changeReason,
            changePurpose: changePurpose,
            dataType: dataType,
            nullable: nullable,
            isForeignKey: isForeignKey,
            fkTarget: fkTarget,
            isIndexed: isIndexed,
            changeKind: changeKind,
            renamedFrom: renamedFrom,
            dopePropertyRef: dopePropertyRef
        )
    }
}
