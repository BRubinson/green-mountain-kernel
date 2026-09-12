// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `clarification_summary` table (m0025: slimmed —
/// backstory_note/refined_goal/refined_detail are gone; clarified intent
/// lives on the care package). Columns map via convertFromSnakeCase.
struct ClarificationSummaryRecord: BaseRecordFields {
    static let databaseTableName = "clarification_summary"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var promptUuid: String
    var status: String
}

/// Read-side mirror of `user_clarification_question` (m0025 split).
struct UserClarificationQuestionRecord: BaseRecordFields {
    static let databaseTableName = "user_clarification_question"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var seq: Int64
    var question: String
    var status: String
    var answerText: String?
    var agentId: String?
    var agentName: String?
}

/// Read-side mirror of `user_clarification_option`.
struct UserClarificationOptionRecord: BaseRecordFields {
    static let databaseTableName = "user_clarification_option"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var questionUuid: String
    var seq: Int64
    var body: String
}

/// Read-side mirror of `user_clarification_answer` (selection junction).
struct UserClarificationAnswerRecord: BaseRecordFields {
    static let databaseTableName = "user_clarification_answer"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var questionUuid: String
    var optionUuid: String
}

/// Read-side mirror of `internal_clarification_note`.
struct InternalClarificationNoteRecord: BaseRecordFields {
    static let databaseTableName = "internal_clarification_note"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var clarificationSummaryUuid: String
    var body: String
    var confusedEntityUuid: String?
    var confusedEntityType: String?
    var weight: Int64?
    var questionUuid: String?
    var agentId: String?
    var agentName: String?
}

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

/// Read-side mirror of `care_package_dope_ref` (dot-path CODES).
struct CarePackageDopeRefRecord: BaseRecordFields {
    static let databaseTableName = "care_package_dope_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var dopeCode: String
    var note: String?
    var seq: Int64
}

/// Read-side mirror of `care_package_kbite_ref`.
struct CarePackageKbiteRefRecord: BaseRecordFields {
    static let databaseTableName = "care_package_kbite_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var kbiteResourceFileUuid: String
    var brief: String?
    var seq: Int64
}

/// Read-side mirror of `care_package_exploration_ref` (curated copies).
struct CarePackageExplorationRefRecord: BaseRecordFields {
    static let databaseTableName = "care_package_exploration_ref"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var carePackageUuid: String
    var curatedTitle: String
    var curatedBody: String
    var filePath: String?
    var sourceFindingUuid: String?
    var seq: Int64
}

extension ClarificationSummaryRecord {
    /// db → wire.
    func wireRow() -> ClarificationSummaryRow {
        ClarificationSummaryRow(
            uuid: uuid, version: version, promptUuid: promptUuid,
            status: status, createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension UserClarificationQuestionRecord {
    /// db → wire. Options + selections are fetched by the repository and
    /// injected — the record stays a plain single-table mirror.
    func wireRow(
        options: [ClarificationOptionRow], selectedOptionUuids: [String]
    ) -> ClarificationQuestionRow {
        ClarificationQuestionRow(
            uuid: uuid, version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            seq: seq, question: question, status: status,
            answerText: answerText, agentId: agentId, agentName: agentName,
            options: options, selectedOptionUuids: selectedOptionUuids)
    }
}

extension UserClarificationOptionRecord {
    func wireRow() -> ClarificationOptionRow {
        ClarificationOptionRow(uuid: uuid, seq: seq, body: body)
    }
}

extension InternalClarificationNoteRecord {
    func wireRow() -> ClarificationNoteRow {
        ClarificationNoteRow(
            uuid: uuid, version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            body: body, confusedEntityUuid: confusedEntityUuid,
            confusedEntityType: confusedEntityType,
            weight: weight.map(Int.init), questionUuid: questionUuid,
            agentId: agentId, agentName: agentName)
    }
}

extension CarePackageRecord {
    /// db → wire, children injected by the repository.
    func wireRow(
        dopeRefs: [CarePackageDopeRefRow],
        kbiteRefs: [CarePackageKbiteRefRow],
        explorationRefs: [CarePackageExplorationRefRow]
    ) -> CarePackageRow {
        CarePackageRow(
            uuid: uuid, version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            clarifiedIntent: clarifiedIntent, status: status,
            dopeScopeUuid: dopeScopeUuid, dopeScopeRevision: dopeScopeRevision,
            dopeRefs: dopeRefs, kbiteRefs: kbiteRefs, explorationRefs: explorationRefs,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension CarePackageDopeRefRecord {
    func wireRow() -> CarePackageDopeRefRow {
        CarePackageDopeRefRow(uuid: uuid, dopeCode: dopeCode, note: note, seq: Int(seq))
    }
}

extension CarePackageKbiteRefRecord {
    func wireRow() -> CarePackageKbiteRefRow {
        CarePackageKbiteRefRow(
            uuid: uuid, kbiteResourceFileUuid: kbiteResourceFileUuid, brief: brief, seq: Int(seq))
    }
}

extension CarePackageExplorationRefRecord {
    func wireRow() -> CarePackageExplorationRefRow {
        CarePackageExplorationRefRow(
            uuid: uuid, curatedTitle: curatedTitle, curatedBody: curatedBody,
            filePath: filePath, sourceFindingUuid: sourceFindingUuid, seq: Int(seq))
    }
}
