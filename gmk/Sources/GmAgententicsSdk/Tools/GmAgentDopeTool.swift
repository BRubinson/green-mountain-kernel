// Agent tools over the dope tree: search by scope and read a subtree by dot-path code.

import Foundation
import FoundationModels

@Generable
struct GmAgentDopeSearchArguments: Sendable {
    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    var query: String

    @Guide(
        description: """
            Which kinds of dope rows to search. Leave empty to search all of them. \
            Use this to ask for only persistence rows, or only cogs.
            """
    )
    var sources: [String]

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    var limit: Int

    init(query: String, sources: [String] = [], limit: Int = 50) {
        self.query = query
        self.sources = sources
        self.limit = limit
    }

    var resolvedSources: [DopeSearchSource] {
        sources.compactMap(DopeSearchSource.init(rawValue:))
    }
}

struct GmAgentDopeSearchGlobalTool: GmAgentDopeTool {
    let name = "dope_search_global"
    let description = "Look in ALL projects and sessions for doped data."

    init() {}

    func call(arguments _: GmAgentDopeSearchArguments) throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                DOPE_SEARCH has no all-projects scope — DopeSearchScope is \
                prompt|session|project and project still requires one \
                project_uuid. Reaching every project means fanning out over \
                PROJECT_LIST client-side, or widening the enum (not decode-safe \
                for a stale peer).
                """
        )
    }
}

struct GmAgentDopeSearchSessionTool: GmAgentDopeTool {
    let name = "dope_search_session"
    let description = "Look in THIS session only for doped data."

    init() {}

    func call(arguments _: GmAgentDopeSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "DOPE_SEARCH")
    }
}

@Generable
struct GmAgentDopeNodeUpdate: Sendable {
    @Guide(description: "The node to change. " + GM_TOOL_GUIDE_DOPE_CODE)
    var code: String

    @Guide(description: "New title for the node, or empty to leave it alone.")
    var title: String

    @Guide(description: "New body text for the node, or empty to leave it alone.")
    var body: String

    init(code: String, title: String = "", body: String = "") {
        self.code = code
        self.title = title
        self.body = body
    }
}

@Generable
struct GmAgentDopeUpdateSessionArguments: Sendable {
    @Guide(description: "All the node changes to make in one go.")
    var updates: [GmAgentDopeNodeUpdate]

    init(updates: [GmAgentDopeNodeUpdate]) {
        self.updates = updates
    }
}

struct GmAgentDopeUpdateSessionTool: GmAgentDopeTool {
    let name = "dope_update_session"
    let description = "Change many session dopes on disk at once."

    init() {}

    func call(arguments _: GmAgentDopeUpdateSessionArguments) throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                no batch node-update verb exists (DOPE_NODE_UPDATE takes one \
                node), and whether 'on disk' means DOPE_WRITE_REPO or \
                DOPE_INGEST is undecided — see the doc comment before wiring.
                """
        )
    }
}
