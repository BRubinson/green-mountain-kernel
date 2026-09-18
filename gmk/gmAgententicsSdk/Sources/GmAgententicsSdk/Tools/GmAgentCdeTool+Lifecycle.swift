// Agent tools that move a prompt through the machine: init, next, load and status.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeInitArguments: Sendable {
    public init() {}
}

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
    @Guide(
        description: """
            Which prompt: a number like 1, a code like p10, its exact name, a \
            unique piece of its name, or its uuid.
            """)
    public var selector: String

    public init(selector: String) {
        self.selector = selector
    }
}

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
    @Guide(description: promptUuidGuide("to move"))
    public var promptUuid: String

    @Guide(description: "Version of the prompt you read, so two writers cannot clobber each other.")
    public var expectedVersion: Int

    @Guide(
        description: """
            Where to move it: 'initiated' to start, 'done' to finish, or 'draft' to \
            send a finished prompt back for editing.
            """, .anyOf(GM_TOOL_ANYOF_PROMPT_STATUS))
    public var status: String

    public init(promptUuid: String, expectedVersion: Int, status: String) {
        self.promptUuid = promptUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

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

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirNextTool: GmAgentRpirTool {
    public let name = "rpir_next"
    public let description = "What phase am I in and what do I do now?"

    public init() {}

    public func call(arguments: GmAgentCdeNextArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BOT_NEXT")
    }
}
