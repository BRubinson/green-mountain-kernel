// The agent tool for searching the record: one scope per kind of prior work.

import Foundation
import FoundationModels

struct GmAgentCdeRpirSearchTool: GmAgentRpirTool {

    /// The record the search is pinned to.
    ///
    /// The kinds filter is applied by the scope rather than by the caller, so
    /// "search explorations" cannot widen into "search everything".
    enum Op: String, CaseIterable, Sendable {

        case exploration

        case clarification

        case architecture

        case architectureOption = "architecture_option"

        case review
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.exploration,
            verbs: [.search],
            summary: "Find old exploration findings by words in them.",
            narrowing: searchNarrowing(.exploration),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.clarification,
            verbs: [.search],
            summary: "Find old clarification questions and notes by words in them.",
            narrowing: searchNarrowing(.clarification),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.architecture,
            verbs: [.search],
            summary: "Find old architecture plans by words in them — summaries and their change rows.",
            narrowing: searchNarrowing(.architecture),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.architectureOption,
            verbs: [.search],
            summary: "Find one architect's proposed option by words in it.",
            narrowing: searchNarrowing(.architectureOption),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.review,
            verbs: [.search],
            summary: "Find old review findings by words in them.",
            narrowing: searchNarrowing(.review),
            requiredParams: ["query"]
        ),
    ]

    static let toolName = "cde_rpir_search"

    /// Pinned: reaching the rest of the record starts here, and a deferred entry
    /// tool is one an agent has to already know the name of to find.
    static let alwaysLoad = true

    let name = GmAgentCdeRpirSearchTool.toolName

    let description = "Find prior work in the record by words in it."

    typealias Output = String

    /// Creates a search tool instance.
    init() {}

    // Argument property names ARE the served tool's snake_case wire argument names.
    // swiftlint:disable identifier_name
    @Generable
    struct Arguments: Sendable {

        @Guide(
            description: "Which record to search.",
            .anyOf(GmAgentCdeRpirSearchTool.Op.allCases.map(\.rawValue))
        )
        var scope: String

        @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY)
        var query: String

        @Guide(description: "Only look in this session, by uuid. Leave it out to search everything.")
        var session_uuid: String?

        @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
        var limit: Int?

        @Guide(description: "page.next_cursor from the previous call (opaque) — omit for the first page")
        var cursor: String?

        @Guide(
            description: """
                Page budget in bytes (default 30000, max 45000); every array and \
                every long text is paged inside it
                """
        )
        var page_bytes: Int?

        /// Creates search tool arguments.
        ///
        /// - Parameters:
        ///   - scope: Which record to search.
        ///   - query: Words to search for.
        ///   - session_uuid: Optional session UUID to limit search scope.
        ///   - limit: Maximum results to return (1-500).
        ///   - cursor: Opaque page cursor for continuation.
        ///   - page_bytes: Page budget in bytes (default 30000, max 45000).
        init(
            scope: String,
            query: String,
            session_uuid: String? = nil,
            limit: Int? = nil,
            cursor: String? = nil,
            page_bytes: Int? = nil
        ) {
            self.scope = scope
            self.query = query
            self.session_uuid = session_uuid
            self.limit = limit
            self.cursor = cursor
            self.page_bytes = page_bytes
        }
    }
    // swiftlint:enable identifier_name
}

/// Creates narrowing advice for a record search.
///
/// Quotes the scope back in the retry advice so an over-budget hit list names the call
/// that produced it rather than the tool alone.
///
/// - Parameter op: The record scope being searched.
/// - Returns: A narrowing suggestion with scope context.
private func searchNarrowing(_ op: GmAgentCdeRpirSearchTool.Op) -> CdeNarrowing {
    pagedNarrowing("\(GmAgentCdeRpirSearchTool.toolName) scope=\(op.rawValue)")
}
