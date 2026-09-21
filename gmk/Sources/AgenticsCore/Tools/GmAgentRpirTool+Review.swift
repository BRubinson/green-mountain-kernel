// The review phase as one tool: findings, the calibrated rank, resolutions and the verdict.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeRpirReviewArguments: Sendable {

    @Guide(
        description: """
            Which part of the review this call is: open | write | rank | \
            complete | resolve | get.
            """,
        .anyOf(GmAgentCdeRpirReviewTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(description: promptUuidGuide("'s review, by uuid — omit to resolve YOUR workflow's prompt"))
    var prompt_uuid: String?

    @Guide(description: summaryUuidGuide(to: "write to", "complaints list"))
    var summary_uuid: String?

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    var expected_version: Int?

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    var agent_name: String?

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID)
    var agent_id: String?

    @Guide(
        description: """
            What kind of problem this is, one of: \
            \(GM_TOOL_ANYOF_REVIEW_KIND.joined(separator: " | ")).
            """
    )
    var kind: String?

    @Guide(description: "Short title for the problem.")
    var title: String?

    @Guide(
        description: """
            The problem itself: what breaks, and the inputs or state that make it \
            break. A claim with no failure case is an opinion.
            """
    )
    var body: String?

    @Guide(description: "Repo-relative file it is in, or empty.")
    var file_path: String?

    @Guide(description: "First line it covers, or 0 if not line-specific.")
    var line_start: Int?

    @Guide(description: "Last line it covers, or 0 if not line-specific.")
    var line_end: Int?

    @Guide(description: GM_TOOL_GUIDE_RATING_OPTIONAL)
    var rating: Int?

    @Guide(
        description: """
            The calibrated batch as "<finding-uuid>:<0-999>" pairs (0 = critical, \
            999 = ignore). One bad pair rejects the whole batch.
            """
    )
    var ratings: [String]?

    @Guide(description: "What the review found, taken as a whole.")
    var overview: String?

    @Guide(
        description: """
            The verdict, one of: \(GM_TOOL_ANYOF_REVIEW_VERDICT.joined(separator: " | ")).
            """
    )
    var verdict: String?

    @Guide(description: "One finding, by uuid: the one being resolved, or the only one to read.")
    var finding_uuid: String?

    @Guide(
        description: """
            How the finding was handled, one of: \
            \(GM_TOOL_ANYOF_REVIEW_RESOLUTION.joined(separator: " | ")). `open` is \
            the initial state, not a resolution.
            """
    )
    var status: String?

    @Guide(description: "Return every finding as a full row, with no stub partition.")
    var full: Bool?

    @Guide(description: GM_TOOL_GUIDE_MAX_RATING)
    var max_rating: Int?

    @Guide(description: "Full-row window as A:B, inclusive rating bounds.")
    var rating_range: String?

    @Guide(description: "page.next_cursor from the previous call. Omit for the first page.")
    var cursor: String?

    @Guide(description: "Page budget in bytes, default 30000 and max 45000.")
    var page_bytes: Int?

    init(
        op: String,
        prompt_uuid: String? = nil,
        summary_uuid: String? = nil,
        expected_version: Int? = nil,
        agent_name: String? = nil,
        agent_id: String? = nil,
        kind: String? = nil,
        title: String? = nil,
        body: String? = nil,
        file_path: String? = nil,
        line_start: Int? = nil,
        line_end: Int? = nil,
        rating: Int? = nil,
        ratings: [String]? = nil,
        overview: String? = nil,
        verdict: String? = nil,
        finding_uuid: String? = nil,
        status: String? = nil,
        full: Bool? = nil,
        max_rating: Int? = nil,
        rating_range: String? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.prompt_uuid = prompt_uuid
        self.summary_uuid = summary_uuid
        self.expected_version = expected_version
        self.agent_name = agent_name
        self.agent_id = agent_id
        self.kind = kind
        self.title = title
        self.body = body
        self.file_path = file_path
        self.line_start = line_start
        self.line_end = line_end
        self.rating = rating
        self.ratings = ratings
        self.overview = overview
        self.verdict = verdict
        self.finding_uuid = finding_uuid
        self.status = status
        self.full = full
        self.max_rating = max_rating
        self.rating_range = rating_range
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}

// swiftlint:enable identifier_name

struct GmAgentCdeRpirReviewTool: GmAgentRpirTool {

    enum Op: String, CaseIterable, Sendable {
        case open
        case write
        case rank
        case complete
        case resolve
        case get
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.open,
            verbs: [.reviewOpen],
            requiredParams: ["prompt_uuid"],
            summary: """
                Open the prompt's review summary. Like the other summaries, opened \
                explicitly rather than as a side effect of a status move.
                """
        ),
        GmAgentToolOp(
            Op.write,
            verbs: [.reviewFindingAdd],
            requiredParams: ["summary_uuid", "kind", "title", "body", "agent_name"],
            summary: "Insert ONE review finding, self-rated 0 = critical … 999 = ignore."
        ),
        GmAgentToolOp(
            Op.rank,
            verbs: [.reviewRank],
            requiredParams: ["summary_uuid", "ratings"],
            summary: """
                Apply the calibrated rating batch. Version-less and atomic: ranking is \
                CROSS-AGENT calibration and belongs to one reader, so an agent rates only \
                its own findings and never calls this. Primary only.
                """
        ),
        GmAgentToolOp(
            Op.complete,
            verbs: [.reviewComplete],
            requiredParams: ["summary_uuid", "expected_version", "overview", "verdict"],
            summary: "Seal the review with its overview and verdict."
        ),
        GmAgentToolOp(
            Op.resolve,
            verbs: [.reviewResolve],
            requiredParams: ["finding_uuid", "expected_version", "status"],
            summary: """
                Resolve ONE finding during the fix loop. `open` is deliberately not \
                accepted — it is the initial state, so resolving TO it would move \
                backwards through an append-only record.
                """
        ),
        GmAgentToolOp(
            Op.get,
            verbs: [.reviewGet],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "finding_uuid"],
                retryWith: "cde_rpir_review op=get with cursor = page.next_cursor; finding_uuid for one body"
            ),
            requiredParams: [],
            summary: """
                The prompt's review record: summary, findings inside the rating window, \
                stubs outside it. Same window semantics as cde_rpir_explore op=get.
                """
        ),
    ]

    typealias Arguments = GmAgentCdeRpirReviewArguments

    typealias Output = String

    let name = "cde_rpir_review"

    let description = """
        The review record: open the complaints list, write findings, rank them, \
        resolve them during the fix loop, seal the verdict, and read it back. \
        Pick the part with `op`.
        """

    init() {}
}
