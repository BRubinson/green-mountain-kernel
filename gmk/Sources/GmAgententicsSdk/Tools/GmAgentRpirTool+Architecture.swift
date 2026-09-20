// Agent tools for the architecture phase: options, the decision, and the change rows expanded from it.

import Foundation
import FoundationModels

@Generable
struct GmAgentRpirOpenArchitectureArguments: Sendable {
    @Guide(description: promptUuidGuide("to open an architecture summary for"))
    var promptUuid: String

    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct GmAgentRpirOpenArchitectureTool: GmAgentRpirTool {
    let name = "rpir_open_architecture"
    let description = "Start the plan page."

    init() {}

    func call(arguments _: GmAgentRpirOpenArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_OPEN")
    }
}

@Generable
struct GmAgentRpirOpenArchitectureOptionArguments: Sendable {
    @Guide(description: "Which prompt's architecture, by summary uuid.")
    var summaryUuid: String

    @Guide(description: "Your methodology name. One plan per methodology.")
    var agentName: String

    @Guide(description: "Your own agent id.")
    var agentId: String

    @Guide(description: "Your whole proposal, written out.")
    var body: String

    @Guide(
        description: """
            Option this proposal REPLACES, by uuid. Leave empty for a new \
            proposal. The old row stays as rejected history, and if it was the \
            selected plan the new one takes the selection.
            """
    )
    var supersedesOptionUuid: String

    @Guide(description: "Version of the replaced option. Required with supersedesOptionUuid.")
    var expectedVersion: Int

