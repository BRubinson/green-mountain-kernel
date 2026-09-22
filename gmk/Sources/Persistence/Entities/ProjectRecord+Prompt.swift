// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `prompt` table. Columns map via convertFromSnakeCase.
struct PromptRecord: BaseRecordFields, TableRecord, SeqOrdered {
    static let databaseTableName = "prompt"

    enum Columns: String, ColumnExpression {
        case uuid = "uuid"
        case version = "version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionUuid = "session_uuid"
        case seq = "seq"
        case code = "code"
        case name = "name"
        case backstory = "backstory"
        case goal = "goal"
        case detail = "detail"
        case command = "command"
        case status = "status"
        case gmfsRelativeStoragePath = "gmfs_relative_storage_path"
    }

    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var sessionUuid: String
    var seq: Int64
    var code: String
    var name: String
    var backstory: String
    var goal: String
    var detail: String
    var command: String
    var status: String
    var gmfsRelativeStoragePath: String
}

extension PromptRecord {
    static let session = belongsTo(SessionRecord.self).forKey("session")

    static let artifacts = hasMany(PromptArtifactRecord.self).forKey("artifacts")

    static let activations = hasMany(PromptActivationRecord.self).forKey("activations")

    static let qualifiedDiagrams = hasMany(PromptQualifiedDiagramRecord.self).forKey("qualifiedDiagrams")

    static let activeKbites = hasMany(
        KbiteRecord.self,
        through: hasMany(PromptActiveKbiteRecord.self).forKey("promptActiveKbites"),
        using: PromptActiveKbiteRecord.kbite
    )
    .forKey("activeKbites")

    static let briefings = hasMany(AgentBriefingRecord.self).forKey("briefings")

    static let clarificationSummaries = hasMany(ClarificationSummaryRecord.self).forKey("clarificationSummaries")

    static let architectureSummaries = hasMany(ArchitectureSummaryRecord.self).forKey("architectureSummaries")

    static let explorationSummaries = hasMany(ExplorationSummaryRecord.self).forKey("explorationSummaries")

    static let reviewSummaries = hasMany(ReviewSummaryRecord.self).forKey("reviewSummaries")
}
