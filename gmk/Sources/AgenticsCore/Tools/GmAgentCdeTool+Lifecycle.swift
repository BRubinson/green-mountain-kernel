// Agent tools for a prompt's life: the cold-start fold, and the prompt row itself.

import Foundation
import FoundationModels

@Generable
struct GmAgentCdeInitArguments: Sendable {
    @Guide(
        description: "The only op: fold identity, prompt and briefing into one answer.",
        .anyOf(GmAgentCdeInitTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(
        description: "Prompt seq (10), code (p10), exact name, or a unique fragment of a name."
    )
    var selector: String?

    @Guide(description: "Workflow variant: bot | rpi | team (default bot).")
    var variant: String?

    @Guide(
        description: """
            Create the prompt when the selector matches nothing. Requires name and \
            detail — a typo must never create a prompt.
            """
    )
    var create: Bool?

    @Guide(description: "Name for a newly created prompt (with create).")
    var name: String?

    @Guide(
        description: """
            Detail text for a newly created prompt (with create). STAY TRUE: the \
            user's passed prompt, verbatim.
            """
    )
    var detail: String?

    /// Initializes arguments for the cde init tool.
    ///
    /// - Parameters:
    ///   - op: The operation to perform (default: `"run"`).
    ///   - selector: A prompt identifier selector.
    ///   - variant: The workflow variant (default: `"bot"`).
    ///   - create: Whether to create a prompt if not found.
    ///   - name: The name for a new prompt.
    ///   - detail: The detail text for a new prompt.
    init(
        op: String = GmAgentCdeInitTool.Op.run.rawValue,
        selector: String? = nil,
        variant: String? = nil,
        create: Bool? = nil,
        name: String? = nil,
        detail: String? = nil
    ) {
        self.op = op
        self.selector = selector
        self.variant = variant
        self.create = create
        self.name = name
        self.detail = detail
    }
}

struct GmAgentCdeInitTool: GmAgentCdeTool {

    enum Op: String, CaseIterable, Sendable {
        case run
    }

    typealias Arguments = GmAgentCdeInitArguments

    typealias Output = String

    let name = "cde_init"
    let description = "Tell me who I am and what I am working on."

    static let alwaysLoad = true

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.run,
            verbs: [.contextEnsure, .promptList, .promptCreate, .promptResume, .botNext, .briefingGet],
            summary: """
                The cold start: resolve project, instance and session from the working \
                directory, resolve or create the prompt, and answer with the phase, its \
                instructions and the briefing's state.
                """
        )
    ]

    /// Initializes the cde init tool.
    init() {}
}

