import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenArchitectureOptionArguments: Sendable {
    @Guide(description: "Which prompt's architecture, by summary uuid.")
    public var summaryUuid: String

    @Guide(description: "Your methodology name. One plan per methodology.")
    public var agentName: String

    @Guide(description: "Your own agent id.")
    public var agentId: String

    @Guide(description: "Your whole proposal, written out.")
    public var body: String

    public init(summaryUuid: String, agentName: String, agentId: String = "", body: String) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.agentId = agentId
        self.body = body
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenArchitectureOptionTool: GmAgentCdeTool {
    public let name = "cde_open_architecture_option"
    public let description = "Start my own plan."

    public init() {}

    public func call(
        arguments: GmAgentCdeOpenArchitectureOptionArguments
    ) async throws -> String {
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

    @Guide(description: "What is happening to it.", .anyOf(["add", "modify", "rename", "delete"]))
    public var changeKind: String

    @Guide(description: "Old field name, only when renaming.")
    public var renamedFrom: String

    @Guide(description: "Dope dot-path CODE for the property, like domain.entity.property.")
    public var dopePropertyRef: String

    public init(
        fieldName: String, dataType: String, changeReason: String, changePurpose: String,
        nullable: Bool = false, isForeignKey: Bool = false, changeKind: String = "add",
        renamedFrom: String = "", dopePropertyRef: String = ""
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

    @Guide(description: "What is happening to it.", .anyOf(["add", "modify", "rename", "delete"]))
    public var changeKind: String

    @Guide(description: "Dope dot-path CODE for the entity, like domain.entity.")
    public var dopeRef: String

    @Guide(description: "The field-level changes inside this one.")
    public var fields: [GmAgentPersistenceFieldChange]

    public init(
        className: String, filePath: String, reasonBrief: String,
        changeKind: String = "modify", dopeRef: String = "",
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
public struct GmAgentCdeWritePersistenceChangesArguments: Sendable {
    @Guide(description: "Which architecture to write to, by summary uuid.")
    public var summaryUuid: String

    @Guide(description: "All the database changes, in one go.")
    public var changes: [GmAgentPersistenceChange]

    public init(summaryUuid: String, changes: [GmAgentPersistenceChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteArchitecturePersistenceChangesTool: GmAgentCdeTool {
    public let name = "cde_write_architecture_persistence_changes"
    public let description = "Write down many database changes."

    public init() {}

    public func call(
        arguments: GmAgentCdeWritePersistenceChangesArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "ARCH_PERSIST_ADD + ARCH_FIELD_ADD (looped)")
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

    @Guide(description: "How worked-out it is.", .anyOf(["pseudo", "draft", "actual"]))
    public var changeDepth: String

    @Guide(description: """
        The instruction whoever implements this will follow. Write it to them, \
        not about them.
        """)
    public var changeCode: String

    public init(
        filePath: String, className: String = "", reasonBrief: String,
        changeDepth: String = "actual", changeCode: String
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
public struct GmAgentCdeWriteGeneralChangesArguments: Sendable {
    @Guide(description: "Which architecture to write to, by summary uuid.")
    public var summaryUuid: String

    @Guide(description: "All the code changes, in one go.")
    public var changes: [GmAgentGeneralChange]

    public init(summaryUuid: String, changes: [GmAgentGeneralChange]) {
        self.summaryUuid = summaryUuid
        self.changes = changes
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteArchitectureGeneralChangesTool: GmAgentCdeTool {
    public let name = "cde_write_architecture_general_changes"
    public let description = "Write down many code changes."

    public init() {}

    public func call(arguments: GmAgentCdeWriteGeneralChangesArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GENERAL_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeDecideArchitectureArguments: Sendable {
    @Guide(description: "Which plan won, by option uuid.")
    public var optionUuid: String

    @Guide(description: "Version of the option you read.")
    public var expectedVersion: Int

    @Guide(description: """
        Why this plan won, and what the rejected ones still contribute. A \
        decision with no reasoning gets argued again later.
        """)
    public var rationale: String

    public init(optionUuid: String, expectedVersion: Int, rationale: String) {
        self.optionUuid = optionUuid
        self.expectedVersion = expectedVersion
        self.rationale = rationale
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentCdeDecideArchitectureTool: GmAgentCdeTool {
    public let name = "cde_decide_architecture"
    public let description = "Pick the winning plan."

    public init() {}

    public func call(arguments: GmAgentCdeDecideArchitectureArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_DECIDE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeGetArchitectureArguments: Sendable {
    @Guide(description: "Which prompt's architecture to read, by uuid.")
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
public struct GmAgentCdeGetArchitectureTool: GmAgentCdeTool {
    public let name = "cde_get_architecture"
    public let description = "Show me the plan and how much of it is built."

    public init() {}

    public func call(arguments: GmAgentCdeGetArchitectureArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "ARCH_GET")
    }
}
