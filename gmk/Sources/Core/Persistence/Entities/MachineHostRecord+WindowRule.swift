import Foundation
import GRDB

/// Read-side mirror of the `window_rule` table: the user's tile or float choice for one app on one machine.
///
/// Identity is `(machineUuid, bundleId)`. Clearing a rule hard-deletes its row, so an absent row means the
/// classifier's default.
struct WindowRuleRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "window_rule"

    /// The `window_rule` column names, snake_case on disk.
    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case machineUuid = "machine_uuid"
        case bundleId = "bundle_id"
        case appName = "app_name"
        case disposition
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var machineUuid: String
    var bundleId: String
    /// The app's display name as of the last upsert, so a rule for an app not running can still be listed.
    var appName: String
    /// `"tile"` or `"float"`; the vocabulary lives in `WindowRuleDisposition`.
    var disposition: String
}

extension WindowRuleRecord {
    /// The machine the rule belongs to.
    static let machine = belongsTo(MachineRecord.self).forKey("machine")
}
