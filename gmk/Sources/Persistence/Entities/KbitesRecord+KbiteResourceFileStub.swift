// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// PROJECTION record: a typed decoder for a result-set shape, not a table
/// mirror, so it is not enrolled in RecordSchemaTests.
///
/// It keeps the kbite stub read narrow. The query projects
/// `resource_file_content IS NOT NULL AS has_content` to avoid touching
/// resource_file_content, which is ~115 MB and the largest thing in the schema.
/// A `SELECT *` would decode fine and silently hold the single-writer queue
/// across a multi-megabyte read; the projection makes that unexpressible.
struct KbiteResourceFileStubRecord: SnakeCaseDecoded {
    var uuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var hasContent: Bool
}

extension KbiteResourceFileStubRecord {
    /// db → wire.
    func wireStub() -> KbiteResourceFileStub {
        KbiteResourceFileStub(
            uuid: uuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            hasContent: hasContent
        )
    }
}
