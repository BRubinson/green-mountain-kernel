// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `app_process` table (m0031): a running GUI app the window manager observes.
///
/// Identity is `(pid, launchedAt)`, so a recycled pid never inherits another app's rows. Rows retire
/// through `deletedOn` and are never hard-deleted.
struct AppProcessRecord: BaseRecordFields, TableRecord, SoftDeletable {
    static let databaseTableName = "app_process"

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case machineUuid = "machine_uuid"
        case pid
        case launchedAt = "launched_at"
        case bundleId = "bundle_id"
        case name
        case isRunning = "is_running"
        case deletedOn = "deleted_on"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var machineUuid: String
    var pid: Int
    /// `NSRunningApplication.launchDate`; a row whose pair mismatches the live process is never rebound.
    var launchedAt: String
    var bundleId: String?
    var name: String
    var isRunning: Bool
    var deletedOn: String?
}

extension AppProcessRecord {
    static let machine = belongsTo(MachineRecord.self).forKey("machine")
}
