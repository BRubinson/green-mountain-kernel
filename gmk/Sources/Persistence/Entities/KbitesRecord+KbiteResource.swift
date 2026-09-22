// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource` table. Columns map via convertFromSnakeCase.
struct KbiteResourceRecord: BaseRecordFields {
    static let databaseTableName = "kbite_resource"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteUuid: String
    var resourceName: String
    var resourceSummary: String
    var resourceType: String
    var resourceTrust: Int64
}

extension KbiteResourceRecord {
    /// db → wire, with the file stubs injected (a second, deliberately
    /// content-free query). resourceTrust narrows Int64 to the wire's Int.
    func wireRow(files: [KbiteResourceFileStub]) -> KbiteResourceRow {
        KbiteResourceRow(
            uuid: uuid,
            kbiteUuid: kbiteUuid,
            resourceName: resourceName,
            resourceSummary: resourceSummary,
            resourceType: resourceType,
            resourceTrust: Int(resourceTrust),
            files: files
        )
    }
}
