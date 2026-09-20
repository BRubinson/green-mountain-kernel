// Agent tools for the architecture phase: options, the decision, and the change rows expanded from it.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirOpenArchitectureArguments: Sendable {
    @Guide(description: promptUuidGuide("to open an architecture summary for"))
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirOpenArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_open_architecture"
    public let description = "Start the plan page."

    public init() {}

    public func call(arguments _: GmAgentRpirOpenArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirOpenArchitectureOptionArguments: Sendable {
    @Guide(description: "Which prompt's architecture, by summary uuid.")
    public var summaryUuid: String

    @Guide(description: "Your methodology name. One plan per methodology.")
    public var agentName: String

    @Guide(description: "Your own agent id.")
    public var agentId: String

    @Guide(description: "Your whole proposal, written out.")
    public var body: String

    @Guide(
        description: """
            Option this proposal REPLACES, by uuid. Leave empty for a new \
            proposal. The old row stays as rejected history, and if it was the \
            selected plan the new one takes the selection.
            """
    )
    public var supersedesOptionUuid: String

    @Guide(description: "Version of the replaced option. Required with supersedesOptionUuid.")
    public var expectedVersion: Int

    public init(
        summaryUuid: String,
        agentName: String,
        agentId: String = "",
        body: String,
        supersedesOptionUuid: String = "",
        expectedVersion: Int = 0
    ) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.agentId = agentId
        self.body = body
        self.supersedesOptionUuid = supersedesOptionUuid
        self.expectedVersion = expectedVersion
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirOpenArchitectureOptionTool: GmAgentRpirTool {
    public let name = "rpir_open_architecture_option"
    public let description = "Start my own plan."

    public init() {}

    public func call(
        arguments _: GmAgentRpirOpenArchitectureOptionArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_OPTION_ADD")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentPersistenceFieldChange: Sendable {
    @Guide(description: "Name of the field.")
    public var fieldName: String

    @Guide(description: "Type of the field.")
    public var dataType: String

    @Guide(description: "Why this field is changing.")
    public var changeReason: String

    @Guide(description: "What the change is for.")
    public var changePurpose: String

    @Guide(description: "True if the field may be null.")
    public var nullable: Bool

    @Guide(description: "True if the field points at another table.")
    public var isForeignKey: Bool

    @Guide(description: "What is happening to it.", .anyOf(GM_TOOL_ANYOF_ARCH_CHANGE_KIND))
    public var changeKind: String

    @Guide(description: "Old field name, only when renaming.")
    public var renamedFrom: String

    @Guide(description: "For the property. " + GM_TOOL_GUIDE_DOPE_CODE)
    public var dopePropertyRef: String

    public init(
        fieldName: String,
        dataType: String,
        changeReason: String,
        changePurpose: String,
        nullable: Bool = false,
        isForeignKey: Bool = false,
        changeKind: String = "add",
        renamedFrom: String = "",
        dopePropertyRef: String = ""
    ) {
        self.fieldName = fieldName
        self.dataType = dataType
        self.changeReason = changeReason
        self.changePurpose = changePurpose
        self.nullable = nullable
        self.isForeignKey = isForeignKey
        self.changeKind = changeKind
        self.renamedFrom = renamedFrom
        self.dopePropertyRef = dopePropertyRef
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentPersistenceChange: Sendable {
    @Guide(description: "Name of the class or table changing.")
    public var className: String

    @Guide(description: "Repo-relative file it lives in.")
    public var filePath: String

    @Guide(description: "Why this change, in one or two sentences.")
    public var reasonBrief: String

    @Guide(description: "What is happening to it.", .anyOf(GM_TOOL_ANYOF_ARCH_CHANGE_KIND))
    public var changeKind: String

    @Guide(description: "For the entity. " + GM_TOOL_GUIDE_DOPE_CODE)
    public var dopeRef: String

    @Guide(description: "The field-level changes inside this one.")
    public var fields: [GmAgentPersistenceFieldChange]

    public init(
        className: String,
        filePath: String,
        reasonBrief: String,
        changeKind: String = "modify",
        dopeRef: String = "",
        fields: [GmAgentPersistenceFieldChange] = []
    ) {
        self.className = className
        self.filePath = filePath
        self.reasonBrief = reasonBrief
        self.changeKind = changeKind
        self.dopeRef = dopeRef
        self.fields = fields
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWritePersistenceChangesArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "architecture"))
    public var summaryUuid: String

    @Guide(description: "All the database changes, in one go.")
    public var changes: [GmAgentPersistenceChange]

    public init(summaryUuid: String, changes: [GmAgentPersistenceChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteArchitecturePersistenceChangesTool: GmAgentRpirTool {
    public let name = "rpir_write_architecture_persistence_changes"
    public let description = "Write down many database changes."

    public init() {}

    public func call(
        arguments _: GmAgentRpirWritePersistenceChangesArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "ARCH_PERSIST_ADD + ARCH_FIELD_ADD (looped)"
        )
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentGeneralChange: Sendable {
    @Guide(description: "Repo-relative file this change owns.")
    public var filePath: String

    @Guide(description: "Class or type being changed, if there is one.")
    public var className: String

    @Guide(description: "Why this change, in one or two sentences.")
    public var reasonBrief: String

    @Guide(description: "How worked-out it is.", .anyOf(GM_TOOL_ANYOF_CHANGE_DEPTH))
    public var changeDepth: String

    @Guide(
        description: """
            The instruction whoever implements this will follow. Write it to them, \
            not about them.
            """
    )
    public var changeCode: String

    public init(
        filePath: String,
        className: String = "",
        reasonBrief: String,
        changeDepth: String = "actual",
        changeCode: String
    ) {
        self.filePath = filePath
        self.className = className
        self.reasonBrief = reasonBrief
        self.changeDepth = changeDepth
        self.changeCode = changeCode
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWriteGeneralChangesArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "architecture"))
    public var summaryUuid: String

    @Guide(description: "All the code changes, in one go.")
    public var changes: [GmAgentGeneralChange]

    public init(summaryUuid: String, changes: [GmAgentGeneralChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteArchitectureGeneralChangesTool: GmAgentRpirTool {
    public let name = "rpir_write_architecture_general_changes"
    public let description = "Write down many code changes."

    public init() {}

    public func call(arguments _: GmAgentRpirWriteGeneralChangesArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GENERAL_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWriteFieldChangesArguments: Sendable {
    @Guide(description: "The database change row these fields belong to, by uuid.")
    public var persistenceChangeUuid: String

    @Guide(description: "All the field changes for that row, in one go.")
    public var fields: [GmAgentPersistenceFieldChange]

    public init(persistenceChangeUuid: String, fields: [GmAgentPersistenceFieldChange]) {
        self.persistenceChangeUuid = persistenceChangeUuid
        self.fields = fields
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteArchitectureFieldChangesTool: GmAgentRpirTool {
    public let name = "rpir_write_architecture_field_changes"
    public let description = "Write down field-level changes under one database change."

    public init() {}

    public func call(arguments _: GmAgentRpirWriteFieldChangesArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_FIELD_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirSummarizeArchitectureArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write", "architecture"))
    public var summaryUuid: String

    @Guide(description: "Version of the summary you read.")
    public var expectedVersion: Int

    @Guide(description: "The plan narrative, written over the expanded rows.")
    public var body: String

    public init(summaryUuid: String, expectedVersion: Int, body: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.body = body
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirSummarizeArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_summarize_architecture"
    public let description = "Write the plan's own summary."

    public init() {}

    public func call(arguments _: GmAgentRpirSummarizeArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_SUMMARIZE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirArchitectureGateArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "move", "architecture"))
    public var summaryUuid: String

    @Guide(description: "Version of the summary you read.")
    public var expectedVersion: Int

    public init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirProposeArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_propose_architecture"
    public let description = "Put the plan on the table."

    public init() {}

    public func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_PROPOSE")
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirApproveArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_approve_architecture"
    public let description = "The human said yes; lock the plan."

    public init() {}

    public func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_APPROVE")
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirReviseArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_revise_architecture"
    public let description = "Reopen the plan for changes."

    public init() {}

    public func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_REVISE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirDecideArchitectureArguments: Sendable {
    @Guide(description: "Which plan won, by option uuid.")
    public var optionUuid: String

    @Guide(description: "Version of the option you read.")
    public var expectedVersion: Int

    @Guide(
        description: """
            Why this plan won, and what the rejected ones still contribute. A \
            decision with no reasoning gets argued again later.
            """
    )
    public var rationale: String

    public init(optionUuid: String, expectedVersion: Int, rationale: String) {
        self.optionUuid = optionUuid
        self.expectedVersion = expectedVersion
        self.rationale = rationale
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirDecideArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_decide_architecture"
    public let description = "Pick the winning plan."

    public init() {}

    public func call(arguments _: GmAgentRpirDecideArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_DECIDE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirGetArchitectureArguments: Sendable {
    @Guide(description: promptUuidGuide("'s architecture to read"))
    public var promptUuid: String

    @Guide(description: "Read one option in full, by uuid. Leave empty for short versions of all.")
    public var optionUuid: String

    @Guide(description: "Read one change in full, by uuid. Leave empty for short versions of all.")
    public var changeUuid: String

    public init(promptUuid: String, optionUuid: String = "", changeUuid: String = "") {
        self.promptUuid = promptUuid
        self.optionUuid = optionUuid
        self.changeUuid = changeUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirGetArchitectureTool: GmAgentRpirTool {
    public let name = "rpir_get_architecture"
    public let description = "Show me the plan and how much of it is built."

    public init() {}

    public func call(arguments _: GmAgentRpirGetArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GET")
    }
}
