// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `exploration_summary` table (m0025: literal
/// per-agent rows keyed UNIQUE(prompt_uuid, agent_type); the prompt-level
/// synthesis/seal is the row with agent_type='synthesis').
struct ExplorationSummaryRecord: BaseRecordFields {
    static let databaseTableName = "exploration_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var agentType: String
    var agentId: String?
    var status: String
    var overview: String
}

/// Read-side mirror of the `exploration_finding` table (m0025: absorbed
/// exploration_key_file — a key file is a finding of kind 'key_file' with
/// file_path set).
struct ExplorationFindingRecord: BaseRecordFields {
    static let databaseTableName = "exploration_finding"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var explorationSummaryUuid: String
    var kind: String
    var title: String
    var body: String
    var filePath: String?
    var agentName: String
    var agentId: String?
    var findingRating: Int64?
}

extension ExplorationSummaryRecord {
    /// db → wire.
    func wireRow() -> ExplorationSummaryRow {
        ExplorationSummaryRow(
            uuid: uuid, version: version, promptUuid: promptUuid,
            agentType: agentType, agentId: agentId,
            status: status, overview: overview,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension ExplorationFindingRecord {
    /// db → wire.
    ///
    /// findingRating narrows Int64 (the column type) to the wire's Int. The
    /// old `row["finding_rating"]` subscript inferred Int straight from the
    /// target type; this makes the conversion explicit and non-truncating.
    func wireRow() -> ExplorationFindingRow {
        ExplorationFindingRow(
            uuid: uuid, version: version,
            explorationSummaryUuid: explorationSummaryUuid,
            kind: kind, title: title, body: body, filePath: filePath,
            agentName: agentName, agentId: agentId,
            findingRating: findingRating.map(Int.init))
    }
}
