// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `review_finding` table.
///
/// Columns map via convertFromSnakeCase.
struct ReviewFindingRecord: BaseRecordFields, TableRecord, Rankable, ParentKeyed {
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

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case reviewSummaryUuid = "review_summary_uuid"
        case kind
        case title
        case body
        case filePath = "file_path"
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case agentName = "agent_name"
        case agentId = "agent_id"
        case findingRating = "finding_rating"
        case status
    }
}

extension ReviewFindingRecord {
    static let parentColumn = Column("review_summary_uuid")
    static let summary = belongsTo(ReviewSummaryRecord.self).forKey("summary")
}
