import Foundation

/// The `effort` frontmatter value: how much reasoning budget a command, skill or agent asks for.
enum GmBridgeClaudeTypeEffort: String, Equatable, Hashable, Sendable, CaseIterable {
    case low, medium, high, xhigh, max
}

enum GmBridgeClaudeTypeModel: String, Equatable, Hashable, Sendable, CaseIterable {

    case opus

    case sonnet

    case haiku

    case fable

    case inherit
}

enum GmBridgeClaudeTypeNativeTool: String, Equatable, Hashable, Sendable, CaseIterable {

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

enum GmBridgeClaudeTypeTool: Equatable, Hashable, Sendable {

    case native(GmBridgeClaudeTypeNativeTool)

    /// A bridged MCP tool, carried as the definition rather than its spelling.
    case mcp(GmBridgeMcpTool)

    /// A raw permission rule, e.g. `Bash(git:*)`. The escape hatch for
    /// anything the two typed cases above cannot name.
    case rule(String)

    var frontmatterValue: String {
        switch self {
        case .native(let tool): return tool.rawValue
        case .mcp(let tool): return tool.qualifiedName
        case .rule(let rule): return rule
        }
    }

    static let bash = Self.native(.bash)

    static let read = Self.native(.read)

    static let write = Self.native(.write)

    static let edit = Self.native(.edit)

    static let grep = Self.native(.grep)

    static let glob = Self.native(.glob)

    static let webFetch = Self.native(.webFetch)

    static let webSearch = Self.native(.webSearch)

    static let skill = Self.native(.skill)

    static let task = Self.native(.task)

    static let todoWrite = Self.native(.todoWrite)

    static let notebookEdit = Self.native(.notebookEdit)

    static let askUserQuestion = Self.native(.askUserQuestion)
}

enum GmBridgeClaudeTypeShell: String, Equatable, Hashable, Sendable, CaseIterable {

    case bash

    case powershell
}

enum GmBridgeClaudeTypeContext: String, Equatable, Hashable, Sendable, CaseIterable {

    case fork
}

struct GmBridgeClaudeTypeHookHandler: Codable, Equatable, Sendable {

    var type: String

    var command: String

    var timeout: Int?

    var async: Bool?

    var once: Bool?

    init(
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

struct GmBridgeClaudeTypeHookGroup: Codable, Equatable, Sendable {

    var matcher: String?

    var hooks: [GmBridgeClaudeTypeHookHandler]

    init(matcher: String? = nil, hooks: [GmBridgeClaudeTypeHookHandler]) {
        self.matcher = matcher
        self.hooks = hooks
    }
}

enum GmBridgeClaudeTypePath {

    static let pluginRoot = "${CLAUDE_PLUGIN_ROOT}"

    static let projectDir = "${CLAUDE_PROJECT_DIR}"

    static let pluginData = "${CLAUDE_PLUGIN_DATA}"
}
