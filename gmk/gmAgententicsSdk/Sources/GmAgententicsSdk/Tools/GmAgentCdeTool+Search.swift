// Agent tools for searching the record: prior work and recorded file changes.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeSearchArguments: Sendable {
    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    public var query: String

    @Guide(description: "Only look in this session, by uuid. Leave empty to search everything.")
    public var sessionUuid: String

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    public var limit: Int

    public init(query: String, sessionUuid: String = "", limit: Int = 50) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.limit = limit
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSearchExplorationTool: GmAgentRpirTool {
    public let name = "rpir_search_exploration"
    public let description = "Find old findings by words in them."

    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=exploration_summary,exploration_finding")
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSearchClarificationTool: GmAgentRpirTool {
    public let name = "rpir_search_clarification"
    public let description = "Find old questions and notes by words in them."

    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=clarification_question,clarification_note")
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSearchArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_search_architecture"
    public let description = "Find old plans by words in them."

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

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSearchReviewTool: GmAgentRpirTool {
    public let name = "rpir_search_review"
    public let description = "Find old complaints by words in them."

    public init() {}

    public func call(arguments: GmAgentCdeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SEARCH kinds=review_summary,review_finding")
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSearchArchitectureOptionTool: GmAgentRpirTool {
    public let name = "rpir_search_architecture_option"
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
    @Guide(description: promptUuidGuide("'s changes to filter to") + " Leave empty to skip this filter.")
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

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSearchFileChangesTool: GmAgentCdeTool {
    public let name = "cde_search_file_changes"
    public let description = "Find what files got changed."

    public init() {}

    public func call(arguments: GmAgentCdeSearchFileChangesArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "FILE_CHANGE_LIST")
    }
}
