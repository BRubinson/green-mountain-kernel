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

    /// Fetches a session and its recency annotation.
    /// - Returns: A request that fetches sessions with `lastActivityAt` annotated.
    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord.annotated(with: SqlAnnotations.lastActivityAt).asRequest(of: Self.self)
    }

    /// Fetches a session joined to the parent instance with project scope.
    ///
    /// `session` carries no `project_uuid`, so project scope rides this join.
    /// The caller constrains the instance further through the alias it passes
    /// in — the join has to be applied before `asRequest(of:)` rebinds the
    /// decoder.
    /// - Parameters:
    ///   - instance: The instance table alias for the join.
    ///   - projectUuid: The project to filter by, or nil for all projects.
    /// - Returns: A request that fetches sessions joined to the instance.
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

    /// Fetches a session with its activation records.
    /// - Returns: A request that fetches sessions with activations ordered by
    ///   creation time.
    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord
            .including(all: SessionRecord.activations.orderedByCreatedAt())
            .asRequest(of: Self.self)
    }
}

/// One row's identity lineage: the session, its code, its instance, its
/// project and that project's primary branch, reachable from a session or
/// from a prompt.
///
/// The promotion guard, the dope scope tier ladder and the diagram owner
/// chain each read a subset; one join serves all three, each key annotated
/// under the property it decodes into.
struct SessionLineage: FetchableRecord, Decodable {
    var sessionUuid: String
    var sessionCode: String
    var instanceUuid: String
    var projectUuid: String
    var primaryBranch: String

    /// Fetches a session's lineage joined from instance and project.
    /// - Parameter sessionUuid: The session to fetch lineage for.
    /// - Returns: A request that fetches the five lineage keys.
    static func request(sessionUuid: String) -> QueryInterfaceRequest<Self> {
        let session = TableAlias<SessionRecord>()
        let instance = TableAlias<InstanceRecord>()
        let project = TableAlias<ProjectRecord>()
        return
            SessionRecord
            .aliased(session)
            .withUuid(sessionUuid)
            .joining(
                required: SessionRecord.instance
                    .aliased(instance)
                    .joining(required: InstanceRecord.project.aliased(project))
            )
            .select(Self.selection(session: session, instance: instance, project: project))
            .asRequest(of: Self.self)
    }

    /// Fetches a prompt's lineage joined from session, instance and project.
    /// - Parameter promptUuid: The prompt to fetch lineage for.
    /// - Returns: A request that fetches the five lineage keys.
    static func request(promptUuid: String) -> QueryInterfaceRequest<Self> {
        let session = TableAlias<SessionRecord>()
        let instance = TableAlias<InstanceRecord>()
        let project = TableAlias<ProjectRecord>()
        return
            PromptRecord
            .all()
            .withUuid(promptUuid)
            .joining(
                required: PromptRecord.session
                    .aliased(session)
                    .joining(
                        required: SessionRecord.instance
                            .aliased(instance)
                            .joining(required: InstanceRecord.project.aliased(project))
                    )
            )
            .select(Self.selection(session: session, instance: instance, project: project))
            .asRequest(of: Self.self)
    }

    /// The five keys under the property names they decode into.
    /// - Parameters:
    ///   - session: The session table alias.
    ///   - instance: The instance table alias.
    ///   - project: The project table alias.
    /// - Returns: The selections for one lineage row.
    private static func selection(
        session: TableAlias<SessionRecord>,
        instance: TableAlias<InstanceRecord>,
        project: TableAlias<ProjectRecord>
    ) -> [any SQLSelectable] {
        [
            session[SessionRecord.Columns.uuid].forKey("sessionUuid"),
            session[SessionRecord.Columns.code].forKey("sessionCode"),
            session[SessionRecord.Columns.instanceUuid].forKey("instanceUuid"),
            instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid"),
            project[ProjectRecord.Columns.primaryProjectBranch].forKey("primaryBranch"),
        ]
    }
}

/// The file-change tally one scope surfaces: how many changes it holds, how
/// many distinct files they touched, and the total line span of their ranges.
///
/// The ranges ride a LEFT JOIN so a change carrying none still counts and its
/// span contributes zero. The aggregate carries no GROUP BY, so an empty scope
/// still yields one row of zeroes.
struct ChangeRollup: FetchableRecord, Decodable {
    var changeCount: Int
    var distinctFiles: Int
    var totalLineSpan: Int

