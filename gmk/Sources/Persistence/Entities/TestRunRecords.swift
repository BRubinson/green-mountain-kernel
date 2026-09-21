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
struct ProjectTestLockRecord: BaseRecordFields {
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
    /// See `TestRunRepository.isHolderGone` — this selects WHICH liveness test
    /// runs, and only `lease` consults `expiresAt`.
    var holderKind: String
    /// The file the holder `flock`s. Absent ⇒ lease mode.
    var lockPath: String?
    var holderPid: Int?
    var claimedAt: String?
    /// Lease mode ONLY. Never the primary liveness test: a TTL fails toward
    /// HOLDING a stuck lock, which for a mutex is the worst direction.
    var expiresAt: String?
}

/// Read-side mirror of the `test_run` table (m0029): APPEND-ONLY run history.
///
/// Nothing here is ever deleted, and the only mutations are the lifecycle
/// stamps (`state`, `startedAt`, `finishedAt`, `exitCode`, `summary`) on a row
/// that already exists.
struct TestRunRecord: BaseRecordFields {
    static let databaseTableName = "test_run"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var instanceUuid: String?
    var sessionUuid: String?
    /// Joins `agent_registration.agent_id` but is NOT a foreign key — that row
    /// is written by a party which may not have arrived yet, so a real FK would
    /// make claiming fail on registration ORDERING rather than on anything
    /// about the claim.
    var agentId: String?
    /// The ephemeral root this run owns. Whatever generates it must keep it
    /// SHORT: `sun_path` is 104 bytes on macOS and the server binds
    /// `NWEndpoint.unix(path:)` beneath this root, so a long path yields a
    /// listener that cannot bind.
    var runRoot: String
    var suiteId: String
    var gitSha: String?
    var gitBranch: String?
    var state: String
    var doneKind: String
    var doneCondition: String
    /// The human sentence another agent reads to decide whether to wait.
    var doneHint: String?
    var startedAt: String?
    var finishedAt: String?
    var exitCode: Int?
    var summary: String?
}
