// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource_file` table. Columns map via convertFromSnakeCase.
struct KbiteResourceFileRecord: BaseRecordFields {
    static let databaseTableName = "kbite_resource_file"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteResourceUuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var resourceFileContent: String?
}

extension KbiteResourceFileRecord {
    /// db → wire.
    ///
    /// This is the FULL-CONTENT read (KBITE_FILE_GET, one file by uuid) and is
    /// the only place resource_file_content is meant to be loaded. The stub
    /// listing path deliberately uses KbiteResourceFileStubRecord instead.
    func wireRow() -> KbiteResourceFileRow {
        KbiteResourceFileRow(
            uuid: uuid,
            kbiteResourceUuid: kbiteResourceUuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            resourceFileContent: resourceFileContent,
            createdAt: createdAt
        )
    }
}
