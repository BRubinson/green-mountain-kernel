// Composite read shapes over the identity-spine tables.
//
// A composite is a decode target for one request: its properties are Records,
// arrays of Records, or annotated scalars, and it owns the request that fills
// it. Wire mapping lives in Mapping/, never here.

import Foundation
import GRDB

/// A session row carried with its recency annotation.
///
/// `session` names no column and no scope, so GRDB decodes it from the base
/// row through `SessionRecord.init(row:)`, which applies that record's own
/// snake_case strategy. `lastActivityAt` decodes from the annotation's alias.
struct SessionSummary: FetchableRecord, Decodable {
    var session: SessionRecord
    var lastActivityAt: String

    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord.annotated(with: SqlAnnotations.lastActivityAt).asRequest(of: Self.self)
    }

    /// The same shape joined to the parent instance. `session` carries no
    /// `project_uuid`, so project scope rides this join, and the caller
    /// constrains the instance further through the alias it passes in — the
    /// join has to be applied before `asRequest(of:)` rebinds the decoder.
    static func request(
        instance: TableAlias<InstanceRecord>,
        projectUuid: String?
    ) -> QueryInterfaceRequest<Self> {
        let request =
            SessionRecord
            .annotated(with: SqlAnnotations.lastActivityAt)
            .joining(required: SessionRecord.instance.aliased(instance))
            .asRequest(of: Self.self)
        guard let projectUuid else { return request }
        return request.filter(instance[InstanceRecord.Columns.projectUuid] == projectUuid)
    }
}

/// A session row carried with its activation registry.
///
/// `session` names no column and no scope, so GRDB decodes it from the base
/// row through `SessionRecord.init(row:)`. The prefetch always yields an
/// array, empty when the session holds no claim.
struct SessionWithActivations: FetchableRecord, Decodable {
    var session: SessionRecord
    var activations: [PromptActivationRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord
            .including(all: SessionRecord.activations.orderedByCreatedAt())
            .asRequest(of: Self.self)
    }
}

/// One session's lineage keys, gathered across the two tiers above it.
///
/// The branch a promotion is allowed from is configured on the project, so the
/// predicate needs the session's code, its project and that project's primary
/// branch together; each is annotated under the key its property carries.
struct SessionLineage: FetchableRecord, Decodable {
    var sessionCode: String
    var projectUuid: String
    var primaryBranch: String

    static func request(sessionUuid: String) -> QueryInterfaceRequest<Self> {
        let instance = TableAlias<InstanceRecord>()
        let project = TableAlias<ProjectRecord>()
        return
            SessionRecord
            .all()
            .withUuid(sessionUuid)
            .joining(
                required: SessionRecord.instance
                    .aliased(instance)
                    .joining(required: InstanceRecord.project.aliased(project))
            )
            .select(
                SessionRecord.Columns.code.forKey("sessionCode"),
                instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid"),
                project[ProjectRecord.Columns.primaryProjectBranch].forKey("primaryBranch")
            )
            .asRequest(of: Self.self)
    }
}

extension DerivableRequest {
    /// Keeps only the rows whose own `prompt_uuid` belongs to this session. A
    /// nil session reads every prompt's rows, the way the unscoped listing does.
    fileprivate func forSessionPrompts(_ sessionUuid: String?) -> Self {
        guard let sessionUuid else { return self }
        return filter(
            PromptRecord
                .select(PromptRecord.Columns.uuid)
                .filter(PromptRecord.Columns.sessionUuid == sessionUuid)
                .contains(Column("prompt_uuid"))
        )
    }
}

/// One clarification summary carried with the counts its listing stub reads.
///
/// `summary` names no column and no scope, so GRDB decodes it from the base
/// row. The two question counts ride the same association under distinct keys,
/// which is what keeps them two joins and two COUNT(DISTINCT)s rather than one
/// join counted twice. The care package hangs off a hasOne, which carries no
/// aggregate, so its readiness stays an EXISTS annotation.
struct ClarificationReport: FetchableRecord, Decodable {
    var summary: ClarificationSummaryRecord
    var questionCount: Int
    var openQuestionCount: Int
    var noteCount: Int
    var carePackageReady: Bool

    private static let carePackageProbe: SQLSelection = SQL(
        sql: """
            EXISTS(SELECT 1 FROM care_package cp
                    WHERE cp.clarification_summary_uuid = clarification_summary.uuid
                      AND cp.status = 'ready')
            """
    )
    .forKey("carePackageReady")

    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        ClarificationSummaryRecord
            .annotated(
                with: ClarificationSummaryRecord.questions
                    .unordered()
                    .count
                    .forKey("questionCount")
            )
            .annotated(
                with: ClarificationSummaryRecord.questions
                    .unordered()
                    .filter(UserClarificationQuestionRecord.Columns.status == "open")
                    .forKey("openQuestions")
                    .count
                    .forKey("openQuestionCount")
            )
            .annotated(with: ClarificationSummaryRecord.notes.count.forKey("noteCount"))
            .annotated(with: [Self.carePackageProbe])
            .forSessionPrompts(sessionUuid)
            .asRequest(of: Self.self)
    }
}

/// One architecture summary carried with its two change counts.
///
/// Both counts are one-hop association aggregates, so the whole shape is the
/// query interface's own: no subquery survives here.
struct ArchitectureReport: FetchableRecord, Decodable {
    var summary: ArchitectureSummaryRecord
    var persistenceChangeCount: Int
    var generalChangeCount: Int

    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        ArchitectureSummaryRecord
            .annotated(
                with: ArchitectureSummaryRecord.persistenceChanges
                    .unordered()
                    .count
                    .forKey("persistenceChangeCount")
            )
            .annotated(
                with: ArchitectureSummaryRecord.generalChanges
                    .unordered()
                    .count
                    .forKey("generalChangeCount")
            )
            .forSessionPrompts(sessionUuid)
            .asRequest(of: Self.self)
    }
}

