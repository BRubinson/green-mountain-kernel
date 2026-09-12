// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `daemon_event` table. Columns map via convertFromSnakeCase.
struct DaemonEventRecord: BaseRecordFields {
    static let databaseTableName = "daemon_event"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kind: String
    var subjectUuid: String?
    var payload: String?
}

extension DaemonEventRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// Named `wireNotification` rather than `wireRow` because the wire type is
    /// EventNotification, not an *Row — and because `id` is genuinely part of
    /// it. This is the one record that keeps the rowid: it is the SUBSCRIBE
    /// replay cursor, not an implementation detail.
    func wireNotification() -> EventNotification {
        EventNotification(
            id: id,
            kind: kind,
            subjectUuid: subjectUuid,
            payload: payload,
            createdAt: createdAt)
    }
}
