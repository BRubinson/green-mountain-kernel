// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// The five dope tree tables share one soft-delete shape: BaseEntity columns
/// plus `deleted_on`.
///
/// This lets DopeRepository.fetchDopeTree build every node's DopeNodeIdentity through one generic helper instead of
/// five copies.
protocol DopeNodeRecord: BaseRecordFields {
    var createdAt: String { get }
    var updatedAt: String { get }
    var deletedOn: String? { get }
}
