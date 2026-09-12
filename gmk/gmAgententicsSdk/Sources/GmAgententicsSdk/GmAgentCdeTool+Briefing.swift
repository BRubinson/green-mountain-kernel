import Foundation
import FoundationModels
import GmDaemonSdk

// The briefing trio, plus the read every explorer pulls at spawn.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenBriefingArguments: Sendable {
    @Guide(description: "Which prompt the briefing belongs to, by uuid.")
    public var promptUuid: String

    @Guide(description: "Which briefing step. Use 'initial' unless you know otherwise.")
    public var step: String

    public init(promptUuid: String, step: String = "initial") {
        self.promptUuid = promptUuid
        self.step = step
    }
}

/// Make empty note page for the dope agent to fill.
///
/// THIS CALL STARTS THE PROMPT. Opening a briefing moves the prompt from draft
/// to initiated, daemon-side and idempotently — it is not a separate step the
/// caller has to remember.
///
/// It is here rather than on `load_prompt` for one reason: loading has to stay a
/// pure read. If merely looking at a prompt advanced it, inspection would be
/// destructive, and in an append-only db that cannot be taken back. Opening a
/// briefing is the first act of real work, so it is the honest trigger.
///
/// Opening an existing briefing RESETS it rather than duplicating, and the reset
/// TRUNCATES its refs — a step's briefing is its current briefing, and stale
/// refs must not leak into the rebuilt one.
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
    @Guide(description: "Which briefing to write to, by uuid.")
    public var briefingUuid: String

    @Guide(description: "Version of the briefing you read, so two writers cannot clobber each other.")
    public var expectedVersion: Int

    @Guide(description: """
        Dope dot-path CODES like domain.entity.property — never uuids. Put an \
        empty list if you looked and found none; an empty list is a real answer.
        """)
    public var dopeRefs: [String]

    @Guide(description: """
        Kbite file uuids. Put an empty list if you looked and found none; an \
        empty list is a real answer.
        """)
    public var kbiteRefs: [String]

    @Guide(description: """
        File change uuids. Put an empty list if there are none; an empty list \
        is a real answer.
        """)
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

/// Put dope, kbite, and file-change notes on the page.
///
/// GENUINELY BATCH, unlike most writes in this surface: `BRIEFING_COMPLETE`
/// takes all three ref arrays in one call, so there is no loop and no
/// partial-write hazard here.
///
/// ALL THREE CLASSES ARE REQUIRED, and the schema enforces it by making them
/// non-optional arrays. The contract is that a briefing records what it LOOKED
/// FOR, not only what it found: an empty list means "searched, found none",
/// which is information, while an omitted list is indistinguishable from never
/// having looked. That distinction is the whole reason the arrays are not
/// optional — a model given `[String]?` will omit the one it has nothing for.
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
    @Guide(description: "Which briefing to mark ready, by uuid.")
    public var briefingUuid: String

    @Guide(description: "Version of the briefing you read.")
    public var expectedVersion: Int

    public init(briefingUuid: String, expectedVersion: Int) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
    }
}

/// Page is done, agent can go away now.
///
/// The last thing a doper does. Marking the briefing ready is what releases
/// whoever is waiting on it — the machine refuses to leave the briefing phase
/// until this lands.
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
    @Guide(description: "Which briefing to read, by uuid.")
    public var briefingUuid: String

    public init(briefingUuid: String) {
        self.briefingUuid = briefingUuid
    }
}

/// Read the page everyone should know.
///
/// What every exploration agent pulls at spawn: the pre-seeded refs its whole
/// cohort shares, so each agent starts from the same ground rather than
/// rediscovering it in parallel.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeLoadBriefTool: GmAgentCdeTool {
    public let name = "cde_load_exploration_brief"
    public let description = "Read the page everyone should know."

    public init() {}

    public func call(arguments: GmAgentCdeLoadBriefArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "BRIEFING_GET")
    }
}
