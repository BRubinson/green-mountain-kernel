// Agent tools for the exploration phase: findings, key files, the calibrated rank and the seal.

import Foundation
import FoundationModels

@Generable
struct GmAgentRpirOpenExplorationArguments: Sendable {
    @Guide(description: promptUuidGuide("to explore"))
    var promptUuid: String

    @Guide(description: "Which methodology you are.", .anyOf(GM_TOOL_ANYOF_AGENT_TYPE))
    var agentType: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID)
    var agentId: String

    init(promptUuid: String, agentType: String, agentId: String = "") {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
    }
}

struct GmAgentRpirOpenExplorationTool: GmAgentRpirTool {
    let name = "rpir_open_exploration"
    let description = "Start my own finding list."

    init() {}

    func call(arguments _: GmAgentRpirOpenExplorationArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_OPEN")
    }
}

@Generable
struct GmAgentExplorationFinding: Sendable {
    @Guide(description: "What kind of finding this is.", .anyOf(GM_TOOL_ANYOF_FINDING_KIND))
    var kind: String

    @Guide(description: "Short title for the finding.")
    var title: String

    @Guide(description: "The finding itself, in full.")
    var body: String

    @Guide(description: "Repo-relative file this is about, or empty.")
    var filePath: String

    @Guide(description: GM_TOOL_GUIDE_RATING_OPTIONAL)
    var rating: Int?

    init(
        kind: String,
        title: String,
        body: String,
        filePath: String = "",
        rating: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.rating = rating
    }
}

@Generable
struct GmAgentRpirWriteExplorationsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "finding list"))
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    var agentName: String

    @Guide(description: "All the findings to write in one go.")
    var findings: [GmAgentExplorationFinding]

    init(summaryUuid: String, agentName: String, findings: [GmAgentExplorationFinding]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.findings = findings
    }
}

struct GmAgentRpirWriteExplorationsTool: GmAgentRpirTool {
    let name = "rpir_write_explorations"
    let description = "Write down many findings at once."

    init() {}

    func call(arguments _: GmAgentRpirWriteExplorationsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_FINDING_ADD (looped)")
    }
}

@Generable
struct GmAgentFindingRating: Sendable {
    @Guide(description: "Which finding, by uuid.")
    var findingUuid: String

    @Guide(description: GM_TOOL_GUIDE_RATING, .range(0...999))
    var rating: Int

    init(findingUuid: String, rating: Int) {
        self.findingUuid = findingUuid
        self.rating = rating
    }
}

@Generable
struct GmAgentRpirRankExplorationsArguments: Sendable {
    @Guide(description: promptUuidGuide("'s findings to rank"))
    var promptUuid: String

    @Guide(description: "Every finding and its rating, all at once.")
    var ratings: [GmAgentFindingRating]

    init(promptUuid: String, ratings: [GmAgentFindingRating]) {
        self.promptUuid = promptUuid
        self.ratings = ratings
    }
}

struct GmAgentRpirRankExplorationsTool: GmAgentRpirTool {
    let name = "rpir_rank_explorations"
    let description = "Give every finding a number, all at once."

    init() {}

    func call(arguments _: GmAgentRpirRankExplorationsArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_RANK")
    }
}

@Generable
struct GmAgentRpirCompleteExplorationArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "seal", "finding list"))
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    var expectedVersion: Int

    @Guide(description: "What the findings add up to, written out.")
    var overview: String

    init(summaryUuid: String, expectedVersion: Int, overview: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
    }
}

struct GmAgentRpirCompleteExplorationTool: GmAgentRpirTool {
    let name = "rpir_complete_exploration"
    let description = "Finding list done, here is what it all means."

    init() {}

    func call(arguments _: GmAgentRpirCompleteExplorationArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_COMPLETE")
    }
}

@Generable
struct GmAgentRpirGetExplorationArguments: Sendable {
    @Guide(description: promptUuidGuide("'s findings to read"))
    var promptUuid: String

    @Guide(description: GM_TOOL_GUIDE_MAX_RATING, .range(0...999))
    var maxRating: Int

    @Guide(description: "Only one methodology's list, or empty for all of them.")
    var agentType: String

    init(promptUuid: String, maxRating: Int = 100, agentType: String = "") {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
        self.agentType = agentType
    }
}

struct GmAgentRpirGetExplorationTool: GmAgentRpirTool {
    let name = "rpir_get_exploration"
    let description = "Show me the findings so far."

    init() {}

    func call(arguments _: GmAgentRpirGetExplorationArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_GET")
    }
}
