// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// The eight diagram element subtype tables share one shape: a row keyed to
/// its parent element. This lets fetchDiagramTree hydrate all eight through a
/// single generic helper instead of eight copies, and lets the helper derive
/// its own table name rather than taking it as a string.
protocol DiagramSubtypeRecord: BaseRecordFields {
    var elementUuid: String { get }
}
