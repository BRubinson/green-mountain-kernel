// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `review_summary` table. Columns map via convertFromSnakeCase.
struct ReviewSummaryRecord: BaseRecordFields {
    static let databaseTableName = "review_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
    var verdict: String?
    var overview: String
    var agentId: String?
}

/// Read-side mirror of the `review_finding` table. Columns map via convertFromSnakeCase.
struct ReviewFindingRecord: BaseRecordFields {
    static let databaseTableName = "review_finding"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var reviewSummaryUuid: String
    var kind: String
    var title: String
    var body: String
    var filePath: String?
    var lineStart: Int64?
    var lineEnd: Int64?
    var agentName: String
    var agentId: String?
    var findingRating: Int64?
    var status: String
}

extension ReviewSummaryRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    func wireRow() -> ReviewSummaryRow {
        ReviewSummaryRow(
            uuid: uuid, version: version, promptUuid: promptUuid,
            status: status, verdict: verdict, overview: overview, agentId: agentId,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension ReviewFindingRecord {
    /// db → wire. Replicates the retired hand mapper exactly.
    ///
    /// lineStart/lineEnd/findingRating narrow Int64 (the column type) to the
    /// wire's Int, explicitly and non-truncating.
    func wireRow() -> ReviewFindingRow {
        ReviewFindingRow(
            uuid: uuid, version: version, reviewSummaryUuid: reviewSummaryUuid,
            kind: kind, title: title, body: body, filePath: filePath,
            lineStart: lineStart.map(Int.init), lineEnd: lineEnd.map(Int.init),
            agentName: agentName, findingRating: findingRating.map(Int.init),
            status: status)
    }
}
