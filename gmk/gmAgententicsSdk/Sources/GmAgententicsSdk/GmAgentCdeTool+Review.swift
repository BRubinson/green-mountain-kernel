import Foundation
import FoundationModels
import GmDaemonSdk

// THE ENTIRE REVIEW FAMILY IS DERIVED.
//
// The prompt behind this surface asks for it in one bracketed aside and names
// none of the tools: "Add the a similar explore + clarify type stage for the
// writing of the review stuff where each agent opens review then one goes
// through them and proposes clarify like questions then implements (implements
// is currently off the books besides change detection".
//
// So the shape below is inferred from the exploration family it is told to
// mirror — open, write, rank, complete, plus the resolve that exploration has no
// equivalent of. Every type here needs sign-off in a way the explicitly-named
// tools do not.
//
// AND THE MIRROR IS NOT EXACT, which is the part that must not be papered over.
// See `GmAgentCdeOpenReviewTool`.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenReviewArguments: Sendable {
    @Guide(description: "Which prompt to review, by uuid.")
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Start the complaints list.
///
/// ONE ROW PER PROMPT, NOT PER AGENT — and the aside this family is derived from
/// says "each agent opens review", so the difference is worth being explicit
/// about rather than quietly resolving.
///
/// `EXPLORE_OPEN` takes `agent_type` and `agent_id` and gives each explorer its
/// own summary row. `REVIEW_OPEN` takes ONLY `prompt_uuid`. There is no
/// `agent_type` column on `review_summary` at all, so reviewers share a single
/// summary and are distinguished only by the `agentName` recorded on each
/// finding they write.
///
/// Making review genuinely per-agent is therefore a SCHEMA change, not a tool
/// change: it needs a new column and a new uniqueness shape. Dropping
/// `review_summary`'s per-prompt UNIQUE constraint is a precondition for it but
/// nowhere near sufficient. Adding an `agentType` parameter here that the verb
/// ignores would be the worst of both — it would read as supported and do
/// nothing.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenReviewTool: GmAgentCdeTool {
    public let name = "cde_open_review"
    public let description = "Start the complaints list."

    public init() {}

    public func call(arguments: GmAgentCdeOpenReviewArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_OPEN")
    }
}

