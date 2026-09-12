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

/// Read-side mirror of the `resource_file_keyword_junction` table. Columns map via convertFromSnakeCase.
struct ResourceFileKeywordJunctionRecord: BaseRecordFields {
    static let databaseTableName = "resource_file_keyword_junction"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var fileUuid: String
    var keywordUuid: String
}

/// PROJECTION record: a typed decoder for a result-set shape rather than a
/// table mirror. Not enrolled in RecordSchemaTests, which maps live TABLES.
///
/// This exists specifically so the kbite stub read stays narrow. Its query
/// projects `resource_file_content IS NOT NULL AS has_content` — a computed
/// column — precisely to avoid touching resource_file_content, which is
/// ~115 MB across ~12k rows and by far the largest thing in the schema.
/// KbiteResourceFileRecord declares that column as String?, so a naive
/// SELECT * conversion would DECODE FINE and regress silently into a
/// multi-megabyte read holding the single-writer queue. Modelling the
/// projection instead makes that mistake unexpressible rather than merely
/// documented.
struct KbiteResourceFileStubRecord: SnakeCaseDecoded {
    var uuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var hasContent: Bool
}

extension KbiteResourceFileStubRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireStub() -> KbiteResourceFileStub {
        KbiteResourceFileStub(
            uuid: uuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            hasContent: hasContent)
    }
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
            files: files)
    }
}

extension KbiteResourceFileRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
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
            createdAt: createdAt)
    }
}
