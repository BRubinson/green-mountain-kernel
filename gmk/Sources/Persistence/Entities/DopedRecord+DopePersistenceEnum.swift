// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `dope_persistence_enum` table. Columns map via convertFromSnakeCase.
struct DopePersistenceEnumRecord: DopeNodeRecord {
    static let databaseTableName = "dope_persistence_enum"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var dopePersistenceUuid: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var repoRepresentativeFile: String?
    var deletedOn: String?
}
