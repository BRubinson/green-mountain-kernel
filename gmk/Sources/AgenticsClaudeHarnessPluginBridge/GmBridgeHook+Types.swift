import Foundation

protocol GmBridgeHookEvent: RawRepresentable, CaseIterable, Sendable
where RawValue == String {

    var description: String { get }

    var supportsMatcher: Bool { get }

    var canBlock: Bool { get }
}

extension GmBridgeHookEvent {

    var code: String { rawValue }

    var supportsMatcher: Bool { true }

    var canBlock: Bool { false }
}

enum GmBridgeHook {

    enum Lifecycle: String, GmBridgeHookEvent {

        case sessionStart = "SessionStart"

        case setup = "Setup"

        case sessionEnd = "SessionEnd"

        var description: String {
            switch self {
            case .sessionStart:
                return "A session begins or resumes."
            case .setup:
                return "Claude Code starts with --init-only, or --init/--maintenance in -p mode."
            case .sessionEnd:
                return "A session terminates."
            }
        }
    }

    enum Turn: String, GmBridgeHookEvent {

        case userPromptSubmit = "UserPromptSubmit"

        case userPromptExpansion = "UserPromptExpansion"

        case messageDisplay = "MessageDisplay"

        case stop = "Stop"

        case stopFailure = "StopFailure"

        var supportsMatcher: Bool {
            switch self {
            case .userPromptSubmit, .messageDisplay, .stop: return false
            case .userPromptExpansion, .stopFailure: return true
            }
        }

        var canBlock: Bool {
            switch self {
            case .userPromptSubmit, .userPromptExpansion, .stop: return true
            case .messageDisplay, .stopFailure: return false
            }
        }

        var description: String {
            switch self {
            case .userPromptSubmit:
                return "A prompt is submitted, before Claude processes it."
            case .userPromptExpansion:
                return "A user-typed command expands into a prompt, before it reaches Claude."
            case .messageDisplay:
                return "Assistant message text is displayed. Display-only; the transcript keeps the original."
            case .stop:
                return "Claude finishes responding."
            case .stopFailure:
                return "The turn ends due to an API error. Output and exit code are ignored."
            }
        }
    }

    enum Tool: String, GmBridgeHookEvent {

        case preToolUse = "PreToolUse"

        case postToolUse = "PostToolUse"

        case postToolUseFailure = "PostToolUseFailure"

        case postToolBatch = "PostToolBatch"

        var supportsMatcher: Bool {
            self != .postToolBatch
        }

        var canBlock: Bool {
            switch self {
            case .preToolUse, .postToolBatch: return true
            case .postToolUse, .postToolUseFailure: return false
            }
        }

        var description: String {
            switch self {
            case .preToolUse:
                return "Before a tool call executes."
            case .postToolUse:
                return "After a tool call succeeds."
            case .postToolUseFailure:
                return "After a tool call fails."
            case .postToolBatch:
                return "After a full batch of parallel tool calls resolves, before the next model call."
            }
        }
    }

    enum Permission: String, GmBridgeHookEvent {

        case permissionRequest = "PermissionRequest"

        case permissionDenied = "PermissionDenied"

        var description: String {
            switch self {
            case .permissionRequest:
                return "A tool call needs a permission decision."
            case .permissionDenied:
                return "Auto mode denies a tool call."
            }
        }
    }

    enum Agent: String, GmBridgeHookEvent {

        case subagentStart = "SubagentStart"

        case subagentStop = "SubagentStop"

        case teammateIdle = "TeammateIdle"

        var supportsMatcher: Bool {
            self != .teammateIdle
        }

        var canBlock: Bool {
            self != .subagentStart
        }

        var description: String {
            switch self {
            case .subagentStart:
                return "A subagent is spawned."
            case .subagentStop:
                return "A subagent finishes."
            case .teammateIdle:
                return "An agent team teammate is about to go idle."
            }
        }
    }

    enum Task: String, GmBridgeHookEvent {

        case taskCreated = "TaskCreated"

        case taskCompleted = "TaskCompleted"

        var supportsMatcher: Bool { false }

        var canBlock: Bool { true }

        var description: String {
            switch self {
            case .taskCreated:
                return "A task is being created via TaskCreate."
            case .taskCompleted:
                return "A task is being marked as completed."
            }
        }
    }

    enum Compaction: String, GmBridgeHookEvent {

        case preCompact = "PreCompact"

        case postCompact = "PostCompact"

        var canBlock: Bool {
            self == .preCompact
        }

        var description: String {
            switch self {
            case .preCompact:
                return "Before context compaction."
            case .postCompact:
                return "After context compaction completes."
            }
        }
    }

