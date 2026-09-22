// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite_resource` table. Columns map via convertFromSnakeCase.
struct KbiteResourceRecord: BaseRecordFields, TableRecord {
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

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case kbiteUuid = "kbite_uuid"
        case resourceName = "resource_name"
        case resourceSummary = "resource_summary"
        case resourceType = "resource_type"
        case resourceTrust = "resource_trust"
    }
}

extension KbiteResourceRecord {
    static let kbite = belongsTo(KbiteRecord.self)
        .forKey("kbite")
    /// The destination is the full-row Record: a list read must `select()`
    /// around `resource_file_content` at request time.
    static let files = hasMany(KbiteResourceFileRecord.self)
        .order(Column("resource_file_name"))
        .forKey("files")
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
