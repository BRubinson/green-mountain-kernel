import Foundation

public enum GmBridgeCommand {

    public typealias Model = GmBridgeClaudeTypeModel

    public typealias Effort = GmBridgeClaudeTypeEffort

    public typealias Native = GmBridgeClaudeTypeNativeTool

    public typealias Tool = GmBridgeClaudeTypeTool

    public typealias Shell = GmBridgeClaudeTypeShell

    public typealias Context = GmBridgeClaudeTypeContext

    public typealias HookHandler = GmBridgeClaudeTypeHookHandler

    public typealias HookGroup = GmBridgeClaudeTypeHookGroup

    public struct File: Equatable, Sendable, GmBridgeFile {

        public var name: String

        public var description: String?

        public var whenToUse: String?

        public var argumentHint: String?

        public var arguments: [String]

        public var disableModelInvocation: Bool?

        public var userInvocable: Bool?

        public var allowedTools: [Tool]

        public var disallowedTools: [Tool]

        public var model: Model?

        public var effort: Effort?

        public var context: Context?

        public var agent: String?

        public var background: Bool?

        public var hooks: [String: [HookGroup]]

        public var shell: Shell?

        public var metadata: [String: String]

        public var license: String?

        public var compatibility: String?

        public var body: String

        public init(
            name: String,
            description: String? = nil,
            whenToUse: String? = nil,
            argumentHint: String? = nil,
            arguments: [String] = [],
            disableModelInvocation: Bool? = nil,
            userInvocable: Bool? = nil,
            allowedTools: [Tool] = [],
            disallowedTools: [Tool] = [],
            model: Model? = nil,
            effort: Effort? = nil,
            context: Context? = nil,
            agent: String? = nil,
            background: Bool? = nil,
            hooks: [String: [HookGroup]] = [:],
            shell: Shell? = nil,
            metadata: [String: String] = [:],
            license: String? = nil,
            compatibility: String? = nil,
            body: String = ""
        ) {
            self.name = name
            self.description = description
            self.whenToUse = whenToUse
            self.argumentHint = argumentHint
            self.arguments = arguments
            self.disableModelInvocation = disableModelInvocation
            self.userInvocable = userInvocable
            self.allowedTools = allowedTools
            self.disallowedTools = disallowedTools
            self.model = model
            self.effort = effort
            self.context = context
            self.agent = agent
            self.background = background
            self.hooks = hooks
            self.shell = shell
            self.metadata = metadata
            self.license = license
            self.compatibility = compatibility
            self.body = body
        }

        public var relativePath: String {
            "commands/\(name).md"
        }

        public var invocation: String {
            "/\(name)"
        }

        public var isEmpty: Bool {
            body.isEmpty
        }

        public func contents() throws -> String? {
            guard !isEmpty else { return nil }

            var lines = ["---"]
            if let description {
                lines.append("description: \(GmBridgeYaml.scalar(description))")
            }
            if let whenToUse {
                lines.append("when_to_use: \(GmBridgeYaml.scalar(whenToUse))")
            }
            if let argumentHint {
                lines.append("argument-hint: \(GmBridgeYaml.scalar(argumentHint))")
            }
            if !arguments.isEmpty {
                lines.append("arguments: \(GmBridgeYaml.list(arguments, separator: " "))")
            }
            if let disableModelInvocation {
                lines.append(
                    "disable-model-invocation: \(GmBridgeYaml.bool(disableModelInvocation))"
                )
            }
            if let userInvocable {
                lines.append("user-invocable: \(GmBridgeYaml.bool(userInvocable))")
            }
            if !allowedTools.isEmpty {
                lines.append("allowed-tools: \(GmBridgeYaml.tools(allowedTools))")
            }
            if !disallowedTools.isEmpty {
                lines.append("disallowed-tools: \(GmBridgeYaml.tools(disallowedTools))")
            }
            if let model {
                lines.append("model: \(model.rawValue)")
            }
            if let effort {
                lines.append("effort: \(effort.rawValue)")
            }
            if let context {
                lines.append("context: \(context.rawValue)")
            }
            if let agent {
                lines.append("agent: \(GmBridgeYaml.scalar(agent))")
            }
            if let background {
                lines.append("background: \(GmBridgeYaml.bool(background))")
            }
            if !hooks.isEmpty {
                lines.append("hooks: \(try GmBridgeYaml.inline(hooks))")
            }
            if let shell {
                lines.append("shell: \(shell.rawValue)")
            }
            if !metadata.isEmpty {
                lines.append("metadata: \(try GmBridgeYaml.inline(metadata))")
            }
            if let license {
                lines.append("license: \(GmBridgeYaml.scalar(license))")
            }
            if let compatibility {
                lines.append("compatibility: \(GmBridgeYaml.scalar(compatibility))")
            }
            lines.append("---")

            let content = body.hasSuffix("\n") ? body : body + "\n"
            return lines.joined(separator: "\n") + "\n\n" + content
        }

        public static let compatibilityLimit = 500
    }
}
