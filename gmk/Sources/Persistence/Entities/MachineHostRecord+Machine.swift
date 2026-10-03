// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `machine` table (m0031): one row per physical host.
///
/// Keyed on `hardwareUuid` (IOPlatformUUID), which is local-only and never sent on the wire.
struct MachineRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "machine"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case hardwareUuid = "hardware_uuid"
        case name
        case code
        case windowManagementEnabled = "window_management_enabled"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var hardwareUuid: String
    var name: String
    var code: String
    /// True when window management runs; false means no AX observer, no hotkey and no lock.
    var windowManagementEnabled: Bool
}
