// Agent tools for the review phase: findings, the rank, resolutions and the verdict.

import Foundation
import FoundationModels

@Generable
struct GmAgentRpirOpenReviewArguments: Sendable {
    @Guide(description: promptUuidGuide("to review"))
    var promptUuid: String

    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct GmAgentRpirOpenReviewTool: GmAgentRpirTool {
    let name = "rpir_open_review"
    let description = "Start the complaints list."

    init() {}

    func call(arguments _: GmAgentRpirOpenReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_OPEN")
    }
}

@Generable
struct GmAgentReviewFinding: Sendable {
    @Guide(description: "What kind of problem this is.", .anyOf(GM_TOOL_ANYOF_REVIEW_KIND))
    var kind: String

    @Guide(description: "Short title for the problem.")
    var title: String

    @Guide(
        description: """
            The problem itself: what breaks, and the inputs or state that make it \
            break. A claim with no failure case is an opinion.
            """
    )
    var body: String

    @Guide(description: "Repo-relative file it is in, or empty.")
    var filePath: String

    @Guide(description: "First line it covers, or 0 if not line-specific.")
    var lineStart: Int

    @Guide(description: "Last line it covers, or 0 if not line-specific.")
    var lineEnd: Int

    @Guide(description: "How bad, 0 is most severe and 999 is ignore. Leave it out unless ranking.")
    var rating: Int?

    init(
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
struct GmAgentRpirWriteReviewsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "complaints list"))
    var summaryUuid: String

    @Guide(description: "Who is reviewing. This is what tells reviewers apart.")
    var agentName: String

    @Guide(description: "All the problems found, in one go.")
    var findings: [GmAgentReviewFinding]

    init(summaryUuid: String, agentName: String, findings: [GmAgentReviewFinding]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.findings = findings
    }
}

struct GmAgentRpirWriteReviewsTool: GmAgentRpirTool {
    let name = "rpir_write_reviews"
    let description = "Write down many complaints."

    init() {}

    func call(arguments _: GmAgentRpirWriteReviewsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_FINDING_ADD (looped)")
    }
}

@Generable
struct GmAgentRpirRankReviewsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "rank", "complaints list"))
    var summaryUuid: String

    @Guide(description: "Every problem and its rating, all at once.")
    var ratings: [GmAgentFindingRating]

    init(summaryUuid: String, ratings: [GmAgentFindingRating]) {
        self.summaryUuid = summaryUuid
        self.ratings = ratings
    }
}

struct GmAgentRpirRankReviewsTool: GmAgentRpirTool {
    let name = "rpir_rank_reviews"
    let description = "Give every complaint a number, all at once."

    init() {}

    func call(arguments _: GmAgentRpirRankReviewsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RANK")
    }
}

@Generable
struct GmAgentRpirCompleteReviewArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "seal", "complaints list"))
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    var expectedVersion: Int

    @Guide(description: "What the review found, taken as a whole.")
    var overview: String

    @Guide(description: "The verdict.", .anyOf(GM_TOOL_ANYOF_REVIEW_VERDICT))
    var verdict: String

    init(summaryUuid: String, expectedVersion: Int, overview: String, verdict: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
        self.verdict = verdict
    }
}

struct GmAgentRpirCompleteReviewTool: GmAgentRpirTool {
    let name = "rpir_complete_review"
    let description = "Complaints done, here is the verdict."

    init() {}

    func call(arguments _: GmAgentRpirCompleteReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_COMPLETE")
    }
}

@Generable
struct GmAgentRpirResolveReviewFindingArguments: Sendable {
    @Guide(description: "Which problem was handled, by uuid.")
    var findingUuid: String

    @Guide(description: "Version of the finding you read.")
    var expectedVersion: Int

    @Guide(description: "How it was handled.", .anyOf(GM_TOOL_ANYOF_REVIEW_RESOLUTION))
    var status: String

    init(findingUuid: String, expectedVersion: Int, status: String) {
        self.findingUuid = findingUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

struct GmAgentRpirResolveReviewFindingTool: GmAgentRpirTool {
    let name = "rpir_resolve_review_finding"
    let description = "This complaint is handled."

    init() {}

    func call(
        arguments _: GmAgentRpirResolveReviewFindingArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_RESOLVE")
    }
}

@Generable
struct GmAgentRpirGetReviewArguments: Sendable {
    @Guide(description: promptUuidGuide("'s review to read"))
    var promptUuid: String

    @Guide(
        description: """
            Only return problems this bad or worse, 0 to 999. Use a small number to \
            keep the answer short.
            """,
        .range(0...999)
    )
    var maxRating: Int

    init(promptUuid: String, maxRating: Int = 100) {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
    }
}

struct GmAgentRpirGetReviewTool: GmAgentRpirTool {
    let name = "rpir_get_review"
    let description = "Show me the complaints so far."

    init() {}

    func call(arguments _: GmAgentRpirGetReviewArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "REVIEW_GET")
    }
}
