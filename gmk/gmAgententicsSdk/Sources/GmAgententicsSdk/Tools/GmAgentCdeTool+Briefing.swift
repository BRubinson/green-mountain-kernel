// Agent tools for the briefing phase: opening, writing and closing a briefing's ref set.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenBriefingArguments: Sendable {
    @Guide(description: promptUuidGuide("the briefing belongs to"))
    public var promptUuid: String

    @Guide(description: "Which briefing step. Use 'initial' unless you know otherwise.")
    public var step: String

    public init(promptUuid: String, step: String = "initial") {
        self.promptUuid = promptUuid
        self.step = step
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenBriefingTool: GmAgentCdeTool {
    public let name = "cde_open_briefing"
    public let description = "Make empty note page for the dope agent to fill."

    public init() {}

    public func call(arguments: GmAgentCdeOpenBriefingArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeWriteBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "briefing"))
    public var briefingUuid: String

    @Guide(description: "Version of the briefing you read, so two writers cannot clobber each other.")
    public var expectedVersion: Int

    @Guide(description: GM_TOOL_GUIDE_DOPE_CODE + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    public var dopeRefs: [String]

    @Guide(description: GM_TOOL_GUIDE_KBITE_FILE_UUID + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    public var kbiteRefs: [String]

    @Guide(description: "File change uuids. " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    public var fileChangeRefs: [String]

    public init(
        briefingUuid: String, expectedVersion: Int,
        dopeRefs: [String], kbiteRefs: [String], fileChangeRefs: [String]
    ) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
        self.dopeRefs = dopeRefs
        self.kbiteRefs = kbiteRefs
        self.fileChangeRefs = fileChangeRefs
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteBriefTool: GmAgentCdeTool {
    public let name = "cde_write_brief"
    public let description = "Put dope, kbite, and file-change notes on the page."

    public init() {}

    public func call(arguments: GmAgentCdeWriteBriefArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeCloseBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "mark ready", "briefing"))
    public var briefingUuid: String

    @Guide(description: "Version of the briefing you read.")
    public var expectedVersion: Int

    public init(briefingUuid: String, expectedVersion: Int) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeCloseBriefTool: GmAgentCdeTool {
    public let name = "cde_close_brief"
    public let description = "Page is done, agent can go away now."

    public init() {}

    public func call(arguments: GmAgentCdeCloseBriefArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeLoadBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "read", "briefing"))
    public var briefingUuid: String

    public init(briefingUuid: String) {
        self.briefingUuid = briefingUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeLoadBriefTool: GmAgentCdeTool {
    public let name = "cde_load_exploration_brief"
    public let description = "Read the page everyone should know."

    public init() {}

    public func call(arguments: GmAgentCdeLoadBriefArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_GET")
    }
}
