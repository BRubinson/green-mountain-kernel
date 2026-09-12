// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `daemon_config` table. Columns map via convertFromSnakeCase.
struct DaemonConfigRecord: BaseRecordFields {
    static let databaseTableName = "daemon_config"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var configKey: String
    var configValue: String
}
