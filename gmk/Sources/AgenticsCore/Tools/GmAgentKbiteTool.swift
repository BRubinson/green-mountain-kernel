// The agent tool over kbites: ranked search, opening a maw, digesting a chewed maw.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeKbiteArguments: Sendable {

    @Guide(
        description: "Which kbite move to make.",
        .anyOf(GmAgentCdeKbiteTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(description: GM_TOOL_GUIDE_SEARCH_QUERY + " search only.")
    var query: String?

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT + " search only.")
    var limit: Int?

    @Guide(description: "The kbite this maw feeds. open_maw only.")
    var kbite_name: String?

    @Guide(description: "Where the maw lives on disk. open_maw only.")
    var maw_path: String?

    @Guide(description: "The kbite code being digested. digest only.")
    var code: String?

    @Guide(description: "The opened maw's path. digest only.")
    var kbite_open_path: String?

    @Guide(description: "Page cursor from the previous answer's page.next_cursor.")
    var cursor: String?

    @Guide(description: "Page budget in bytes.")
    var page_bytes: Int?

    /// Creates kbite tool arguments.
    ///
    /// - Parameters:
    ///   - op: The operation name.
    ///   - query: Optional search query.
    ///   - limit: Optional result limit.
    ///   - kbite_name: Optional kbite name.
    ///   - maw_path: Optional maw path.
    ///   - code: Optional kbite code.
    ///   - kbite_open_path: Optional open path.
    ///   - cursor: Optional page cursor.
    ///   - page_bytes: Optional page budget.
    init(
        op: String,
        query: String? = nil,
        limit: Int? = nil,
        kbite_name: String? = nil,
        maw_path: String? = nil,
        code: String? = nil,
        kbite_open_path: String? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.query = query
        self.limit = limit
        self.kbite_name = kbite_name
        self.maw_path = maw_path
        self.code = code
        self.kbite_open_path = kbite_open_path
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}

// swiftlint:enable identifier_name

struct GmAgentCdeKbiteTool: GmAgentKbiteTool {

    enum Op: String, CaseIterable, Sendable {
        case search
        case openMaw = "open_maw"
        case digest
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.search,
            verbs: [.kbiteSearch],
            summary: "bm25-ranked kbite file stubs with briefs — read the briefs first.",
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "limit"],
                retryWith: "cde_kbite op=search with cursor = page.next_cursor"
            ),
            requiredParams: ["query"]
        ),
        GmAgentToolOp(
            Op.openMaw,
            verbs: [.kbiteMawOpen],
            summary: """
                Open a maw — the staging directory a kbite's raw sources are \
                collected into before they are chewed and digested.
                """,
            requiredParams: ["kbite_name", "maw_path"]
        ),
        GmAgentToolOp(
            Op.digest,
            verbs: [.kbiteDigest],
            summary: "Digest a chewed maw into the database and archive its raw sources.",
            requiredParams: ["code", "kbite_open_path"]
        ),
    ]

    static let alwaysLoad = true

    let name = "cde_kbite"
    let description = """
        Pre-indexed external knowledge: search digested kbite files, open a maw \
        to collect raw sources, digest a chewed maw.
        """

    typealias Arguments = GmAgentCdeKbiteArguments
    typealias Output = String

    /// Creates a cde_kbite tool instance.
    init() {}
}
