// Agent tools for the review phase: findings, the rank, resolutions and the verdict.

import Foundation
import FoundationModels

@Generable
public struct GmAgentRpirOpenReviewArguments: Sendable {
    @Guide(description: promptUuidGuide("to review"))
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

public struct GmAgentRpirOpenReviewTool: GmAgentRpirTool {
    public let name = "rpir_open_review"
    public let description = "Start the complaints list."

    public init() {}

    public func call(arguments _: GmAgentRpirOpenReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_OPEN")
    }
}

@Generable
public struct GmAgentReviewFinding: Sendable {
    @Guide(description: "What kind of problem this is.", .anyOf(GM_TOOL_ANYOF_REVIEW_KIND))
    public var kind: String

    @Guide(description: "Short title for the problem.")
    public var title: String

    @Guide(
        description: """
            The problem itself: what breaks, and the inputs or state that make it \
            break. A claim with no failure case is an opinion.
            """
    )
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
        kind: String,
        title: String,
        body: String,
        filePath: String = "",
        lineStart: Int = 0,
        lineEnd: Int = 0,
        rating: Int? = nil
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

@Generable
public struct GmAgentRpirWriteReviewsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "complaints list"))
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

public struct GmAgentRpirWriteReviewsTool: GmAgentRpirTool {
    public let name = "rpir_write_reviews"
    public let description = "Write down many complaints."

    public init() {}

    public func call(arguments _: GmAgentRpirWriteReviewsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_FINDING_ADD (looped)")
    }
}

@Generable
public struct GmAgentRpirRankReviewsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "rank", "complaints list"))
    public var summaryUuid: String

    @Guide(description: "Every problem and its rating, all at once.")
    public var ratings: [GmAgentFindingRating]

    public init(summaryUuid: String, ratings: [GmAgentFindingRating]) {
        self.summaryUuid = summaryUuid
        self.ratings = ratings
    }
}

public struct GmAgentRpirRankReviewsTool: GmAgentRpirTool {
    public let name = "rpir_rank_reviews"
    public let description = "Give every complaint a number, all at once."

    public init() {}

    public func call(arguments _: GmAgentRpirRankReviewsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RANK")
    }
}

@Generable
public struct GmAgentRpirCompleteReviewArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "seal", "complaints list"))
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    public var expectedVersion: Int

    @Guide(description: "What the review found, taken as a whole.")
    public var overview: String

    @Guide(description: "The verdict.", .anyOf(GM_TOOL_ANYOF_REVIEW_VERDICT))
    public var verdict: String

    public init(summaryUuid: String, expectedVersion: Int, overview: String, verdict: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
        self.verdict = verdict
    }
}

public struct GmAgentRpirCompleteReviewTool: GmAgentRpirTool {
    public let name = "rpir_complete_review"
    public let description = "Complaints done, here is the verdict."

    public init() {}

    public func call(arguments _: GmAgentRpirCompleteReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_COMPLETE")
    }
}

@Generable
public struct GmAgentRpirResolveReviewFindingArguments: Sendable {
    @Guide(description: "Which problem was handled, by uuid.")
    public var findingUuid: String

    @Guide(description: "Version of the finding you read.")
    public var expectedVersion: Int

    @Guide(description: "How it was handled.", .anyOf(GM_TOOL_ANYOF_REVIEW_RESOLUTION))
    public var status: String

    public init(findingUuid: String, expectedVersion: Int, status: String) {
        self.findingUuid = findingUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

public struct GmAgentRpirResolveReviewFindingTool: GmAgentRpirTool {
    public let name = "rpir_resolve_review_finding"
    public let description = "This complaint is handled."

    public init() {}

    public func call(
        arguments _: GmAgentRpirResolveReviewFindingArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RESOLVE")
    }
}

@Generable
public struct GmAgentRpirGetReviewArguments: Sendable {
    @Guide(description: promptUuidGuide("'s review to read"))
    public var promptUuid: String

    @Guide(
        description: """
            Only return problems this bad or worse, 0 to 999. Use a small number to \
            keep the answer short.
            """,
        .range(0...999)
    )
    public var maxRating: Int

    public init(promptUuid: String, maxRating: Int = 100) {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
    }
}

public struct GmAgentRpirGetReviewTool: GmAgentRpirTool {
    public let name = "rpir_get_review"
    public let description = "Show me the complaints so far."

    public init() {}

    public func call(arguments _: GmAgentRpirGetReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_GET")
    }
}
