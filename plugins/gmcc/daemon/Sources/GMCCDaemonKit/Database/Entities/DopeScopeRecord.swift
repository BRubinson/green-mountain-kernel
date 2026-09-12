// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_scope` table. Columns map via convertFromSnakeCase.
struct DopeScopeRecord: BaseRecordFields {
    static let databaseTableName = "dope_scope"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var instanceUuid: String?
    var sessionUuid: String?
    var promptUuid: String?
    var scopeType: String
    var code: String
    var name: String
    var description: String
    var revision: Int64
    var deletedOn: String?
    var promotedFromScopeUuid: String?
    var promotedFromRevision: Int64?
    var promotedFromUpdatedAt: String?
}

extension DopeScopeRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// Every parameter is passed explicitly, including the three the wire
    /// init defaults (projectUuid, instanceUuid, deletedOn). Omitting
    /// `deletedOn` here would COMPILE and would quietly un-delete every
    /// tombstoned dope node for all 14 readers of this row.
    func wireRow() -> DopeScopeRow {
        DopeScopeRow(
            uuid: uuid, version: version,
            projectUuid: projectUuid, instanceUuid: instanceUuid,
            sessionUuid: sessionUuid, promptUuid: promptUuid,
            scopeType: scopeType, code: code, name: name,
            description: description, revision: revision,
            deletedOn: deletedOn,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
