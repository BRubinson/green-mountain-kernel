import Foundation
import FoundationModels
import GmDaemonSdk

// The kbite family: search, open a maw, digest.
//
// WHAT IS DELIBERATELY ABSENT. Chewing — the step between opening a maw and
// digesting it — stays in the plugin for now, so there is no chew tool here.
// So do KBITE_EXPORT / IMPORT / DELETE / KEYWORD_TAG / LIST / ADD / REMOVE,
// all of which the daemon serves. This surface is an intentionally constrained
// subset of the daemon client interface, and the constraint only holds if
// "the verb exists" stops being a reason to add a tool.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentKbiteSearchArguments: Sendable {
    @Guide(description: "Words to look for. Whole words match; misspellings find nothing.")
    public var query: String

    @Guide(description: """
        Only look inside these kbites, by uuid. Leave empty to search every \
        digested kbite.
        """)
    public var kbiteUuids: [String]

    @Guide(description: "How many hits to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(query: String, kbiteUuids: [String] = [], limit: Int = 20) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

/// Find stuff in chewed-up kbites.
///
/// Returns ranked STUBS with briefs, never file content — read a brief, then
/// fetch the one file you want. That shape is the verb's, not a choice made
/// here, and it is what keeps a broad search from blowing a context window.
///
/// FTS5 token matching with bm25 ranking. Not typo-tolerant: a query with no
/// searchable tokens is refused rather than answered emptily.
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

/// Open big mouth to collect stuff.
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

/// Swallow the chewed stuff into the brain.
///
/// Digestion is the step that moves chewed files into the db and archives the
/// raw sources. Chewing itself happens in the plugin and is not reachable from
/// this surface.
@available(GmAgentOs 1.0, *)
public struct GmAgentKbiteDigestTool: GmAgentKbiteTool {
    public let name = "kbite_digest"
    public let description = "Swallow the chewed stuff into the brain."

    public init() {}

    public func call(arguments: GmAgentKbiteDigestArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "KBITE_DIGEST")
    }
}
