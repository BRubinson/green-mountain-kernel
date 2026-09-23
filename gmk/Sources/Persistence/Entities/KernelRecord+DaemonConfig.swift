// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `daemon_config` table.
///
/// Columns map via convertFromSnakeCase.
struct DaemonConfigRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "daemon_config"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var configKey: String
    var configValue: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case configKey = "config_key"
        case configValue = "config_value"
    }
}
