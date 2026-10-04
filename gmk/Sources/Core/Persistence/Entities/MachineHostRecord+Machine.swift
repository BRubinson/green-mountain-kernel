import Foundation
import GRDB

/// Read-side mirror of the `machine` table: one row per physical host.
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