/// One review finding.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentReviewFinding: Sendable {
    @Guide(description: "What kind of problem this is.", .anyOf([
        "correctness_bug", "spec_deviation", "regression_risk",
        "security", "simplification", "other",
    ]))
    public var kind: String

    @Guide(description: "Short title for the problem.")
    public var title: String

    @Guide(description: """
        The problem itself: what breaks, and the inputs or state that make it \
        break. A claim with no failure case is an opinion.
        """)
    public var body: String

    @Guide(description: "Repo-relative file it is in, or empty.")
    public var filePath: String

    @Guide(description: "First line it covers, or 0 if not line-specific.")
    public var lineStart: Int

    @Guide(description: "Last line it covers, or 0 if not line-specific.")
    public var lineEnd: Int

    /// OPTIONAL for the same reason `GmAgentExplorationFinding.rating` is: nil
    /// means UNRANKED, and `REVIEW_COMPLETE` refuses while any finding is
    /// unranked. Making it non-optional would satisfy that gate automatically
    /// and silently, which is the failure that looks like success.
    @Guide(description: "How bad, 0 is most severe and 999 is ignore. Leave it out unless ranking.")
    public var rating: Int?

    public init(
        kind: String, title: String, body: String, filePath: String = "",
        lineStart: Int = 0, lineEnd: Int = 0, rating: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.rating = rating
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeWriteReviewsArguments: Sendable {
    @Guide(description: "Which complaints list to write to, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Who is reviewing. This is what tells reviewers apart.")
    public var agentName: String

    @Guide(description: "All the problems found, in one go.")
    public var findings: [GmAgentReviewFinding]

    public init(summaryUuid: String, agentName: String, findings: [GmAgentReviewFinding]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.findings = findings
    }
}

/// Write down many complaints.
///
/// `agentName` carries more weight here than in exploration: since every
/// reviewer writes into ONE shared summary, it is the only thing distinguishing
/// one reviewer's findings from another's.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteReviewsTool: GmAgentCdeTool {
    public let name = "cde_write_reviews"
    public let description = "Write down many complaints."

    public init() {}

    public func call(arguments: GmAgentCdeWriteReviewsArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_FINDING_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeRankReviewsArguments: Sendable {
    @Guide(description: "Which complaints list to rank, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Every problem and its rating, all at once.")
    public var ratings: [GmAgentFindingRating]

    public init(summaryUuid: String, ratings: [GmAgentFindingRating]) {
        self.summaryUuid = summaryUuid
        self.ratings = ratings
    }
}

/// Give every complaint a number, all at once.
///
/// Cross-agent calibration by one reader: a rating has to mean the same thing
/// whichever reviewer wrote the finding, which it cannot if each reviewer scores
/// only its own. Atomic on the wire, and `complete_review` refuses while
/// anything is unranked — so this is a required step, not a tidying one.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeRankReviewsTool: GmAgentCdeTool {
    public let name = "cde_rank_reviews"
    public let description = "Give every complaint a number, all at once."

    public init() {}

    public func call(arguments: GmAgentCdeRankReviewsArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RANK")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeCompleteReviewArguments: Sendable {
    @Guide(description: "Which complaints list to seal, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Version of the list you read.")
    public var expectedVersion: Int

    @Guide(description: "What the review found, taken as a whole.")
    public var overview: String

    @Guide(description: "The verdict.", .anyOf([
        "approved", "approved_with_nits", "changes_requested",
    ]))
    public var verdict: String

    public init(summaryUuid: String, expectedVersion: Int, overview: String, verdict: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
        self.verdict = verdict
    }
}

/// Complaints done, here is the verdict.
///
/// Refuses while any finding is unranked — rank first. The verdict is stored
/// only here, and a complete review must have one.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeCompleteReviewTool: GmAgentCdeTool {
    public let name = "cde_complete_review"
    public let description = "Complaints done, here is the verdict."

    public init() {}

    public func call(arguments: GmAgentCdeCompleteReviewArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeResolveReviewFindingArguments: Sendable {
    @Guide(description: "Which problem was handled, by uuid.")
    public var findingUuid: String

    @Guide(description: "Version of the finding you read.")
    public var expectedVersion: Int

    @Guide(description: "How it was handled.", .anyOf(["fixed", "accepted", "wont_fix"]))
    public var status: String

    public init(findingUuid: String, expectedVersion: Int, status: String) {
        self.findingUuid = findingUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

/// This complaint is handled.
///
/// Legal AFTER the review is sealed, by design — the fix loop runs post-seal, so
/// this is the one write in the family that a completed summary still accepts.
/// `accepted` and `wont_fix` are real outcomes, not evasions: a finding the
/// author disagrees with is resolved by saying so, on the record, rather than by
/// leaving it open forever.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeResolveReviewFindingTool: GmAgentCdeTool {
    public let name = "cde_resolve_review_finding"
    public let description = "This complaint is handled."

    public init() {}

    public func call(
        arguments: GmAgentCdeResolveReviewFindingArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RESOLVE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeGetReviewArguments: Sendable {
    @Guide(description: "Which prompt's review to read, by uuid.")
    public var promptUuid: String

    @Guide(description: """
        Only return problems this bad or worse, 0 to 999. Use a small number to \
        keep the answer short.
        """, .range(0...999))
    public var maxRating: Int

    public init(promptUuid: String, maxRating: Int = 100) {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
    }
}

/// Show me the complaints so far.
///
/// DERIVED, and narrowed by `maxRating` like every other read here.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeGetReviewTool: GmAgentCdeTool {
    public let name = "cde_get_review"
    public let description = "Show me the complaints so far."

    public init() {}

    public func call(arguments: GmAgentCdeGetReviewArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_GET")
    }
}
