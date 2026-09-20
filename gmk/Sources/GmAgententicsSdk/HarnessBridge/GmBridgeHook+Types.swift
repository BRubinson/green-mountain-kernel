import Foundation

public protocol GmBridgeHookEvent: RawRepresentable, CaseIterable, Sendable
where RawValue == String {

    var description: String { get }

    var supportsMatcher: Bool { get }

    var canBlock: Bool { get }
}

extension GmBridgeHookEvent {

    public var code: String { rawValue }

    public var supportsMatcher: Bool { true }

    public var canBlock: Bool { false }
}

public enum GmBridgeHook {

    public enum Lifecycle: String, GmBridgeHookEvent {

        case sessionStart = "SessionStart"

        case setup = "Setup"

        case sessionEnd = "SessionEnd"

        public var description: String {
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

    public enum Turn: String, GmBridgeHookEvent {

        case userPromptSubmit = "UserPromptSubmit"

        case userPromptExpansion = "UserPromptExpansion"

        case messageDisplay = "MessageDisplay"

        case stop = "Stop"

        case stopFailure = "StopFailure"

        public var supportsMatcher: Bool {
            switch self {
            case .userPromptSubmit, .messageDisplay, .stop: return false
            case .userPromptExpansion, .stopFailure: return true
            }
        }

        public var canBlock: Bool {
            switch self {
            case .userPromptSubmit, .userPromptExpansion, .stop: return true
            case .messageDisplay, .stopFailure: return false
            }
        }

        public var description: String {
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

    public enum Tool: String, GmBridgeHookEvent {

        case preToolUse = "PreToolUse"

        case postToolUse = "PostToolUse"

        case postToolUseFailure = "PostToolUseFailure"

        case postToolBatch = "PostToolBatch"

        public var supportsMatcher: Bool {
            self != .postToolBatch
        }

        public var canBlock: Bool {
            switch self {
            case .preToolUse, .postToolBatch: return true
            case .postToolUse, .postToolUseFailure: return false
            }
        }

        public var description: String {
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

    public enum Permission: String, GmBridgeHookEvent {

        case permissionRequest = "PermissionRequest"

        case permissionDenied = "PermissionDenied"

        public var description: String {
            switch self {
            case .permissionRequest:
                return "A tool call needs a permission decision."
            case .permissionDenied:
                return "Auto mode denies a tool call."
            }
        }
    }

    public enum Agent: String, GmBridgeHookEvent {

        case subagentStart = "SubagentStart"

        case subagentStop = "SubagentStop"

        case teammateIdle = "TeammateIdle"

        public var supportsMatcher: Bool {
            self != .teammateIdle
        }

        public var canBlock: Bool {
            self != .subagentStart
        }

        public var description: String {
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

    public enum Task: String, GmBridgeHookEvent {

        case taskCreated = "TaskCreated"

        case taskCompleted = "TaskCompleted"

        public var supportsMatcher: Bool { false }

        public var canBlock: Bool { true }

        public var description: String {
            switch self {
            case .taskCreated:
                return "A task is being created via TaskCreate."
            case .taskCompleted:
                return "A task is being marked as completed."
            }
        }
    }

    public enum Compaction: String, GmBridgeHookEvent {

        case preCompact = "PreCompact"

        case postCompact = "PostCompact"

        public var canBlock: Bool {
            self == .preCompact
        }

        public var description: String {
            switch self {
            case .preCompact:
                return "Before context compaction."
            case .postCompact:
                return "After context compaction completes."
            }
        }
    }

    public enum Model: String, GmBridgeHookEvent {

        case preModelSwitch = "PreModelSwitch"

        case postModelSwitch = "PostModelSwitch"

        public var canBlock: Bool {
            self == .preModelSwitch
        }

        public var description: String {
            switch self {
            case .preModelSwitch:
                return "Before a requested model switch is applied."
            case .postModelSwitch:
                return "After the session's model changes."
            }
        }
    }

    public enum Workspace: String, GmBridgeHookEvent {

        case instructionsLoaded = "InstructionsLoaded"

        case configChange = "ConfigChange"

        case cwdChanged = "CwdChanged"

        case directoryAdded = "DirectoryAdded"

        case fileChanged = "FileChanged"

        public var supportsMatcher: Bool {
            self != .cwdChanged
        }

        public var canBlock: Bool {
            self == .configChange
        }

        public var description: String {
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

    public enum Worktree: String, GmBridgeHookEvent {

        case worktreeCreate = "WorktreeCreate"

        case worktreeRemove = "WorktreeRemove"

        public var supportsMatcher: Bool { false }

        public var canBlock: Bool { true }

        public var description: String {
            switch self {
            case .worktreeCreate:
                return "A worktree is being created. Replaces default git behavior."
            case .worktreeRemove:
                return "A worktree is being removed."
            }
        }
    }

    public enum Elicitation: String, GmBridgeHookEvent {

        case elicitation = "Elicitation"

        case elicitationResult = "ElicitationResult"

        public var canBlock: Bool { true }

        public var description: String {
            switch self {
            case .elicitation:
                return "An MCP server requests user input during a tool call."
            case .elicitationResult:
                return "After a user responds to an MCP elicitation, before the response is sent back."
            }
        }
    }

    public enum Notification: String, GmBridgeHookEvent {

        case notification = "Notification"

        public var description: String {
            "Claude Code sends a notification."
        }
    }

    public enum HandlerType: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case command

        case http

        case mcpTool = "mcp_tool"

        case prompt

        case agent
    }

    public struct Handler: Codable, Equatable, Sendable {

        public var type: HandlerType

        public var command: String?

        public var args: [String]?

        public var url: String?

        public var server: String?

        public var tool: String?

        public var prompt: String?

        public var agent: String?

        public var timeout: Int?

        public var async: Bool?

        public init(
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

        public init(
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

        public static func http(
            url: String,
            timeout: Int? = nil,
            async: Bool? = nil
        ) -> Handler {
            Handler(type: .http, url: url, timeout: timeout, async: async)
        }

        public static func mcpTool(
            server: String,
            tool: String,
            timeout: Int? = nil
        ) -> Handler {
            Handler(type: .mcpTool, server: server, tool: tool, timeout: timeout)
        }

        public static func prompt(_ text: String, timeout: Int? = nil) -> Handler {
            Handler(type: .prompt, prompt: text, timeout: timeout)
        }

        public static func agent(_ name: String, timeout: Int? = nil) -> Handler {
            Handler(type: .agent, agent: name, timeout: timeout)
        }
    }

    public struct MatcherGroup: Codable, Equatable, Sendable {

        public var matcher: String?

        public var hooks: [Handler]

        public init(matcher: String? = nil, hooks: [Handler]) {
            self.matcher = matcher
            self.hooks = hooks
        }
    }

    public struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { "hooks/hooks.json" }

        public var description: String?

        public var hooks: [String: [MatcherGroup]]

        public init(description: String? = nil, hooks: [String: [MatcherGroup]]) {
            self.description = description
            self.hooks = hooks
        }
    }
}
