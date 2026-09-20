// Agent tools over the kbites: ranked search and reading one digested file.

import Foundation
import FoundationModels

@Generable
struct GmAgentKbiteSearchArguments: Sendable {
    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    var query: String

    @Guide(
        description: """
            Only look inside these kbites, by uuid. Leave empty to search every \
            digested kbite.
            """
    )
    var kbiteUuids: [String]

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    var limit: Int

    init(query: String, kbiteUuids: [String] = [], limit: Int = 20) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

struct GmAgentKbiteSearchTool: GmAgentKbiteTool {
    let name = "kbite_search"
    let description = "Find stuff in chewed-up kbites."

    init() {}

    func call(arguments _: GmAgentKbiteSearchArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_SEARCH")
    }
}

@Generable
struct GmAgentKbiteOpenMawArguments: Sendable {
    @Guide(description: "Name of the kbite this maw collects for.")
    var kbiteName: String

    @Guide(description: "Where on disk the maw collects files.")
    var mawPath: String

    init(kbiteName: String, mawPath: String) {
        self.kbiteName = kbiteName
        self.mawPath = mawPath
    }
}

struct GmAgentKbiteOpenMawTool: GmAgentKbiteTool {
    let name = "kbite_open_maw"
    let description = "Open big mouth to collect stuff."

    init() {}

    func call(arguments _: GmAgentKbiteOpenMawArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_MAW_OPEN")
    }
}

@Generable
struct GmAgentKbiteDigestArguments: Sendable {
    @Guide(description: "Short code that names the kbite.")
    var code: String

    @Guide(description: "Path to the opened maw holding the chewed files.")
    var kbiteOpenPath: String

    init(code: String, kbiteOpenPath: String) {
        self.code = code
        self.kbiteOpenPath = kbiteOpenPath
    }
}

struct GmAgentKbiteDigestTool: GmAgentKbiteTool {
    let name = "kbite_digest"
    let description = "Swallow the chewed stuff into the brain."

    init() {}

    func call(arguments _: GmAgentKbiteDigestArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_DIGEST")
    }
}
