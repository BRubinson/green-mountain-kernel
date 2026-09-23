// The cde_rpir_explore tool: the finding list, its findings, the calibrated rank and the seal.

import Foundation
import FoundationModels

struct GmAgentCdeRpirExploreTool: GmAgentRpirTool {

    typealias Output = String

    /// The ONE spelling of this tool's name.
    static let toolName = "cde_rpir_explore"

    enum Op: String, CaseIterable, Sendable {
        case open
        case write
        case rank
        case complete
        case get
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.open,
            verbs: [.botGet, .exploreOpen],
            summary: """
                Fetch-or-open an exploration summary (identity is the self-reported \
                agent_type; 'synthesis' is the prompt-level seal row the clarifier opens \
                once everything is ranked).
                """,
            requiredParams: ["agent_type"]
        ),
        GmAgentToolOp(
            Op.write,
            verbs: [.exploreFindingAdd],
            summary: """
                Insert ONE exploration finding (self-rate 0=critical…999=ignore; unranked \
                blocks the synthesis seal).
                """,
            requiredParams: ["summary_uuid", "kind", "title", "body", "agent_name"]
        ),
        GmAgentToolOp(
            Op.rank,
            verbs: [.botGet, .exploreRank],
            summary: """
                Batch-rank findings PROMPT-wide: one atomic calibrated batch across every \
                summary. One bad pair rejects the whole batch; 0 unranked is what lets the \
                synthesis seal pass.
                """,
            requiredParams: ["ratings"]
        ),
        GmAgentToolOp(
            Op.complete,
            verbs: [.exploreComplete],
            summary: """
                Seal a summary with its overview — your own methodology row, or the \
                synthesis row once every finding is ranked (it refuses while anything is \
                unranked).
                """,
            requiredParams: ["summary_uuid", "expected_version", "overview"]
        ),
        GmAgentToolOp(
            Op.get,
            verbs: [.botGet, .exploreGet],
            summary: """
                The prompt's exploration record: summaries, key files, findings inside the \
                rating window, stubs outside it. Unranked findings are ALWAYS full rows.
                """,
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "finding_uuid"],
                retryWith: "\(toolName) op=get with cursor = page.next_cursor; finding_uuid for one body"
            )
        ),
    ]

    let name = GmAgentCdeRpirExploreTool.toolName
    let description = """
        The prompt's exploration record: op open starts your finding list, op write adds \
        ONE finding, op rank calibrates them prompt-wide, op complete seals the list with \
        an overview, op get reads the findings back.
        """

    /// Initializes the exploration tool.
    init() {}

    // Argument property names ARE the served tool's snake_case wire argument names.
    // swiftlint:disable identifier_name
    @Generable
    struct Arguments: Sendable {

        @Guide(description: "open | write | rank | complete | get", .anyOf(Op.allCases.map(\.rawValue)))
        var op: String

        @Guide(description: "Explicit prompt uuid (omit to resolve YOUR workflow's prompt) (open, rank, get)")
        var prompt_uuid: String?

        @Guide(
            description:
                "Which methodology you are (open); filter to one methodology's list (get)",
            .anyOf(GM_TOOL_ANYOF_AGENT_TYPE)
        )
        var agent_type: String?

        @Guide(description: GM_TOOL_GUIDE_AGENT_ID + " (open, write)")
        var agent_id: String?

        @Guide(description: GM_TOOL_GUIDE_AGENT_NAME + " (write)")
        var agent_name: String?

        @Guide(description: "Your exploration summary uuid (write, complete)")
        var summary_uuid: String?

        @Guide(description: "The summary version this write was based on (complete)")
        var expected_version: Int?

        @Guide(description: "Your overview narrative (complete)")
        var overview: String?

        @Guide(description: "What kind of finding this is (write)", .anyOf(GM_TOOL_ANYOF_FINDING_KIND))
        var kind: String?

        @Guide(description: "Finding title (write)")
        var title: String?

        @Guide(description: "Finding body (write)")
        var body: String?

        @Guide(description: "Repo-relative anchor path (write)")
        var file_path: String?

        @Guide(description: "0-999 self-rating; leave it out unless you were told to rate (write)")
        var rating: Int?

        @Guide(description: "\"<finding-uuid>:<0-999>\" pairs, every finding at once (rank)")
        var ratings: [String]?

        @Guide(description: "Return every finding as a full row, with no stub partition (get)")
        var full: Bool?

        @Guide(description: "Widen/narrow the full-row window to ratings 0...N (get)")
        var max_rating: Int?

        @Guide(description: "Full-row window as A:B, inclusive rating bounds (get)")
        var rating_range: String?

        @Guide(description: "Return exactly this finding in full and nothing else (get)")
        var finding_uuid: String?

        @Guide(
            description:
                "page.next_cursor from the previous call (opaque) — omit for the first page (get)"
        )
        var cursor: String?

        @Guide(
            description:
                "Page budget in bytes (default 30000, max 45000); every array and every long text is paged inside it (get)"
        )
        var page_bytes: Int?
    }
    // swiftlint:enable identifier_name
}