/// One prompt's exploration report, folded across its per-agent summaries.
///
/// Summaries are per-agent rows keyed UNIQUE(prompt_uuid, agent_type), so the
/// stub is a GROUP BY prompt_uuid: the representative identity is a pivot that
/// prefers the synthesis row, and the three finding counts reach two tables
/// down. Neither shape is an association aggregate, so both stay annotations
/// riding the typed request.
struct ExplorationReport: FetchableRecord, Decodable {
    var promptUuid: String
    var repUuid: String
    var repVersion: Int64
    var repStatus: String
    var keyFileCount: Int
    var findingCount: Int
    var sub100FindingCount: Int
    var unrankedFindingCount: Int

    private static let pivot: [SQLSelection] = [
        SQL(
            sql: """
                COALESCE(
                    MAX(CASE WHEN exploration_summary.agent_type = 'synthesis'
                             THEN exploration_summary.uuid END),
                    MIN(exploration_summary.uuid))
                """
        )
        .forKey("repUuid"),
        SQL(
            sql: """
                COALESCE(
                    MAX(CASE WHEN exploration_summary.agent_type = 'synthesis'
                             THEN exploration_summary.version END),
                    0)
                """
        )
        .forKey("repVersion"),
        SQL(
            sql: """
                COALESCE(
                    MAX(CASE WHEN exploration_summary.agent_type = 'synthesis'
                             THEN exploration_summary.status END),
                    'exploring')
                """
        )
        .forKey("repStatus"),
    ]

    /// key_file findings are path anchors: counted on their own and excluded
    /// from the ranking math the other two counts do.
    private static let findingCounts: [SQLSelection] = [
        SQL(sql: findingScalar("COALESCE(SUM(f.kind = 'key_file'), 0)", excludingKeyFiles: false))
            .forKey("keyFileCount"),
        SQL(sql: findingScalar("COUNT(*)", excludingKeyFiles: true))
            .forKey("findingCount"),
        SQL(
            sql: findingScalar(
                "COALESCE(SUM(f.finding_rating < 100), 0)",
                excludingKeyFiles: true
            )
        )
        .forKey("sub100FindingCount"),
        SQL(
            sql: findingScalar(
                "COUNT(*)",
                excludingKeyFiles: true,
                extra: "AND f.finding_rating IS NULL"
            )
        )
        .forKey("unrankedFindingCount"),
    ]

    private static func findingScalar(
        _ aggregate: String,
        excludingKeyFiles: Bool,
        extra: String = ""
    ) -> String {
        """
        (SELECT \(aggregate)
         FROM exploration_finding f
         JOIN exploration_summary es ON es.uuid = f.exploration_summary_uuid
         WHERE es.prompt_uuid = exploration_summary.prompt_uuid
         \(excludingKeyFiles ? "AND f.kind != 'key_file'" : "") \(extra))
        """
    }

    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        ExplorationSummaryRecord
            .select(
                [ExplorationSummaryRecord.Columns.promptUuid.forKey("promptUuid")]
                    + Self.pivot + Self.findingCounts
            )
            .forSessionPrompts(sessionUuid)
            .group(ExplorationSummaryRecord.Columns.promptUuid)
            .asRequest(of: Self.self)
    }
}

/// One review summary carried with the four counts its stub reads.
///
/// All four count the same children under different predicates, so they ride
/// ONE left join and one GROUP BY rather than the four joins four association
/// aggregates would open over a table that holds dozens of rows per summary.
struct ReviewReport: FetchableRecord, Decodable {
    var summary: ReviewSummaryRecord
    var findingCount: Int
    var sub100FindingCount: Int
    var unrankedFindingCount: Int
    var openFindingCount: Int

    private static let counts: [SQLSelection] = [
        SQL(sql: "COUNT(finding.uuid)").forKey("findingCount"),
        SQL(sql: "COALESCE(SUM(finding.finding_rating < 100), 0)")
            .forKey("sub100FindingCount"),
        SQL(sql: "COUNT(finding.uuid) - COUNT(finding.finding_rating)")
            .forKey("unrankedFindingCount"),
        SQL(sql: "COALESCE(SUM(finding.status = 'open'), 0)").forKey("openFindingCount"),
    ]

    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        let finding = TableAlias<ReviewFindingRecord>(name: "finding")
        return
            ReviewSummaryRecord
            .joining(optional: ReviewSummaryRecord.findings.aliased(finding))
            .annotated(with: Self.counts)
            .forSessionPrompts(sessionUuid)
            .group(ReviewSummaryRecord.Columns.uuid)
            .asRequest(of: Self.self)
    }
}

/// The prompt row the listing surfaces, ordered the way its scope reads.
///
/// `prompt` names no column and no scope, so GRDB decodes it from the base
/// row through `PromptRecord.init(row:)`. The report enrichment PROMPT_LIST
/// can attach is not part of this shape: it is four grouped aggregations over
/// other tables, folded in by the caller, never a per-row subquery.
struct PromptSummary: FetchableRecord, Decodable {
    var prompt: PromptRecord

    /// A nil `sessionUuid` reads every prompt in the db, where `seq` is unique
    /// only inside one session and so orders under its parent.
    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        guard let sessionUuid else {
            return
                PromptRecord
                .order(PromptRecord.Columns.sessionUuid, PromptRecord.Columns.seq)
                .asRequest(of: Self.self)
        }
        return
            PromptRecord
            .filter(PromptRecord.Columns.sessionUuid == sessionUuid)
            .orderedBySeq()
            .asRequest(of: Self.self)
    }
}
