import Foundation
import FoundationModels
import GmDaemonSdk

// The CDE entry points: who am I, which prompt, start/finish, what now.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeInitArguments: Sendable {
    public init() {}
}

/// Tell me who I am and what I am working on.
///
/// The first call a primary agent makes. The SessionStart hook has already
/// registered the agent's identity and env, so this READS that rather than
/// establishing it — composing the context, the resolved paths, and whatever
/// the agent registry knows about this agent id, then rendering it plainly for
/// the user.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeInitTool: GmAgentCdeTool {
    public let name = "cde_init"
    public let description = "Tell me who I am and what I am working on."

    public init() {}

    public func call(arguments: GmAgentCdeInitArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "CONTEXT_GET + PATHS_GET + AGENT_REGISTER")
    }
}

/// How a selector matched, mirroring `PromptResolver.MatchKind` plus the two
/// non-match outcomes.
@available(GmAgentOs 1.0, *)
@Generable
public enum GmAgentPromptMatchKind: String, Sendable {
    case seq
    case code
    case name
    case nameSubstring
    case uuid
    case ambiguous
    case notFound
}

/// What `load_prompt` gives back.
///
/// THE SHAPE IS A SUM, NOT A STRUCT WITH OPTIONALS, and that is the whole point.
/// `PromptResolver.Resolution` has three arms — matched, ambiguous, notFound —
/// and its header is explicit that ambiguity is a RESULT and never a guess:
/// "Silently picking the first would file a session's work against the wrong
/// prompt, and the append-only db means that mistake is permanent." A result
/// type that can only express success forces exactly that mistake, so `matchKind`
/// carries the outcome and `candidates` carries the alternatives when there is
/// more than one.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentLoadedPrompt: Sendable {
    @Guide(description: "How the selector matched, or 'ambiguous'/'notFound' if it did not.")
    public var matchKind: GmAgentPromptMatchKind

    @Guide(description: "The matched prompt's uuid, empty if nothing matched.")
    public var promptUuid: String

    @Guide(description: "Where the prompt is: draft, initiated, or done.")
    public var status: String

    @Guide(description: "Every prompt the selector matched, when it matched more than one.")
    public var candidates: [String]

    @Guide(description: "Briefings that exist for this prompt, top level only.")
    public var briefingUuids: [String]

    @Guide(description: "Kbite codes switched on for this prompt.")
    public var kbiteCodes: [String]

    public init(
        matchKind: GmAgentPromptMatchKind, promptUuid: String = "", status: String = "",
        candidates: [String] = [], briefingUuids: [String] = [], kbiteCodes: [String] = []
    ) {
        self.matchKind = matchKind
        self.promptUuid = promptUuid
        self.status = status
        self.candidates = candidates
        self.briefingUuids = briefingUuids
        self.kbiteCodes = kbiteCodes
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeLoadPromptArguments: Sendable {
    @Guide(description: """
        Which prompt: a number like 1, a code like p10, its exact name, a \
        unique piece of its name, or its uuid.
        """)
    public var selector: String

    public init(selector: String) {
        self.selector = selector
    }
}

/// Get one prompt by number, name, or id.
///
/// REUSE `PromptResolver` RATHER THAN RE-DERIVING IT. Its four tiers are tried
/// to exhaustion in order — bare integer as `seq`, then `code`, then exact name,
/// then unique name substring — and the ordering matters: an exact name must
/// never lose to a substring hit on a different prompt. It is pure, folding over
/// the stubs `PROMPT_LIST` already returns, and it rests on
/// `UNIQUE(session_uuid, seq)` and `UNIQUE(session_uuid, code)`, which is what
/// makes seq and code single-valued answers rather than best guesses.
///
/// ONE GAP TO CLOSE WHEN WIRING: a raw uuid is NOT one of the four tiers. This
/// tool's description promises it, so try `PROMPT_GET` with the selector first
/// and fall through to the resolver — do not let a uuid drift into the substring
/// tier, where it will simply miss.
///
/// The return composes TWO verbs. `PROMPT_GET` yields the row, artifacts, kbite
/// codes and a change summary but NOT briefings; `BRIEFING_LIST` yields those.
///
/// THIS IS A PURE READ. It must not advance the prompt — `open_briefing` is what
/// moves draft to initiated. A read that mutates makes mere inspection
/// destructive, and in an append-only db that is not retractable.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeLoadPromptTool: GmAgentCdeTool {
    public let name = "cde_load_prompt"
    public let description = "Get one prompt by number, name, or id."

    public init() {}

    public func call(
        arguments: GmAgentCdeLoadPromptArguments
    ) async throws -> GmAgentLoadedPrompt {
        throw GmAgentToolError.notWired(tool: name, verb: "PROMPT_LIST + PROMPT_GET + BRIEFING_LIST")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeSetStatusArguments: Sendable {
    @Guide(description: "Which prompt to move, by uuid.")
    public var promptUuid: String

    @Guide(description: "Version of the prompt you read, so two writers cannot clobber each other.")
    public var expectedVersion: Int

    @Guide(description: """
        Where to move it: 'initiated' to start, 'done' to finish, or 'draft' to \
        send a finished prompt back for editing.
        """, .anyOf(["draft", "initiated", "done"]))
    public var status: String

    public init(promptUuid: String, expectedVersion: Int, status: String) {
        self.promptUuid = promptUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

/// Say the prompt is started or finished.
///
/// The parent bot's tool. Three states and a cycle: draft → initiated → done,
/// and done → draft to re-open a finished prompt for editing.
///
/// In practice the bot calls this for `done`. The draft → initiated move happens
/// daemon-side when the briefing is opened, so the start does not depend on an
/// agent remembering to make it; this tool can still make it explicitly, which
/// is what the idempotent guard on the briefing side allows for.
///
/// `done` has two side effects worth knowing before calling it: it releases the
/// prompt's activation claim, and it closes the prompt's active workflow row.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeSetStatusTool: GmAgentCdeTool {
    public let name = "cde_set_status"
    public let description = "Say the prompt is started or finished."

    public init() {}

    public func call(arguments: GmAgentCdeSetStatusArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "PROMPT_SET_STATUS")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeNextArguments: Sendable {
    @Guide(description: "Which prompt, by uuid. Leave empty to use the one this session is on.")
    public var promptUuid: String

    public init(promptUuid: String = "") {
        self.promptUuid = promptUuid
    }
}

/// What phase am I in and what do I do now?
///
/// DERIVED — the prompt behind this surface never named it, and it is the most
/// called verb in the whole lifecycle. It returns the phase, that phase's
/// instructions, the uuid bundle and the gate blockers, so an agent needs no
/// other document to know what to do next.
///
/// Phase is COMPUTED from db evidence on every call, with no stored cursor. That
/// is why collapsing the prompt's own status to three states cost nothing: the
/// machine never read status to know where it was. It also means resume is the
/// only code path there is — asking again is how you recover.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeNextTool: GmAgentCdeTool {
    public let name = "cde_next"
    public let description = "What phase am I in and what do I do now?"

    public init() {}

    public func call(arguments: GmAgentCdeNextArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BOT_NEXT")
    }
}
