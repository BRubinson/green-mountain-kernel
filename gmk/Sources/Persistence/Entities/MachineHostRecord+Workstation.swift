// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `workstation` table (m0031): one connected-display set of a machine.
///
/// Identity is `(machineUuid, displaySetKey)`. A row is minted on first sight of its set and never
/// retires; the workstation whose key equals the connected set is the active one.
struct WorkstationRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "workstation"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case machineUuid = "machine_uuid"
        case displaySetKey = "display_set_key"
        case name
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var machineUuid: String
    /// The member displays' stable keys, sorted and comma-joined.
    var displaySetKey: String
    /// The user-editable name, which defaults to the member display names in position order.
    var name: String
}

extension WorkstationRecord {
    static let machine = belongsTo(MachineRecord.self).forKey("machine")
}
