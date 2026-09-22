// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram_uml_node` table. Columns map via convertFromSnakeCase.
struct DiagramUmlNodeRecord: DiagramSubtypeRecord {
    static let databaseTableName = "diagram_uml_node"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var nodeKind: String
    var width: Double
    var height: Double
    var markdown: String
    var fontSize: Double?
    var textColor: String?
    var strokeColor: String?
    var strokeWidth: Double?
    var fillColor: String?
}
