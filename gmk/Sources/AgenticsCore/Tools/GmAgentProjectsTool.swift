// The cde_session tool: the project, instance and session spine as one tool.

import Foundation
import FoundationModels

struct GmAgentCdeSessionTool: GmAgentProjectsTool {

    typealias Output = String

    /// The ONE spelling of this tool's name.
    static let toolName = "cde_session"

    enum Op: String, CaseIterable, Sendable {
        case search
        case update
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.search,
            verbs: [.catalogSearch],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "project_uuid", "limit"],
                retryWith: "\(toolName) op=search with cursor = page.next_cursor"
            ),
            requiredParams: ["query"],
            summary: "Find projects, instances and sessions by name or id."
        ),
        GmAgentToolOp(
            Op.update,
            verbs: [.sessionUpdate],
            requiredParams: ["session_uuid", "expected_version"],
            summary: "Change one session's name, backstory or goal."
        ),
    ]

    let name = GmAgentCdeSessionTool.toolName
    let description =
        "The project, instance and session spine: op search finds them by name or id, op update changes one session."

    init() {}

    // Argument property names ARE the served tool's snake_case wire argument names.
    // swiftlint:disable identifier_name
    @Generable
    struct Arguments: Sendable {

        @Guide(description: "search | update", .anyOf(Op.allCases.map(\.rawValue)))
        var op: String

        @Guide(description: "Name or id fragment (search)")
        var query: String?

        @Guide(description: "Restrict to one project (search)")
        var project_uuid: String?

        @Guide(description: "Max hits (search)", .range(1...500))
        var limit: Int?

        @Guide(description: "The session to update (update)")
        var session_uuid: String?

        @Guide(description: "The session version this write is based on (update)")
        var expected_version: Int?

        @Guide(description: "New name (update)")
        var name: String?

        @Guide(description: "New backstory (update)")
        var backstory: String?

        @Guide(description: "New goal (update)")
        var goal: String?

        @Guide(
            description:
                "page.next_cursor from the previous call (opaque) — omit for the first page (search)"
        )
        var cursor: String?

        @Guide(
            description:
                "Page budget in bytes (default 30000, max 45000); every array and every long text is paged inside it (search)"
        )
        var page_bytes: Int?
    }
    // swiftlint:enable identifier_name
}