    /// Fetches file-change tallies for a session.
    /// - Parameter sessionUuid: The session to tally changes for.
    /// - Returns: A request that fetches the change tally.
    static func request(sessionUuid: String) -> QueryInterfaceRequest<Self> {
        Self.base().filter(FileChangeRecord.Columns.sessionUuid == sessionUuid)
    }

    /// Fetches file-change tallies for a prompt.
    /// - Parameter promptUuid: The prompt to tally changes for.
    /// - Returns: A request that fetches the change tally.
    static func request(promptUuid: String) -> QueryInterfaceRequest<Self> {
        Self.base().filter(FileChangeRecord.Columns.promptUuid == promptUuid)
    }

    /// Builds SQL selections for file-change tally aggregates.
    /// - Parameter range: The file change range table alias for line span
    ///   calculations.
    /// - Returns: An array of SQL selections for change count, distinct files,
    ///   and total line span.
    static func tally(
        _ range: TableAlias<FileChangeRangeRecord>
    ) -> [any SQLSelectable] {
        [
            count(distinct: FileChangeRecord.Columns.uuid).forKey("changeCount"),
            count(distinct: FileChangeRecord.Columns.sessionFileUuid).forKey("distinctFiles"),
            (sum(
                range[FileChangeRangeRecord.Columns.lineEnd]
                    - range[FileChangeRangeRecord.Columns.lineStart] + 1
            ) ?? 0)
            .forKey("totalLineSpan"),
        ]
    }

    /// Builds the base request for file-change tallies with range joins.
    /// - Returns: A request that fetches change tallies with optional range
    ///   joins.
    private static func base() -> QueryInterfaceRequest<Self> {
        let range = TableAlias<FileChangeRangeRecord>()
        return
            FileChangeRecord
            .joining(optional: FileChangeRecord.ranges.aliased(range))
            .select(Self.tally(range))
            .asRequest(of: Self.self)
    }
}

/// The same tally split per prompt, for one session's whole change history.
///
/// `promptUuid` is optional because a change captured outside any activation
/// claim is attributed to no prompt, and that group is a legitimate row.
struct PromptChangeRollup: FetchableRecord, Decodable {
    var promptUuid: String?
    var changeCount: Int
    var distinctFiles: Int
    var totalLineSpan: Int

    /// Fetches file-change tallies split per prompt in a session.
    /// - Parameter sessionUuid: The session to tally changes for.
    /// - Returns: A request that fetches the tally grouped by prompt UUID.
    static func request(sessionUuid: String) -> QueryInterfaceRequest<Self> {
        let range = TableAlias<FileChangeRangeRecord>()
        return
            FileChangeRecord
            .filter(FileChangeRecord.Columns.sessionUuid == sessionUuid)
            .joining(optional: FileChangeRecord.ranges.aliased(range))
            .select([FileChangeRecord.Columns.promptUuid.forKey("promptUuid")] + ChangeRollup.tally(range))
            .group(FileChangeRecord.Columns.promptUuid)
            .order(FileChangeRecord.Columns.promptUuid)
            .asRequest(of: Self.self)
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

    /// Fetches a clarification with question and note counts.
    /// - Parameter sessionUuid: The session to filter by, or nil for all
    ///   sessions.
    /// - Returns: A request that fetches clarifications with annotated counts
    ///   and care package readiness.
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

    /// Fetches an architecture summary with annotated change counts.
    ///
    /// Includes counts of persistence and general changes.
    /// - Parameter sessionUuid: The session to filter by, or nil for all
    ///   sessions.
    /// - Returns: A request that fetches architecture summaries with annotated
    ///   change counts.
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

    /// Builds a SQL scalar subquery for exploration finding aggregates.
    /// - Parameters:
    ///   - aggregate: The SQL aggregate function (e.g., `COUNT(*)`).
    ///   - excludingKeyFiles: Whether to exclude key file findings.
    ///   - extra: Additional SQL conditions to append.
    /// - Returns: A SQL scalar subquery string.
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

    /// Fetches an exploration report folded across per-agent summaries.
    /// - Parameter sessionUuid: The session to filter by, or nil for all
    ///   sessions.
    /// - Returns: A request that fetches exploration reports with pivot and
    ///   finding counts.
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

    /// Fetches a review summary with finding counts.
    /// - Parameter sessionUuid: The session to filter by, or nil for all
    ///   sessions.
    /// - Returns: A request that fetches review summaries with annotated
    ///   finding counts.
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
