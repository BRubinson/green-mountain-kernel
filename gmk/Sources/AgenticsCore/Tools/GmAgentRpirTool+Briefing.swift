// The briefing phase as one tool: open the page, write its refs, seal it, read it.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeRpirBriefingArguments: Sendable {

    @Guide(
        description: "Which briefing move to make.",
        .anyOf(GmAgentCdeRpirBriefingTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(description: promptUuidGuide("the briefing belongs to") + " Required by open.")
    var prompt_uuid: String?

    @Guide(
        description: """
            Which briefing step. 'initial' is the only accepted value; the daemon \
            rejects anything else.
            """
    )
    var step: String?

    @Guide(description: summaryUuidGuide(to: "write to", "briefing") + " Required by write and close.")
    var briefing_uuid: String?

    @Guide(description: GM_TOOL_GUIDE_VERSION_CONFLICT)
    var expected_version: Int?

    @Guide(description: GM_TOOL_GUIDE_DOPE_CODE + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var dope_refs: [String]?

    @Guide(description: GM_TOOL_GUIDE_KBITE_FILE_UUID + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var kbite_refs: [String]?

    @Guide(description: "File change uuids. " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var file_change_refs: [String]?

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID)
    var agent_id: String?

    @Guide(description: "page.next_cursor from the previous call (opaque) — omit for the first page. Load only.")
    var cursor: String?

    @Guide(
        description: """
            Page budget in bytes (default 30000, max 45000); every array and every \
            long text is paged inside it. Load only.
            """
    )
    var page_bytes: Int?

    init(
        op: String,
        prompt_uuid: String? = nil,
        step: String? = nil,
        briefing_uuid: String? = nil,
        expected_version: Int? = nil,
        dope_refs: [String]? = nil,
        kbite_refs: [String]? = nil,
        file_change_refs: [String]? = nil,
        agent_id: String? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.prompt_uuid = prompt_uuid
        self.step = step
        self.briefing_uuid = briefing_uuid
        self.expected_version = expected_version
        self.dope_refs = dope_refs
        self.kbite_refs = kbite_refs
        self.file_change_refs = file_change_refs
        self.agent_id = agent_id
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}

// swiftlint:enable identifier_name

struct GmAgentCdeRpirBriefingTool: GmAgentRpirTool {

    enum Op: String, CaseIterable, Sendable {
        case open
        case write
        case close
        case load
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.open,
            verbs: [.briefingOpen],
            requiredParams: ["prompt_uuid"],
            summary: """
                Open the briefing row a briefer then fills. The only legal response to the \
                'initial briefing not ready' gate blocker, and the very next call after cde_init \
                for a prompt whose briefing is absent.
                """
        ),
        GmAgentToolOp(
            Op.write,
            verbs: [.briefingComplete],
            requiredParams: [
                "briefing_uuid", "expected_version", "dope_refs", "kbite_refs", "file_change_refs",
            ],
            summary: """
                building → ready: write the briefing's ref set (opinion-free; the daemon \
                stamps staleness + kbite briefs). ALL THREE ref classes are REQUIRED of \
                you: a briefing records what it LOOKED FOR, not only what it found. Pass \
                [] for a class you searched and came up empty on — that is a real answer. \
                Omitting a class is refused, because absent is indistinguishable from \
                never having looked.
                """
        ),
        GmAgentToolOp(
            Op.close,
            verbs: [.briefingComplete],
            requiredParams: [
                "briefing_uuid", "expected_version", "dope_refs", "kbite_refs", "file_change_refs",
            ],
            summary: """
                Seal the briefing — the briefer's page is done and the agent can go away. \
                Same verb as op=write: BRIEFING_COMPLETE both writes the ref set and moves \
                building → ready.
                """
        ),
        GmAgentToolOp(
            Op.load,
            verbs: [.briefingGet],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes"],
                retryWith: "cde_rpir_briefing op=load with cursor = page.next_cursor"
            ),
            summary: """
                Fetch a briefing + staleness. Zero-uuid form: pass only step and YOUR \
                briefing resolves.
                """
        ),
    ]

    typealias Arguments = GmAgentCdeRpirBriefingArguments
    typealias Output = String

    let name = "cde_rpir_briefing"
    let description = """
        The briefing page: open it for a briefer, write its dope/kbite/file-change ref \
        set, seal it, and read it back.
        """

    init() {}
}