    init(
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

struct GmAgentRpirOpenArchitectureOptionTool: GmAgentRpirTool {
    let name = "rpir_open_architecture_option"
    let description = "Start my own plan."

    init() {}

    func call(
        arguments _: GmAgentRpirOpenArchitectureOptionArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_OPTION_ADD")
    }
}

@Generable
struct GmAgentPersistenceFieldChange: Sendable {
    @Guide(description: "Name of the field.")
    var fieldName: String

    @Guide(description: "Type of the field.")
    var dataType: String

    @Guide(description: "Why this field is changing.")
    var changeReason: String

    @Guide(description: "What the change is for.")
    var changePurpose: String

    @Guide(description: "True if the field may be null.")
    var nullable: Bool

    @Guide(description: "True if the field points at another table.")
    var isForeignKey: Bool

    @Guide(description: "What is happening to it.", .anyOf(GM_TOOL_ANYOF_ARCH_CHANGE_KIND))
    var changeKind: String

    @Guide(description: "Old field name, only when renaming.")
    var renamedFrom: String

    @Guide(description: "For the property. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dopePropertyRef: String

    init(
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

@Generable
struct GmAgentPersistenceChange: Sendable {
    @Guide(description: "Name of the class or table changing.")
    var className: String

    @Guide(description: "Repo-relative file it lives in.")
    var filePath: String

    @Guide(description: "Why this change, in one or two sentences.")
    var reasonBrief: String

    @Guide(description: "What is happening to it.", .anyOf(GM_TOOL_ANYOF_ARCH_CHANGE_KIND))
    var changeKind: String

    @Guide(description: "For the entity. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dopeRef: String

    @Guide(description: "The field-level changes inside this one.")
    var fields: [GmAgentPersistenceFieldChange]

    init(
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

@Generable
struct GmAgentRpirWritePersistenceChangesArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "architecture"))
    var summaryUuid: String

    @Guide(description: "All the database changes, in one go.")
    var changes: [GmAgentPersistenceChange]

    init(summaryUuid: String, changes: [GmAgentPersistenceChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

struct GmAgentRpirWriteArchitecturePersistenceChangesTool: GmAgentRpirTool {
    let name = "rpir_write_architecture_persistence_changes"
    let description = "Write down many database changes."

    init() {}

    func call(
        arguments _: GmAgentRpirWritePersistenceChangesArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "ARCH_PERSIST_ADD + ARCH_FIELD_ADD (looped)"
        )
    }
}

@Generable
struct GmAgentGeneralChange: Sendable {
    @Guide(description: "Repo-relative file this change owns.")
    var filePath: String

    @Guide(description: "Class or type being changed, if there is one.")
    var className: String

    @Guide(description: "Why this change, in one or two sentences.")
    var reasonBrief: String

    @Guide(description: "How worked-out it is.", .anyOf(GM_TOOL_ANYOF_CHANGE_DEPTH))
    var changeDepth: String

    @Guide(
        description: """
            The instruction whoever implements this will follow. Write it to them, \
            not about them.
            """
    )
    var changeCode: String

    init(
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

@Generable
struct GmAgentRpirWriteGeneralChangesArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "architecture"))
    var summaryUuid: String

    @Guide(description: "All the code changes, in one go.")
    var changes: [GmAgentGeneralChange]

    init(summaryUuid: String, changes: [GmAgentGeneralChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

struct GmAgentRpirWriteArchitectureGeneralChangesTool: GmAgentRpirTool {
    let name = "rpir_write_architecture_general_changes"
    let description = "Write down many code changes."

    init() {}

    func call(arguments _: GmAgentRpirWriteGeneralChangesArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GENERAL_ADD (looped)")
    }
}

@Generable
struct GmAgentRpirWriteFieldChangesArguments: Sendable {
    @Guide(description: "The database change row these fields belong to, by uuid.")
    var persistenceChangeUuid: String

    @Guide(description: "All the field changes for that row, in one go.")
    var fields: [GmAgentPersistenceFieldChange]

    init(persistenceChangeUuid: String, fields: [GmAgentPersistenceFieldChange]) {
        self.persistenceChangeUuid = persistenceChangeUuid
        self.fields = fields
    }
}

struct GmAgentRpirWriteArchitectureFieldChangesTool: GmAgentRpirTool {
    let name = "rpir_write_architecture_field_changes"
    let description = "Write down field-level changes under one database change."

    init() {}

    func call(arguments _: GmAgentRpirWriteFieldChangesArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_FIELD_ADD (looped)")
    }
}

@Generable
struct GmAgentRpirSummarizeArchitectureArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write", "architecture"))
    var summaryUuid: String

    @Guide(description: "Version of the summary you read.")
    var expectedVersion: Int

    @Guide(description: "The plan narrative, written over the expanded rows.")
    var body: String

    init(summaryUuid: String, expectedVersion: Int, body: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.body = body
    }
}

struct GmAgentRpirSummarizeArchitectureTool: GmAgentRpirTool {
    let name = "rpir_summarize_architecture"
    let description = "Write the plan's own summary."

    init() {}

    func call(arguments _: GmAgentRpirSummarizeArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_SUMMARIZE")
    }
}

@Generable
struct GmAgentRpirArchitectureGateArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "move", "architecture"))
    var summaryUuid: String

    @Guide(description: "Version of the summary you read.")
    var expectedVersion: Int

    init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

struct GmAgentRpirProposeArchitectureTool: GmAgentRpirTool {
    let name = "rpir_propose_architecture"
    let description = "Put the plan on the table."

    init() {}

    func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_PROPOSE")
    }
}

struct GmAgentRpirApproveArchitectureTool: GmAgentRpirTool {
    let name = "rpir_approve_architecture"
    let description = "The human said yes; lock the plan."

    init() {}

    func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_APPROVE")
    }
}

struct GmAgentRpirReviseArchitectureTool: GmAgentRpirTool {
    let name = "rpir_revise_architecture"
    let description = "Reopen the plan for changes."

    init() {}

    func call(arguments _: GmAgentRpirArchitectureGateArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_REVISE")
    }
}

@Generable
struct GmAgentRpirDecideArchitectureArguments: Sendable {
    @Guide(description: "Which plan won, by option uuid.")
    var optionUuid: String

    @Guide(description: "Version of the option you read.")
    var expectedVersion: Int

    @Guide(
        description: """
            Why this plan won, and what the rejected ones still contribute. A \
            decision with no reasoning gets argued again later.
            """
    )
    var rationale: String

    init(optionUuid: String, expectedVersion: Int, rationale: String) {
        self.optionUuid = optionUuid
        self.expectedVersion = expectedVersion
        self.rationale = rationale
    }
}

struct GmAgentRpirDecideArchitectureTool: GmAgentRpirTool {
    let name = "rpir_decide_architecture"
    let description = "Pick the winning plan."

    init() {}

    func call(arguments _: GmAgentRpirDecideArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_DECIDE")
    }
}

@Generable
struct GmAgentRpirGetArchitectureArguments: Sendable {
    @Guide(description: promptUuidGuide("'s architecture to read"))
    var promptUuid: String

    @Guide(description: "Read one option in full, by uuid. Leave empty for short versions of all.")
    var optionUuid: String

    @Guide(description: "Read one change in full, by uuid. Leave empty for short versions of all.")
    var changeUuid: String

    init(promptUuid: String, optionUuid: String = "", changeUuid: String = "") {
        self.promptUuid = promptUuid
        self.optionUuid = optionUuid
        self.changeUuid = changeUuid
    }
}

struct GmAgentRpirGetArchitectureTool: GmAgentRpirTool {
    let name = "rpir_get_architecture"
    let description = "Show me the plan and how much of it is built."

    init() {}

    func call(arguments _: GmAgentRpirGetArchitectureArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GET")
    }
}
