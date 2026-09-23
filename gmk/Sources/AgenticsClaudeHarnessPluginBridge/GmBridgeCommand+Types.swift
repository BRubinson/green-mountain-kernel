import Foundation

enum GmBridgeCommand {

    typealias Model = GmBridgeClaudeTypeModel

    typealias Effort = GmBridgeClaudeTypeEffort

    typealias Native = GmBridgeClaudeTypeNativeTool

    typealias Tool = GmBridgeClaudeTypeTool

    typealias Shell = GmBridgeClaudeTypeShell

    typealias Context = GmBridgeClaudeTypeContext

    typealias HookHandler = GmBridgeClaudeTypeHookHandler

    typealias HookGroup = GmBridgeClaudeTypeHookGroup

    struct File: Equatable, Sendable, GmBridgeFile {

        var name: String

        var description: String?

        var whenToUse: String?

        var argumentHint: String?

        var arguments: [String]

        var disableModelInvocation: Bool?

        var userInvocable: Bool?

        var allowedTools: [Tool]

        var disallowedTools: [Tool]

        var model: Model?

        var effort: Effort?

        var context: Context?

        var agent: String?

        var background: Bool?

        var hooks: [String: [HookGroup]]

        var shell: Shell?

        var metadata: [String: String]

        var license: String?

        var compatibility: String?

        var body: String

        /// Creates a new command definition.
        /// - Parameters:
        ///   - name: The command name.
        ///   - description: A brief description of what the command does.
        ///   - whenToUse: Guidance on when to invoke this command.
        ///   - argumentHint: A short hint about expected arguments.
        ///   - arguments: List of argument names.
        ///   - disableModelInvocation: Whether to disable model invocation.
        ///   - userInvocable: Whether users can invoke this command.
        ///   - allowedTools: Tools this command is allowed to use.
        ///   - disallowedTools: Tools this command cannot use.
        ///   - model: The model to use for invocation.
        ///   - effort: The reasoning effort level.
        ///   - context: The execution context.
        ///   - agent: The agent type if applicable.
        ///   - background: Whether to run in the background.
        ///   - hooks: Hook configurations keyed by hook name.
        ///   - shell: The shell to execute in.
        ///   - metadata: Custom metadata key-value pairs.
        ///   - license: The license type.
        ///   - compatibility: Version compatibility information.
        ///   - body: The command body or description text.
        init(
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

        var relativePath: String {
            "commands/\(name).md"
        }

        var invocation: String {
            "/\(name)"
        }

        var isEmpty: Bool {
            body.isEmpty
        }

        /// Renders the command definition as YAML frontmatter plus body.
        /// - Returns: The rendered command file, or nil if the body is empty.
        /// - Throws: A formatting error if YAML rendering fails.
        func contents() throws -> String? {
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

        static let compatibilityLimit = 500
    }
}
