// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// PROJECTION record: a typed decoder for a result-set shape, not a table
/// mirror, so it is deliberately NOT enrolled in RecordSchemaTests.
///
/// `lastActivityAt` is a correlated MAX() across session.updated_at,
/// prompt.updated_at and file_change.created_at, and is a column nowhere, which
/// is why SessionRecord.wireRow() cannot synthesize it. The MAX is
/// lexicographic, correct only because isoNow() emits seconds-precision
/// ISO-8601 Z for every writer.
struct SessionStubRecord: SnakeCaseDecoded {
    var uuid: String
    var version: Int64
    var instanceUuid: String
    var code: String
    var name: String
    var gmfsRelativeStoragePath: String
    var createdAt: String
    var updatedAt: String
    var lastActivityAt: String
}
