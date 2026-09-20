// Agent tools that move a prompt through the machine: init, next, load and status.

import Foundation
import FoundationModels

@Generable
struct GmAgentCdeInitArguments: Sendable {
    init() {}
}

struct GmAgentCdeInitTool: GmAgentCdeTool {
    let name = "cde_init"
    let description = "Tell me who I am and what I am working on."

    init() {}

    func call(arguments _: GmAgentCdeInitArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "CONTEXT_GET + PATHS_GET + AGENT_REGISTER"
        )
    }
}

@Generable
enum GmAgentPromptMatchKind: String, Sendable {
    case seq
    case code
    case name
    case nameSubstring
    case uuid
    case ambiguous
    case notFound
}

@Generable
struct GmAgentLoadedPrompt: Sendable {
    @Guide(description: "How the selector matched, or 'ambiguous'/'notFound' if it did not.")
    var matchKind: GmAgentPromptMatchKind

    @Guide(description: "The matched prompt's uuid, empty if nothing matched.")
    var promptUuid: String

    @Guide(description: "Where the prompt is: draft, initiated, or done.")
    var status: String

    @Guide(description: "Every prompt the selector matched, when it matched more than one.")
    var candidates: [String]

    @Guide(description: "Briefings that exist for this prompt, top level only.")
    var briefingUuids: [String]

    @Guide(description: "Kbite codes switched on for this prompt.")
    var kbiteCodes: [String]

    init(
        matchKind: GmAgentPromptMatchKind,
        promptUuid: String = "",
        status: String = "",
        candidates: [String] = [],
        briefingUuids: [String] = [],
        kbiteCodes: [String] = []
    ) {
        self.matchKind = matchKind
        self.promptUuid = promptUuid
        self.status = status
        self.candidates = candidates
        self.briefingUuids = briefingUuids
        self.kbiteCodes = kbiteCodes
    }
}

@Generable
struct GmAgentCdeLoadPromptArguments: Sendable {
    @Guide(
        description: """
            Which prompt: a number like 1, a code like p10, its exact name, a \
            unique piece of its name, or its uuid.
            """
    )
    var selector: String

    init(selector: String) {
        self.selector = selector
    }
}

struct GmAgentCdeLoadPromptTool: GmAgentCdeTool {
    let name = "cde_load_prompt"
    let description = "Get one prompt by number, name, or id."

    init() {}

    func call(
        arguments _: GmAgentCdeLoadPromptArguments
    ) throws -> GmAgentLoadedPrompt {
        throw GmAgentToolError.notWired(tool: name, verb: "PROMPT_LIST + PROMPT_GET + BRIEFING_LIST")
    }
}

@Generable
struct GmAgentCdeSetStatusArguments: Sendable {
    @Guide(description: promptUuidGuide("to move"))
    var promptUuid: String

    @Guide(description: "Version of the prompt you read, so two writers cannot clobber each other.")
    var expectedVersion: Int

    @Guide(
        description: """
            Where to move it: 'initiated' to start, 'done' to finish, or 'draft' to \
            send a finished prompt back for editing.
            """,
        .anyOf(GM_TOOL_ANYOF_PROMPT_STATUS)
    )
    var status: String

    init(promptUuid: String, expectedVersion: Int, status: String) {
        self.promptUuid = promptUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

struct GmAgentCdeSetStatusTool: GmAgentCdeTool {
    let name = "cde_set_status"
    let description = "Say the prompt is started or finished."

    init() {}

    func call(arguments _: GmAgentCdeSetStatusArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "PROMPT_SET_STATUS")
    }
}

@Generable
struct GmAgentCdeNextArguments: Sendable {
    @Guide(description: "Which prompt, by uuid. Leave empty to use the one this session is on.")
    var promptUuid: String

    init(promptUuid: String = "") {
        self.promptUuid = promptUuid
    }
}

struct GmAgentRpirNextTool: GmAgentRpirTool {
    let name = "rpir_next"
    let description = "What phase am I in and what do I do now?"

    init() {}

    func call(arguments _: GmAgentCdeNextArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BOT_NEXT")
    }
}
