// The one agent tool over the dope tree: search a scope, search every project, write a scope to disk.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeDopeArguments: Sendable {

    @Guide(
        description: "Which dope door to use.",
        .anyOf(GM_TOOL_ANYOF_CDE_DOPE_OP)
    )
    var op: String

    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
    var query: String?

    @Guide(description: "prompt|session|project (default session)")
    var scope: String?

    @Guide(description: "Prompt scope selector")
    var prompt_uuid: String?

    @Guide(description: "Explicit session uuid")
    var session_uuid: String?

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT)
    var limit: Int?

    @Guide(description: "The dope scope to write")
    var scope_uuid: String?

    @Guide(description: "Write even when the repo has diverged")
    var force: Bool?

    @Guide(description: "page.next_cursor from the previous call (opaque) — omit for the first page")
    var cursor: String?

    @Guide(
        description: """
            Page budget in bytes (default 30000, max 45000); every array and \
            every long text is paged inside it
            """
    )
    var page_bytes: Int?

    /// Creates a dope tool arguments set.
    /// - Parameters:
    ///   - op: The operation to perform.
    ///   - query: The search query, or nil.
    ///   - scope: The scope type (prompt, session, project), or nil.
    ///   - prompt_uuid: The prompt uuid selector, or nil.
    ///   - session_uuid: The explicit session uuid, or nil.
    ///   - limit: The maximum number of results, or nil.
    ///   - scope_uuid: The dope scope to write, or nil.
    ///   - force: Whether to force write despite divergence, or nil.
    ///   - cursor: The pagination cursor from the previous call, or nil.
    ///   - page_bytes: The page budget in bytes, or nil.
    init(
        op: String,
        query: String? = nil,
        scope: String? = nil,
        prompt_uuid: String? = nil,
        session_uuid: String? = nil,
        limit: Int? = nil,
        scope_uuid: String? = nil,
        force: Bool? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.query = query
        self.scope = scope
        self.prompt_uuid = prompt_uuid
        self.session_uuid = session_uuid
        self.limit = limit
        self.scope_uuid = scope_uuid
        self.force = force
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}

// swiftlint:enable identifier_name

let GM_TOOL_ANYOF_CDE_DOPE_OP = GmAgentCdeDopeTool.Op.allCases.map(\.rawValue)

struct GmAgentCdeDopeTool: GmAgentDopeTool {

    enum Op: String, CaseIterable, Sendable {
        case searchSession = "search_session"
        case searchGlobal = "search_global"
        case updateSession = "update_session"
    }

    typealias Arguments = GmAgentCdeDopeArguments

    typealias Output = String

    static let toolName = "cde_dope"

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.searchSession,
            verbs: [.dopeSearch],
            summary: "FTS over the session's dope tree (hits carry dot-paths).",
            narrowing: pagedOpNarrowing(Op.searchSession),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.searchGlobal,
            verbs: [.dopeSearch],
            summary: "FTS over the dope trees of ALL projects and sessions, not just this one.",
            narrowing: pagedOpNarrowing(Op.searchGlobal),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.updateSession,
            verbs: [.dopeWriteRepo],
            summary: "Write the session's dope tree back to its repo — many dope nodes to disk at once.",
            requiredParams: ["scope_uuid"]
        ),
    ]

    static let alwaysLoad = true

    let name = GmAgentCdeDopeTool.toolName

    let description = """
        The doped record of the code: search this session's dope tree, search \
        every project's, or write a scope back to its repo.
        """

    /// Creates the dope search tool.
    init() {}

    /// Names the tool and operation for paging advice.
    /// - Parameter op: The operation that is paged.
    /// - Returns: A narrowing configuration with pagination parameters.
    private static func pagedOpNarrowing(_ op: Op) -> CdeNarrowing {
        CdeNarrowing(
            parameters: ["cursor", "page_bytes"],
            retryWith: "\(toolName) op=\(op.rawValue) with cursor = page.next_cursor"
        )
    }
}
