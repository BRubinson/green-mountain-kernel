// Agent tools for the exploration phase: findings, key files, the calibrated rank and the seal.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenExplorationArguments: Sendable {
    @Guide(description: promptUuidGuide("to explore"))
    public var promptUuid: String

    @Guide(description: "Which methodology you are.", .anyOf(GM_TOOL_ANYOF_AGENT_TYPE))
    public var agentType: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID)
    public var agentId: String

    public init(promptUuid: String, agentType: String, agentId: String = "") {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenExplorationTool: GmAgentCdeTool {
    public let name = "cde_open_exploration"
    public let description = "Start my own finding list."

    public init() {}

    public func call(arguments: GmAgentCdeOpenExplorationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentExplorationFinding: Sendable {
    @Guide(description: "What kind of finding this is.", .anyOf(GM_TOOL_ANYOF_FINDING_KIND))
    public var kind: String

    @Guide(description: "Short title for the finding.")
    public var title: String

    @Guide(description: "The finding itself, in full.")
    public var body: String

    @Guide(description: "Repo-relative file this is about, or empty.")
    public var filePath: String

    @Guide(description: GM_TOOL_GUIDE_RATING_OPTIONAL)
    public var rating: Int?

    public init(
        kind: String, title: String, body: String, filePath: String = "", rating: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.rating = rating
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeWriteExplorationsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "finding list"))
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    public var agentName: String

    @Guide(description: "All the findings to write in one go.")
    public var findings: [GmAgentExplorationFinding]

    public init(summaryUuid: String, agentName: String, findings: [GmAgentExplorationFinding]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.findings = findings
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteExplorationsTool: GmAgentCdeTool {
    public let name = "cde_write_explorations"
    public let description = "Write down many findings at once."

    public init() {}

    public func call(arguments: GmAgentCdeWriteExplorationsArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_FINDING_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentFindingRating: Sendable {
    @Guide(description: "Which finding, by uuid.")
    public var findingUuid: String

    @Guide(description: GM_TOOL_GUIDE_RATING, .range(0...999))
    public var rating: Int

    public init(findingUuid: String, rating: Int) {
        self.findingUuid = findingUuid
        self.rating = rating
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeRankExplorationsArguments: Sendable {
    @Guide(description: promptUuidGuide("'s findings to rank"))
    public var promptUuid: String

    @Guide(description: "Every finding and its rating, all at once.")
    public var ratings: [GmAgentFindingRating]

    public init(promptUuid: String, ratings: [GmAgentFindingRating]) {
        self.promptUuid = promptUuid
        self.ratings = ratings
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeRankExplorationsTool: GmAgentCdeTool {
    public let name = "cde_rank_explorations"
    public let description = "Give every finding a number, all at once."

    public init() {}

    public func call(arguments: GmAgentCdeRankExplorationsArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_RANK")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeCompleteExplorationArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "seal", "finding list"))
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    public var expectedVersion: Int

    @Guide(description: "What the findings add up to, written out.")
    public var overview: String

    public init(summaryUuid: String, expectedVersion: Int, overview: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeCompleteExplorationTool: GmAgentCdeTool {
    public let name = "cde_complete_exploration"
    public let description = "Finding list done, here is what it all means."

    public init() {}

    public func call(arguments: GmAgentCdeCompleteExplorationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeGetExplorationArguments: Sendable {
    @Guide(description: promptUuidGuide("'s findings to read"))
    public var promptUuid: String

    @Guide(description: GM_TOOL_GUIDE_MAX_RATING, .range(0...999))
    public var maxRating: Int

    @Guide(description: "Only one methodology's list, or empty for all of them.")
    public var agentType: String

    public init(promptUuid: String, maxRating: Int = 100, agentType: String = "") {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
        self.agentType = agentType
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeGetExplorationTool: GmAgentCdeTool {
    public let name = "cde_get_exploration"
    public let description = "Show me the findings so far."

    public init() {}

    public func call(arguments: GmAgentCdeGetExplorationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_GET")
    }
}
