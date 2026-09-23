// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `project_test_lock` table (m0029): the ONE mutable
/// claim cell per project.
///
/// The pairing with `test_run` is the point. This row is overwritten on every
/// claim and release; the ledger row it points at is never touched again. Were
/// they one table, every re-lock would destroy the record of the previous run —
/// a deletion by another name, in a db whose whole contract is that it does not
/// lose history.
struct ProjectTestLockRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "project_test_lock"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var state: String
    var heldByRunUuid: String?
    var targetInstanceUuid: String?
    /// `process` (flock-backed, the default and the safe one) or `lease`.
    ///
    /// See `TestRunRepository.isHolderGone` — this selects WHICH liveness test
    /// runs, and only `lease` consults `expiresAt`.
    var holderKind: String
    /// The file the holder `flock`s.
    ///
    /// Absent ⇒ lease mode.
    var lockPath: String?
    var holderPid: Int?
    var claimedAt: String?
    /// Lease mode ONLY.
    ///
    /// Never the primary liveness test: a TTL fails toward HOLDING a stuck lock,
    /// which for a mutex is the worst direction.
    var expiresAt: String?

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case state
        case heldByRunUuid = "held_by_run_uuid"
        case targetInstanceUuid = "target_instance_uuid"
        case holderKind = "holder_kind"
        case lockPath = "lock_path"
        case holderPid = "holder_pid"
        case claimedAt = "claimed_at"
        case expiresAt = "expires_at"
    }
}

extension ProjectTestLockRecord {
    static let project = belongsTo(ProjectRecord.self).forKey("project")
    static let heldByRun = belongsTo(TestRunRecord.self).forKey("heldByRun")
    static let targetInstance = belongsTo(InstanceRecord.self).forKey("targetInstance")
}
