// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `test_run` table (m0029): APPEND-ONLY run history.
///
/// Nothing here is ever deleted, and the only mutations are the lifecycle
/// stamps (`state`, `startedAt`, `finishedAt`, `exitCode`, `summary`) on a row
/// that already exists.
struct TestRunRecord: BaseRecordFields, TableRecord {
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

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectUuid = "project_uuid"
        case instanceUuid = "instance_uuid"
        case sessionUuid = "session_uuid"
        case agentId = "agent_id"
        case runRoot = "run_root"
        case suiteId = "suite_id"
        case gitSha = "git_sha"
        case gitBranch = "git_branch"
        case state
        case doneKind = "done_kind"
        case doneCondition = "done_condition"
        case doneHint = "done_hint"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case exitCode = "exit_code"
        case summary
    }
}

extension TestRunRecord {
    static let project = belongsTo(ProjectRecord.self).forKey("project")
    static let instance = belongsTo(InstanceRecord.self).forKey("instance")
    static let session = belongsTo(SessionRecord.self).forKey("session")
    static let lock = hasOne(ProjectTestLockRecord.self).forKey("lock")
}
