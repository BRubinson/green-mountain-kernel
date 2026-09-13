import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeSearchArguments: Sendable {
    @Guide(description: "Words to look for. Whole words match; misspellings find nothing.")
    public var query: String

    @Guide(description: """
        Which kinds of dope rows to search. Leave empty to search all of them. \
        Use this to ask for only persistence rows, or only cogs.
        """)
    public var sources: [String]

    @Guide(description: "How many hits to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(query: String, sources: [String] = [], limit: Int = 50) {
        self.query = query
        self.sources = sources
        self.limit = limit
    }

    public var resolvedSources: [DopeSearchSource] {
        sources.compactMap(DopeSearchSource.init(rawValue:))
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentDopeSearchGlobalTool: GmAgentDopeTool {
    public let name = "dope_search_global"
    public let description = "Look in ALL projects and sessions for doped data."

    public init() {}

    public func call(arguments: GmAgentDopeSearchArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                DOPE_SEARCH has no all-projects scope — DopeSearchScope is \
                prompt|session|project and project still requires one \
                project_uuid. Reaching every project means fanning out over \
                PROJECT_LIST client-side, or widening the enum (not decode-safe \
                for a stale peer).
                """)
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentDopeSearchSessionTool: GmAgentDopeTool {
    public let name = "dope_search_session"
    public let description = "Look in THIS session only for doped data."

    public init() {}

    public func call(arguments: GmAgentDopeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "DOPE_SEARCH")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeNodeUpdate: Sendable {
    @Guide(description: "Dot-path code of the node to change, like domain.entity.property.")
    public var code: String

    @Guide(description: "New title for the node, or empty to leave it alone.")
    public var title: String

    @Guide(description: "New body text for the node, or empty to leave it alone.")
    public var body: String

    public init(code: String, title: String = "", body: String = "") {
        self.code = code
        self.title = title
        self.body = body
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeUpdateSessionArguments: Sendable {
    @Guide(description: "All the node changes to make in one go.")
    public var updates: [GmAgentDopeNodeUpdate]

    public init(updates: [GmAgentDopeNodeUpdate]) {
        self.updates = updates
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentDopeUpdateSessionTool: GmAgentDopeTool {
    public let name = "dope_update_session"
    public let description = "Change many session dopes on disk at once."

    public init() {}

    public func call(arguments: GmAgentDopeUpdateSessionArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                no batch node-update verb exists (DOPE_NODE_UPDATE takes one \
                node), and whether 'on disk' means DOPE_WRITE_REPO or \
                DOPE_INGEST is undecided — see the doc comment before wiring.
                """)
    }
}
