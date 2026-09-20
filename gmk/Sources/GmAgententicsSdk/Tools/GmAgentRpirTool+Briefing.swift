// Agent tools for the briefing phase: opening, writing and closing a briefing's ref set.

import Foundation
import FoundationModels

@Generable
struct GmAgentRpirOpenBriefingArguments: Sendable {
    @Guide(description: promptUuidGuide("the briefing belongs to"))
    var promptUuid: String

    @Guide(description: "Which briefing step. 'initial' is the only accepted value; the daemon rejects anything else.")
    var step: String

    init(promptUuid: String, step: String = "initial") {
        self.promptUuid = promptUuid
        self.step = step
    }
}

struct GmAgentRpirOpenBriefingTool: GmAgentRpirTool {
    let name = "rpir_open_briefing"
    let description = "Make empty note page for the briefer to fill."

    init() {}

    func call(arguments _: GmAgentRpirOpenBriefingArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_OPEN")
    }
}

@Generable
struct GmAgentRpirWriteBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "briefing"))
    var briefingUuid: String

    @Guide(description: "Version of the briefing you read, so two writers cannot clobber each other.")
    var expectedVersion: Int

    @Guide(description: GM_TOOL_GUIDE_DOPE_CODE + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var dopeRefs: [String]

    @Guide(description: GM_TOOL_GUIDE_KBITE_FILE_UUID + " " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var kbiteRefs: [String]

    @Guide(description: "File change uuids. " + GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER)
    var fileChangeRefs: [String]

    init(
        briefingUuid: String,
        expectedVersion: Int,
        dopeRefs: [String],
        kbiteRefs: [String],
        fileChangeRefs: [String]
    ) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
        self.dopeRefs = dopeRefs
        self.kbiteRefs = kbiteRefs
        self.fileChangeRefs = fileChangeRefs
    }
}

struct GmAgentRpirWriteBriefTool: GmAgentRpirTool {
    let name = "rpir_write_brief"
    let description = "Put dope, kbite, and file-change notes on the page."

    init() {}

    func call(arguments _: GmAgentRpirWriteBriefArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_COMPLETE")
    }
}

@Generable
struct GmAgentRpirCloseBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "mark ready", "briefing"))
    var briefingUuid: String

    @Guide(description: "Version of the briefing you read.")
    var expectedVersion: Int

    init(briefingUuid: String, expectedVersion: Int) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
    }
}

struct GmAgentRpirCloseBriefTool: GmAgentRpirTool {
    let name = "rpir_close_brief"
    let description = "Page is done, agent can go away now."

    init() {}

    func call(arguments _: GmAgentRpirCloseBriefArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_COMPLETE")
    }
}

@Generable
struct GmAgentRpirLoadBriefArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "read", "briefing"))
    var briefingUuid: String

    init(briefingUuid: String) {
        self.briefingUuid = briefingUuid
    }
}

struct GmAgentRpirLoadBriefTool: GmAgentRpirTool {
    let name = "rpir_load_exploration_brief"
    let description = "Read the page everyone should know."

    init() {}

    func call(arguments _: GmAgentRpirLoadBriefArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_GET")
    }
}
