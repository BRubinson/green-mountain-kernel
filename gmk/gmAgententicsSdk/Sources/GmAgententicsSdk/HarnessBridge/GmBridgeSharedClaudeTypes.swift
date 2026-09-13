import Foundation
import ClaudeForFoundationModels

public typealias GmBridgeClaudeTypeEffort = ClaudeModel.Effort

public enum GmBridgeClaudeTypeModel: String, Equatable, Hashable, Sendable, CaseIterable {

    case opus

    case sonnet

    case haiku

    case fable

    case inherit
}

public enum GmBridgeClaudeTypeNativeTool: String, Equatable, Hashable, Sendable, CaseIterable {

    case bash = "Bash"

    case read = "Read"

    case write = "Write"

    case edit = "Edit"

    case grep = "Grep"

    case glob = "Glob"

    case webFetch = "WebFetch"

    case webSearch = "WebSearch"

    case skill = "Skill"

    case task = "Task"

    case todoWrite = "TodoWrite"

    case notebookEdit = "NotebookEdit"

    case askUserQuestion = "AskUserQuestion"
}

public enum GmBridgeClaudeTypeTool: Equatable, Hashable, Sendable {

    case native(GmBridgeClaudeTypeNativeTool)

    /// A bridged MCP tool, carried as the definition rather than its spelling.
    case mcp(GmBridgeMcpTool)

    /// A raw permission rule, e.g. `Bash(gm_hook:*)`. The escape hatch for
    /// anything the two typed cases above cannot name.
    case rule(String)

    public var frontmatterValue: String {
        switch self {
        case .native(let tool): return tool.rawValue
        case .mcp(let tool): return tool.qualifiedName
        case .rule(let rule): return rule
        }
    }

    public static let bash = Self.native(.bash)

    public static let read = Self.native(.read)

    public static let write = Self.native(.write)

    public static let edit = Self.native(.edit)

    public static let grep = Self.native(.grep)

    public static let glob = Self.native(.glob)

    public static let webFetch = Self.native(.webFetch)

    public static let webSearch = Self.native(.webSearch)

    public static let skill = Self.native(.skill)

    public static let task = Self.native(.task)

    public static let todoWrite = Self.native(.todoWrite)

    public static let notebookEdit = Self.native(.notebookEdit)

    public static let askUserQuestion = Self.native(.askUserQuestion)
}

public enum GmBridgeClaudeTypeShell: String, Equatable, Hashable, Sendable, CaseIterable {

    case bash

    case powershell
}

public enum GmBridgeClaudeTypeContext: String, Equatable, Hashable, Sendable, CaseIterable {

    case fork
}

public struct GmBridgeClaudeTypeHookHandler: Codable, Equatable, Sendable {

    public var type: String

    public var command: String

    public var timeout: Int?

    public var async: Bool?

    public var once: Bool?

    public init(
        command: String,
        timeout: Int? = nil,
        async: Bool? = nil,
        once: Bool? = nil
    ) {
        self.type = "command"
        self.command = command
        self.timeout = timeout
        self.async = async
        self.once = once
    }
}

public struct GmBridgeClaudeTypeHookGroup: Codable, Equatable, Sendable {

    public var matcher: String?

    public var hooks: [GmBridgeClaudeTypeHookHandler]

    public init(matcher: String? = nil, hooks: [GmBridgeClaudeTypeHookHandler]) {
        self.matcher = matcher
        self.hooks = hooks
    }
}

public enum GmBridgeClaudeTypePath {

    public static let pluginRoot = "${CLAUDE_PLUGIN_ROOT}"

    public static let projectDir = "${CLAUDE_PROJECT_DIR}"

    public static let pluginData = "${CLAUDE_PLUGIN_DATA}"
}