// A property name here IS the wire argument name, so it stays snake_case.
// swiftlint:disable identifier_name
@Generable
struct GmAgentCdePromptArguments: Sendable {
    @Guide(
        description: """
            What to do with the prompt: read it, list prompts, edit a draft, move it, or \
            read its file changes.
            """,
        .anyOf(GmAgentCdePromptTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(
        description: promptUuidGuide("to read or write")
            + " Leave it out to use the prompt this session is on."
    )
    var prompt_uuid: String?

    @Guide(
        description: """
            list: which prompts — a number like 1, a code like p10, or a unique piece \
            of a name. Leave it out to list them all.
            """
    )
    var selector: String?

    @Guide(
        description: """
            list, file_changes: which session. Leave it out for the session this \
            working directory resolves to.
            """
    )
    var session_uuid: String?

    @Guide(
        description: """
            draft, set_status: version of the prompt you read, so two writers cannot \
            clobber each other.
            """
    )
    var expected_version: Int?

    @Guide(description: "draft: the prompt's detail. Leave it out to leave it alone.")
    var detail: String?

    @Guide(description: "draft: the prompt's backstory. Leave it out to leave it alone.")
    var backstory: String?

    @Guide(description: "draft: the prompt's goal. Leave it out to leave it alone.")
    var goal: String?

    @Guide(
        description: """
            set_status: where to move it — 'initiated' to start, 'done' to finish, or \
            'draft' to send a finished prompt back for editing.
            """,
        .anyOf(GM_TOOL_ANYOF_PROMPT_STATUS)
    )
    var status: String?

    @Guide(
        description: "file_changes: only changes to this repo-relative path. Leave it out for every file."
    )
    var path: String?

    @Guide(description: "file_changes: how many rows to consider, newest first.")
    var limit: Int?

    @Guide(description: "Page cursor from the previous call's page.next_cursor; leave it out for the first page.")
    var cursor: String?

    @Guide(description: "Page budget in bytes; every array and every long text is paged inside it.")
    var page_bytes: Int?

    /// Initializes arguments for the cde prompt tool.
    ///
    /// - Parameters:
    ///   - op: The operation to perform.
    ///   - prompt_uuid: The prompt's identifier.
    ///   - selector: A prompt selector for listing.
    ///   - session_uuid: The session's identifier.
    ///   - expected_version: The prompt's last-read version.
    ///   - detail: The prompt's detail text.
    ///   - backstory: The prompt's backstory.
    ///   - goal: The prompt's goal.
    ///   - status: The new status when transitioning.
    ///   - path: A repo-relative path for file changes.
    ///   - limit: The maximum number of file changes to return.
    ///   - cursor: A pagination cursor for continued reads.
    ///   - page_bytes: The page size budget in bytes.
    init(
        op: String,
        prompt_uuid: String? = nil,
        selector: String? = nil,
        session_uuid: String? = nil,
        expected_version: Int? = nil,
        detail: String? = nil,
        backstory: String? = nil,
        goal: String? = nil,
        status: String? = nil,
        path: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.prompt_uuid = prompt_uuid
        self.selector = selector
        self.session_uuid = session_uuid
        self.expected_version = expected_version
        self.detail = detail
        self.backstory = backstory
        self.goal = goal
        self.status = status
        self.path = path
        self.limit = limit
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}
// swiftlint:enable identifier_name

struct GmAgentCdePromptTool: GmAgentCdeTool {

    enum Op: String, CaseIterable, Sendable {
        case load
        case list
        case draft
        case setStatus = "set_status"
        case fileChanges = "file_changes"
    }

    typealias Arguments = GmAgentCdePromptArguments

    typealias Output = String

    let name = "cde_prompt"
    let description = """
        The workflow's prompt: read it without being told a uuid, list prompts, edit a \
        draft's backstory / goal / detail, move it through draft → initiated → done, or \
        read the file changes recorded against it. Long text arrives as windows — loop on \
        cursor until page.next_cursor is null.
        """

    static let alwaysLoad = true

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.load,
            verbs: [.botGet, .promptGet],
            summary: """
                The prompt this workflow is on. Reading it never advances it; its detail, \
                backstory and goal arrive as text windows.
                """,
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes"],
                retryWith: "cde_prompt op=load with cursor = page.next_cursor"
            )
        ),
        GmAgentToolOp(
            Op.list,
            verbs: [.promptList],
            summary: "The session's prompts, narrowed by an optional selector."
        ),
        GmAgentToolOp(
            Op.draft,
            verbs: [.promptUpdateContent],
            summary: """
                Edit a DRAFT prompt's stay-true triple. The daemon refuses once the prompt \
                has left draft, so re-open it first.
                """,
            requiredParams: ["prompt_uuid", "expected_version"]
        ),
        GmAgentToolOp(
            Op.setStatus,
            verbs: [.promptSetStatus],
            summary: """
                THE ONLY DOOR THAT MOVES A PROMPT, and it claims or releases the prompt's \
                activation for this instance. It creates no summaries. Primary only.
                """,
            requiredParams: ["prompt_uuid", "expected_version", "status"]
        ),
        GmAgentToolOp(
            Op.fileChanges,
            verbs: [.fileChangeList],
            summary: """
                READ ONLY: what the machine believes you have touched. Capture belongs to \
                the PostToolUse hook, so there is no op here that writes one.
                """,
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "path", "limit"],
                retryWith: "cde_prompt op=file_changes with cursor = page.next_cursor; path for one file"
            )
        ),
    ]

    /// Initializes the cde prompt tool.
    init() {}
}
