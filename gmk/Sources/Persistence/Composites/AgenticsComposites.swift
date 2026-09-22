// GRDB-native composite records for the agentics tables.
//
// A composite is FetchableRecord + Decodable whose properties are Records or
// arrays of Records. Each property name equals the `forKey` name of the
// association that supplies it; the one property naming no association decodes
// from the base row itself. No property maps to a column, so the composite
// needs no column-decoding strategy: every child decodes with its own.

import Foundation
import GRDB

/// One `agent_briefing` row with its three ref classes, fetched in four
/// statements by GRDB rather than one per briefing.
struct AgentBriefingWithRefs: FetchableRecord, Decodable {
    var agentBriefing: AgentBriefingRecord
    var dopeRefs: [AgentBriefingDopePersistenceRecord]
    var kbiteRefs: [AgentBriefingDopeKbiteRecord]
    var fileChangeRefs: [AgentSessionFileChangeRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        AgentBriefingRecord
            .including(all: AgentBriefingRecord.dopeRefs)
            .including(all: AgentBriefingRecord.kbiteRefs)
            .including(all: AgentBriefingRecord.fileChangeRefs)
            .asRequest(of: Self.self)
    }
}

/// One `user_clarification_question` row with its options, in two statements
/// rather than one option query per question.
struct ClarificationQuestionWithOptions: FetchableRecord, Decodable {
    /// NOT `question`: the base row carries a TEXT column of that name, and a
    /// key matching a column wins over the base-row decode, so the record
    /// would be JSON-decoded out of the question text.
    var questionRow: UserClarificationQuestionRecord
    var options: [UserClarificationOptionRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        UserClarificationQuestionRecord
            .all()
            .orderedBySeq()
            .including(all: UserClarificationQuestionRecord.options)
            .asRequest(of: Self.self)
    }
}

/// One `architecture_persistence_change` row with its field changes.
struct ArchPersistenceChangeWithFields: FetchableRecord, Decodable {
    var change: ArchitecturePersistenceChangeRecord
    var fields: [ArchitecturePersistenceFieldChangeRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        ArchitecturePersistenceChangeRecord
            .all()
            .orderedBySeq()
            .including(all: ArchitecturePersistenceChangeRecord.fields)
            .asRequest(of: Self.self)
    }
}

/// One `review_summary` row with its findings.
///
/// The findings carry the read's own ordering — unranked (NULL) first, then
/// rating ascending, then insertion order — so the rating window stays a
/// partition the caller applies to the whole set, never a filter that would
/// drop the stub roster.
struct ReviewSummaryWithFindings: FetchableRecord, Decodable {
    var summary: ReviewSummaryRecord
    var findings: [ReviewFindingRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        ReviewSummaryRecord
            .including(
                all: ReviewSummaryRecord.findings
                    .order(
                        ReviewFindingRecord.Columns.findingRating != nil,
                        ReviewFindingRecord.Columns.findingRating,
                        Column("id")
                    )
            )
            .asRequest(of: Self.self)
    }
}

/// One `file_change` row with the path it changed and its line ranges.
///
/// `relativePath` lives on `session_file`, so it rides the INNER JOIN as an
/// annotation rather than a second record: the wire row carries the path, not
/// the file entity. A `relativePath` filter belongs to the same join and so is
/// taken here rather than at the call site.
struct FileChangeWithRanges: FetchableRecord, Decodable {
    var fileChange: FileChangeRecord
    var relativePath: String
    var ranges: [FileChangeRangeRecord]

    static func request(relativePath: String?) -> QueryInterfaceRequest<Self> {
        let sessionFile = TableAlias<SessionFileRecord>()
        let request =
            FileChangeRecord
            .joining(required: FileChangeRecord.sessionFile.aliased(sessionFile))
            .annotated(
                with: sessionFile[SessionFileRecord.Columns.relativePath].forKey("relativePath")
            )
            .including(all: FileChangeRecord.ranges.order(Column("id")))
            .asRequest(of: Self.self)
        guard let relativePath else { return request }
        return request.filter(sessionFile[SessionFileRecord.Columns.relativePath] == relativePath)
    }
}

/// One `care_package` row with its three ref classes.
struct CarePackageWithRefs: FetchableRecord, Decodable {
    var carePackage: CarePackageRecord
    var dopeRefs: [CarePackageDopeRefRecord]
    var kbiteRefs: [CarePackageKbiteRefRecord]
    var explorationRefs: [CarePackageExplorationRefRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        CarePackageRecord
            .including(all: CarePackageRecord.dopeRefs)
            .including(all: CarePackageRecord.kbiteRefs)
            .including(all: CarePackageRecord.explorationRefs)
            .asRequest(of: Self.self)
    }
}