    enum Model: String, GmBridgeHookEvent {

        case preModelSwitch = "PreModelSwitch"

        case postModelSwitch = "PostModelSwitch"

        var canBlock: Bool {
            self == .preModelSwitch
        }

        var description: String {
            switch self {
            case .preModelSwitch:
                return "Before a requested model switch is applied."
            case .postModelSwitch:
                return "After the session's model changes."
            }
        }
    }

    enum Workspace: String, GmBridgeHookEvent {

        case instructionsLoaded = "InstructionsLoaded"

        case configChange = "ConfigChange"

        case cwdChanged = "CwdChanged"

        case directoryAdded = "DirectoryAdded"

        case fileChanged = "FileChanged"

        var supportsMatcher: Bool {
            self != .cwdChanged
        }

        var canBlock: Bool {
            self == .configChange
        }

        var description: String {
            switch self {
            case .instructionsLoaded:
                return "A CLAUDE.md or .claude/rules/*.md file is loaded into context."
            case .configChange:
                return "A configuration file changes during a session."
            case .cwdChanged:
                return "The working directory changes."
            case .directoryAdded:
                return "A working directory is added mid-session."
            case .fileChanged:
                return "A watched file changes on disk. The matcher names the filenames to watch."
            }
        }
    }

    enum Worktree: String, GmBridgeHookEvent {

        case worktreeCreate = "WorktreeCreate"

        case worktreeRemove = "WorktreeRemove"

        var supportsMatcher: Bool { false }

        var canBlock: Bool { true }

        var description: String {
            switch self {
            case .worktreeCreate:
                return "A worktree is being created. Replaces default git behavior."
            case .worktreeRemove:
                return "A worktree is being removed."
            }
        }
    }

    enum Elicitation: String, GmBridgeHookEvent {

        case elicitation = "Elicitation"

        case elicitationResult = "ElicitationResult"

        var canBlock: Bool { true }

        var description: String {
            switch self {
            case .elicitation:
                return "An MCP server requests user input during a tool call."
            case .elicitationResult:
                return "After a user responds to an MCP elicitation, before the response is sent back."
            }
        }
    }

    enum Notification: String, GmBridgeHookEvent {

        case notification = "Notification"

        var description: String {
            "Claude Code sends a notification."
        }
    }

    enum HandlerType: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case command

        case http

        case mcpTool = "mcp_tool"

        case prompt

        case agent
    }

    struct Handler: Codable, Equatable, Sendable {

        var type: HandlerType

        var command: String?

        var args: [String]?

        var url: String?

        var server: String?

        var tool: String?

        var prompt: String?

        var agent: String?

        var timeout: Int?

        var async: Bool?

        init(
            type: HandlerType,
            command: String? = nil,
            args: [String]? = nil,
            url: String? = nil,
            server: String? = nil,
            tool: String? = nil,
            prompt: String? = nil,
            agent: String? = nil,
            timeout: Int? = nil,
            async: Bool? = nil
        ) {
            self.type = type
            self.command = command
            self.args = args
            self.url = url
            self.server = server
            self.tool = tool
            self.prompt = prompt
            self.agent = agent
            self.timeout = timeout
            self.async = async
        }

        init(
            command: String,
            args: [String]? = nil,
            timeout: Int? = nil,
            async: Bool? = nil
        ) {
            self.init(
                type: .command,
                command: command,
                args: args,
                timeout: timeout,
                async: async
            )
        }

        static func http(
            url: String,
            timeout: Int? = nil,
            async: Bool? = nil
        ) -> Handler {
            Handler(type: .http, url: url, timeout: timeout, async: async)
        }

        static func mcpTool(
            server: String,
            tool: String,
            timeout: Int? = nil
        ) -> Handler {
            Handler(type: .mcpTool, server: server, tool: tool, timeout: timeout)
        }

        static func prompt(_ text: String, timeout: Int? = nil) -> Handler {
            Handler(type: .prompt, prompt: text, timeout: timeout)
        }

        static func agent(_ name: String, timeout: Int? = nil) -> Handler {
            Handler(type: .agent, agent: name, timeout: timeout)
        }
    }

    struct MatcherGroup: Codable, Equatable, Sendable {

        var matcher: String?

        var hooks: [Handler]

        init(matcher: String? = nil, hooks: [Handler]) {
            self.matcher = matcher
            self.hooks = hooks
        }
    }

    struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { "hooks/hooks.json" }

        var description: String?

        var hooks: [String: [MatcherGroup]]

        init(description: String? = nil, hooks: [String: [MatcherGroup]]) {
            self.description = description
            self.hooks = hooks
        }
    }
}
