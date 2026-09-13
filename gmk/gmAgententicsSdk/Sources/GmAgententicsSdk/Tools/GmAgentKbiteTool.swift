// Agent tools over the kbites: ranked search and reading one digested file.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentKbiteSearchArguments: Sendable {
    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    public var query: String

    @Guide(description: """
        Only look inside these kbites, by uuid. Leave empty to search every \
        digested kbite.
        """)
    public var kbiteUuids: [String]

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    public var limit: Int

    public init(query: String, kbiteUuids: [String] = [], limit: Int = 20) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentKbiteSearchTool: GmAgentKbiteTool {
    public let name = "kbite_search"
    public let description = "Find stuff in chewed-up kbites."

    public init() {}

    public func call(arguments: GmAgentKbiteSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_SEARCH")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentKbiteOpenMawArguments: Sendable {
    @Guide(description: "Name of the kbite this maw collects for.")
    public var kbiteName: String

    @Guide(description: "Where on disk the maw collects files.")
    public var mawPath: String

    public init(kbiteName: String, mawPath: String) {
        self.kbiteName = kbiteName
        self.mawPath = mawPath
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentKbiteOpenMawTool: GmAgentKbiteTool {
    public let name = "kbite_open_maw"
    public let description = "Open big mouth to collect stuff."

    public init() {}

    public func call(arguments: GmAgentKbiteOpenMawArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_MAW_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentKbiteDigestArguments: Sendable {
    @Guide(description: "Short code that names the kbite.")
    public var code: String

    @Guide(description: "Path to the opened maw holding the chewed files.")
    public var kbiteOpenPath: String

    public init(code: String, kbiteOpenPath: String) {
        self.code = code
        self.kbiteOpenPath = kbiteOpenPath
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentKbiteDigestTool: GmAgentKbiteTool {
    public let name = "kbite_digest"
    public let description = "Swallow the chewed stuff into the brain."

    public init() {}

    public func call(arguments: GmAgentKbiteDigestArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_DIGEST")
    }
}
