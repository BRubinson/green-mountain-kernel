// Agent tools for searching the record: prior work and recorded file changes.

import Foundation
import FoundationModels

@Generable
struct GmAgentCdeSearchArguments: Sendable {
    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    var query: String

    @Guide(description: "Only look in this session, by uuid. Leave empty to search everything.")
    var sessionUuid: String

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    var limit: Int

    init(query: String, sessionUuid: String = "", limit: Int = 50) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.limit = limit
    }
}

struct GmAgentRpirSearchExplorationTool: GmAgentRpirTool {
    let name = "rpir_search_exploration"
    let description = "Find old findings by words in them."

    init() {}

    func call(arguments _: GmAgentCdeSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "SEARCH kinds=exploration_summary,exploration_finding"
        )
    }
}

struct GmAgentRpirSearchClarificationTool: GmAgentRpirTool {
    let name = "rpir_search_clarification"
    let description = "Find old questions and notes by words in them."

    init() {}

    func call(arguments _: GmAgentCdeSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "SEARCH kinds=clarification_question,clarification_note"
        )
    }
}

struct GmAgentRpirSearchArchitectureTool: GmAgentRpirTool {
    let name = "rpir_search_architecture"
    let description = "Find old plans by words in them."

    init() {}

    func call(arguments _: GmAgentCdeSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: """
                SEARCH kinds=architecture_summary,architecture_general_change,\
                architecture_persistence_change
                """
        )
    }
}

struct GmAgentRpirSearchReviewTool: GmAgentRpirTool {
    let name = "rpir_search_review"
    let description = "Find old complaints by words in them."

    init() {}

    func call(arguments _: GmAgentCdeSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "SEARCH kinds=review_summary,review_finding"
        )
    }
}

struct GmAgentRpirSearchArchitectureOptionTool: GmAgentRpirTool {
    let name = "rpir_search_architecture_option"
    let description = "Find one architect's plan by words in it."

    init() {}

    func call(arguments _: GmAgentCdeSearchArguments) throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                SearchKind has no architecture_option arm — option rows were \
                never added to the FTS index. ARCH_GET reads them by uuid, but \
                nothing searches their text. Closing this needs a new SearchKind \
                plus its FTS table and triggers.
                """
        )
    }
}

@Generable
struct GmAgentCdeSearchFileChangesArguments: Sendable {
    @Guide(description: promptUuidGuide("'s changes to filter to") + " Leave empty to skip this filter.")
    var promptUuid: String

    @Guide(description: "Only changes in this session, by uuid. Leave empty to skip this filter.")
    var sessionUuid: String

    @Guide(description: "Only changes to this repo-relative path. Leave empty for all files.")
    var relativePath: String

    @Guide(description: "How many to return, 1 to 500.", .range(1...500))
    var limit: Int

    init(
        promptUuid: String = "",
        sessionUuid: String = "",
        relativePath: String = "",
        limit: Int = 100
    ) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.relativePath = relativePath
        self.limit = limit
    }
}

struct GmAgentCdeSearchFileChangesTool: GmAgentCdeTool {
    let name = "cde_search_file_changes"
    let description = "Find what files got changed."

    init() {}

    func call(arguments _: GmAgentCdeSearchFileChangesArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "FILE_CHANGE_LIST")
    }
}
