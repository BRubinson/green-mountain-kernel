import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenReviewArguments: Sendable {
    @Guide(description: "Which prompt to review, by uuid.")
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenReviewTool: GmAgentCdeTool {
    public let name = "cde_open_review"
    public let description = "Start the complaints list."

    public init() {}

    public func call(arguments: GmAgentCdeOpenReviewArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_OPEN")
    }
}

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

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeGetReviewTool: GmAgentCdeTool {
    public let name = "cde_get_review"
    public let description = "Show me the complaints so far."

    public init() {}

    public func call(arguments: GmAgentCdeGetReviewArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_GET")
    }
}
