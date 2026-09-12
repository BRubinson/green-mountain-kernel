import Foundation
import FoundationModels
import GmDaemonSdk

// The exploration family: open, write, rank, complete, read.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenExplorationArguments: Sendable {
    @Guide(description: "Which prompt to explore, by uuid.")
    public var promptUuid: String

    @Guide(description: "Which methodology you are.", .anyOf([
        "aggressive", "conservative", "pragmatic", "alternative", "general", "synthesis",
    ]))
    public var agentType: String

    @Guide(description: "Your own agent id, so two agents cannot share one list.")
    public var agentId: String

    public init(promptUuid: String, agentType: String, agentId: String = "") {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
    }
}

/// Start my own finding list.
///
/// One row per agent type, deduped automatically — every explorer opens its own
/// and writes only to that one. Sealing another agent's row is not something
/// this surface offers.
///
/// `synthesis` is the odd one: it is the prompt-level row the single reader
/// opens last, and completing it is the seal for the whole exploration rather
/// than for one methodology.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenExplorationTool: GmAgentCdeTool {
    public let name = "cde_open_exploration"
    public let description = "Start my own finding list."

    public init() {}

    public func call(arguments: GmAgentCdeOpenExplorationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_OPEN")
    }
}

/// One exploration finding.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentExplorationFinding: Sendable {
    @Guide(description: "What kind of finding this is.", .anyOf([
        "persistence_model", "implementation_pattern", "existing_functionality",
        "scope_creep_risk", "general_relevant_change", "key_file", "other",
    ]))
    public var kind: String

    @Guide(description: "Short title for the finding.")
    public var title: String

    @Guide(description: "The finding itself, in full.")
    public var body: String

    @Guide(description: "Repo-relative file this is about, or empty.")
    public var filePath: String

    /// OPTIONAL, AND THE nil IS LOAD-BEARING. nil means UNRANKED, which is a
    /// real state rather than a missing value: `EXPLORE_COMPLETE` on the
    /// synthesis row refuses while any finding in the prompt is unranked, and
    /// that refusal is what makes the cross-agent calibration pass mandatory
    /// instead of merely recommended.
    ///
    /// A non-optional Int here would give every finding a rating the moment it
    /// was written, drive `promptUnrankedCount` permanently to zero, and
    /// silently retire the gate while every doc comment still described it. The
    /// wire type is `Int?` for exactly this reason; match it.
    @Guide(description: """
        How important, 0 is most important and 999 is ignore. Leave it out \
        unless you were told to rate; ranking is one reader's job.
        """)
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
    @Guide(description: "Which finding list to write to, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Who is writing, for the record.")
    public var agentName: String

    @Guide(description: "All the findings to write in one go.")
    public var findings: [GmAgentExplorationFinding]

    public init(summaryUuid: String, agentName: String, findings: [GmAgentExplorationFinding]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.findings = findings
    }
}

/// Write down many findings at once.
///
/// PLURAL BY DESIGN, SINGULAR UNDERNEATH — and the gap between those two is a
/// real hazard, not a detail. `EXPLORE_FINDING_ADD` takes ONE finding, so until
/// a plural wire verb exists an implementation of this loops. A ten-finding call
/// that fails at the seventh leaves six findings committed, in a database that
/// is append-only and never wiped: there is no rollback, and retrying the whole
/// batch duplicates the six.
///
/// The plural shape is still the right thing to declare now, because argument
/// shapes are the expensive thing to change once anything depends on them. What
/// is not acceptable is shipping the shape while implying atomicity it does not
/// have — hence this paragraph.
///
/// Contrast `rank_explorations`, which IS atomic on the wire: one bad pair
/// rejects the whole batch.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteExplorationsTool: GmAgentCdeTool {
    public let name = "cde_write_explorations"
    public let description = "Write down many findings at once."

    public init() {}

    public func call(arguments: GmAgentCdeWriteExplorationsArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_FINDING_ADD (looped)")
    }
}

/// One finding's rating.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentFindingRating: Sendable {
    @Guide(description: "Which finding, by uuid.")
    public var findingUuid: String

    @Guide(description: "How important: 0 is most important, 999 means ignore.", .range(0...999))
    public var rating: Int

    public init(findingUuid: String, rating: Int) {
        self.findingUuid = findingUuid
        self.rating = rating
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeRankExplorationsArguments: Sendable {
    @Guide(description: "Which prompt's findings to rank, by uuid.")
    public var promptUuid: String

    @Guide(description: "Every finding and its rating, all at once.")
    public var ratings: [GmAgentFindingRating]

    public init(promptUuid: String, ratings: [GmAgentFindingRating]) {
        self.promptUuid = promptUuid
        self.ratings = ratings
    }
}

/// Give every finding a number, all at once.
///
/// DERIVED — the prompt behind this surface names writing and completing an
/// exploration but not ranking it, and without ranking the exploration can never
/// be sealed: `EXPLORE_COMPLETE` on the synthesis row REFUSES while any finding
/// in the prompt is unranked. So this is not an enhancement, it is a missing
/// link in the chain the other tools form.
///
/// Prompt-wide and cross-agent: a rating means the same thing whichever
/// methodology wrote the finding, which is why it is one calibration pass by one
/// reader rather than each agent scoring its own. Atomic — one bad pair rejects
/// the whole batch — which is also why the argument is a single list.
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
    @Guide(description: "Which finding list to seal, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Version of the list you read.")
    public var expectedVersion: Int

    @Guide(description: "What the findings add up to, written out.")
    public var overview: String

    public init(summaryUuid: String, expectedVersion: Int, overview: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
    }
}

/// Finding list done, here is what it all means.
///
/// Seals one row — your own. Sealing the `synthesis` row is the prompt-level
/// seal, and it refuses while any finding anywhere in the prompt is unranked.
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
    @Guide(description: "Which prompt's findings to read, by uuid.")
    public var promptUuid: String

    @Guide(description: """
        Only return findings this important or better, 0 to 999. Use a small \
        number to keep the answer short.
        """, .range(0...999))
    public var maxRating: Int

    @Guide(description: "Only one methodology's list, or empty for all of them.")
    public var agentType: String

    public init(promptUuid: String, maxRating: Int = 100, agentType: String = "") {
        self.promptUuid = promptUuid
        self.maxRating = maxRating
        self.agentType = agentType
    }
}

/// Show me the findings so far.
///
/// DERIVED. The prompt names no read beside these writes, and that would be a
/// real hole: an agent that cannot read its own exploration rows through this
/// surface will go get them another way, and once it is outside the surface for
/// reading it is outside it for writing too.
///
/// NARROWED ON PURPOSE. `maxRating` and `agentType` exist so the answer can be
/// made smaller, because an unnarrowable read is the other way an agent ends up
/// leaving — a tool that can only return everything eventually returns more than
/// the caller can hold, and then it stops being used.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeGetExplorationTool: GmAgentCdeTool {
    public let name = "cde_get_exploration"
    public let description = "Show me the findings so far."

    public init() {}

    public func call(arguments: GmAgentCdeGetExplorationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "EXPLORE_GET")
    }
}
