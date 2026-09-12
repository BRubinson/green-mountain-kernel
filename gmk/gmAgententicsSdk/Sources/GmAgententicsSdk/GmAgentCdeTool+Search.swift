import Foundation
import FoundationModels
import GmDaemonSdk

// The searches.
//
// UNDERNEATH, THESE ARE TWO VERBS. Four of them are `SEARCH` with a different
// `kinds` filter, and the file-change one is `FILE_CHANGE_LIST`. They are kept
// as separate NAMED tools anyway, and that is a deliberate choice rather than a
// missed simplification: a tool called `search_exploration` with its kinds
// already fixed is something a model picks correctly on the first try, while one
// generic `search` with a `kinds` parameter is something it must populate
// correctly — and populating it wrongly returns plausible results from the wrong
// table rather than an error.
//
// FTS5 THROUGHOUT: token matching with bm25 ranking, not typo tolerance. A query
// with no searchable tokens is refused rather than answered emptily.

/// Shared arguments for the text searches.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeSearchArguments: Sendable {
    @Guide(description: "Words to look for. Whole words match; misspellings find nothing.")
    public var query: String

    @Guide(description: "Only look in this session, by uuid. Leave empty to search everything.")
    public var sessionUuid: String

    @Guide(description: "How many hits to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(query: String, sessionUuid: String = "", limit: Int = 50) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.limit = limit
    }
}

/// Find old findings by words in them.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchExplorationTool: GmAgentCdeTool {
    public let name = "cde_search_exploration"
    public let description = "Find old findings by words in them."

    /// `[.explorationSummary, .explorationFinding]`.
    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=exploration_summary,exploration_finding")
    }
}

/// Find old questions and notes by words in them.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchClarificationTool: GmAgentCdeTool {
    public let name = "cde_search_clarification"
    public let description = "Find old questions and notes by words in them."

    /// `[.clarificationQuestion, .clarificationNote]`.
    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=clarification_question,clarification_note")
    }
}

/// Find old plans by words in them.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchArchitectureTool: GmAgentCdeTool {
    public let name = "cde_search_architecture"
    public let description = "Find old plans by words in them."

    /// `[.architectureSummary, .architectureGeneralChange, .architecturePersistenceChange]`.
    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: """
                SEARCH kinds=architecture_summary,architecture_general_change,\
                architecture_persistence_change
                """)
    }
}

/// Find old complaints by words in them.
///
/// DERIVED alongside the rest of the review family.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchReviewTool: GmAgentCdeTool {
    public let name = "cde_search_review"
    public let description = "Find old complaints by words in them."

    /// `[.reviewSummary, .reviewFinding]`.
    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=review_summary,review_finding")
    }
}

/// Find one architect's plan by words in it.
///
/// DECLARED BUT NOT BACKED, and this is a gap in the search index rather than in
/// the wiring. `SearchKind` has ten arms and none of them is
/// `architecture_option`: option rows arrived with the architect-pen inversion
/// and the FTS kinds were never extended to cover them. They are reachable today
/// only through `ARCH_GET`, which returns option bodies as stubs unless asked for
/// one by uuid — a read, not a search.
///
/// Closing it means a new `SearchKind` case plus the FTS table and triggers
/// behind it, in the same shape the other nine have.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchArchitectureOptionTool: GmAgentCdeTool {
    public let name = "cde_search_architecture_option"
    public let description = "Find one architect's plan by words in it."

    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                SearchKind has no architecture_option arm — option rows were \
                never added to the FTS index. ARCH_GET reads them by uuid, but \
                nothing searches their text. Closing this needs a new SearchKind \
                plus its FTS table and triggers.
                """)
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeSearchFileChangesArguments: Sendable {
    @Guide(description: "Only changes for this prompt, by uuid. Leave empty to skip this filter.")
    public var promptUuid: String

    @Guide(description: "Only changes in this session, by uuid. Leave empty to skip this filter.")
    public var sessionUuid: String

    @Guide(description: "Only changes to this repo-relative path. Leave empty for all files.")
    public var relativePath: String

    @Guide(description: "How many to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(
        promptUuid: String = "", sessionUuid: String = "",
        relativePath: String = "", limit: Int = 100
    ) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.relativePath = relativePath
        self.limit = limit
    }
}

/// Find what files got changed.
///
/// ONE TOOL WHERE THE PROMPT ASKED FOR TWO. `search_session_file_changes` and
/// `search_prompt_file_changes` are the same call with a different field filled
/// in — `FILE_CHANGE_LIST` already takes `session_uuid`, `prompt_uuid` and a
/// path filter together. Splitting them would produce two tools with identical
/// argument structs and one field each ignored, which is worse for a model than
/// one tool whose scope is visible in its arguments.
///
/// This is the exception to the keep-them-separate rule at the top of this file,
/// and for the opposite reason: there the tools differed in a field the caller
/// should not have to set, here they differ in one the caller must set anyway.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchFileChangesTool: GmAgentCdeTool {
    public let name = "cde_search_file_changes"
    public let description = "Find what files got changed."

    public init() {}

    public func call(arguments: GmAgentCdeSearchFileChangesArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "FILE_CHANGE_LIST")
    }
}
