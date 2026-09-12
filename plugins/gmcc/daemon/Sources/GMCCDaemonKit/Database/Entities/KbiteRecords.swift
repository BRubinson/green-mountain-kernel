// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `kbite` table. Columns map via convertFromSnakeCase.
struct KbiteRecord: BaseRecordFields {
    static let databaseTableName = "kbite"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var code: String
}

/// Read-side mirror of the `keyword` table. Columns map via convertFromSnakeCase.
struct KeywordRecord: BaseRecordFields {
    static let databaseTableName = "keyword"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var keyword: String
}

/// Read-side mirror of the `kbite_keyword_junction` table. Columns map via convertFromSnakeCase.
struct KbiteKeywordJunctionRecord: BaseRecordFields {
    static let databaseTableName = "kbite_keyword_junction"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var kbiteUuid: String
    var keywordUuid: String
}

extension KbiteRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> KbiteRow {
        KbiteRow(
            uuid: uuid,
            version: version,
            code: code,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}
