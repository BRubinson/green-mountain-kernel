// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of `care_package`.
struct CarePackageRecord: BaseRecordFields {
    static let databaseTableName = "care_package"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var clarifiedIntent: String
    var status: String
    var dopeScopeUuid: String?
    var dopeScopeRevision: Int64?
}

extension CarePackageRecord {
    /// db → wire, children injected by the repository.
    func wireRow(
        dopeRefs: [CarePackageDopeRefRow],
        kbiteRefs: [CarePackageKbiteRefRow],
        explorationRefs: [CarePackageExplorationRefRow]
    ) -> CarePackageRow {
        CarePackageRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            clarifiedIntent: clarifiedIntent,
            status: status,
            dopeScopeUuid: dopeScopeUuid,
            dopeScopeRevision: dopeScopeRevision,
            dopeRefs: dopeRefs,
            kbiteRefs: kbiteRefs,
            explorationRefs: explorationRefs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
