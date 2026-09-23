// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_element_provenance` table.
///
/// Columns map via convertFromSnakeCase.
struct DopeElementProvenanceRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "dope_element_provenance"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopeScopeUuid: String
    var dotPath: String
    var elementKind: String
    var syncedContentHash: String?
    var locallyModified: Bool

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dopeScopeUuid = "dope_scope_uuid"
        case dotPath = "dot_path"
        case elementKind = "element_kind"
        case syncedContentHash = "synced_content_hash"
        case locallyModified = "locally_modified"
    }
}

extension DopeElementProvenanceRecord {
    static let scope = belongsTo(DopeScopeRecord.self).forKey("scope")
}
