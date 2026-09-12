// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `session` table. Columns map via convertFromSnakeCase.
struct SessionRecord: BaseRecordFields {
    static let databaseTableName = "session"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var instanceUuid: String
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var status: String
    var ckfsRelativeStoragePath: String
}

/// Read-side mirror of the `session_file` table. Columns map via convertFromSnakeCase.
struct SessionFileRecord: BaseRecordFields {
    static let databaseTableName = "session_file"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var relativePath: String
    var active: Bool
}

extension SessionRecord {
    /// db → wire, with the activation registry injected.
    ///
    /// Parameterized because activations are a second query against
    /// prompt_activation. Labelled and un-defaulted deliberately: SessionRow's
    /// own init defaults `activations` to [], so a nullary wireRow() that
    /// forgot them would compile and silently report every session as
    /// unclaimed.
    func wireRow(activations: [PromptActivationRow]) -> SessionRow {
        SessionRow(
            uuid: uuid, version: version, code: code, name: name,
            backstory: backstory, goal: goal,
            createdAt: createdAt, updatedAt: updatedAt,
            activations: activations)
    }
}

/// PROJECTION record: a typed decoder for a result-set shape rather than a
/// table mirror, so it is deliberately NOT enrolled in RecordSchemaTests
/// (which maps live TABLES, and stays at exactly 57 entries).
///
/// `lastActivityAt` is a correlated MAX() across session.updated_at,
/// prompt.updated_at and file_change.created_at — not a column anywhere.
/// That is exactly why SessionRecord.wireRow() cannot synthesize it, and why
/// this shape was previously the one hand mapper with no repository owner
/// (it served both ListingRepository.listSessions and
/// GitStateRepository.instanceCurrentSession from a static on Store).
///
/// The MAX is lexicographic, which is only correct because isoNow() emits
/// seconds-precision ISO-8601 Z for every writer.
struct SessionStubRecord: SnakeCaseDecoded {
    var uuid: String
    var version: Int64
    var instanceUuid: String
    var code: String
    var name: String
    var ckfsRelativeStoragePath: String
    var createdAt: String
    var updatedAt: String
    var lastActivityAt: String
}

extension SessionStubRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireStub() -> SessionStub {
        SessionStub(
            uuid: uuid,
            version: version,
            instanceUuid: instanceUuid,
            code: code,
            name: name,
            ckfsRelativeStoragePath: ckfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastActivityAt: lastActivityAt)
    }
}
