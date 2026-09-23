import Foundation

enum GmBridgeSkill {

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

        var paths: [String]

        var shell: Shell?

        var metadata: [String: String]

        var license: String?

        var compatibility: String?

        var body: String

        /// Initializes a skill manifest.
        ///
        /// - Parameters:
        ///   - name: The skill name.
        ///   - description: Short description of the skill.
        ///   - whenToUse: When to invoke the skill.
        ///   - argumentHint: Hint for argument syntax.
        ///   - arguments: Array of argument names.
        ///   - disableModelInvocation: Whether to disable model invocation.
        ///   - userInvocable: Whether the user can invoke it.
        ///   - allowedTools: Tools allowed by this skill.
        ///   - disallowedTools: Tools disallowed by this skill.
        ///   - model: The model to use.
        ///   - effort: The effort level.
        ///   - context: The execution context.
        ///   - agent: The agent type.
        ///   - background: Whether to run in background.
        ///   - hooks: Hook definitions keyed by hook name.
        ///   - paths: Filesystem paths related to the skill.
        ///   - shell: The shell to use.
        ///   - metadata: Additional metadata as key-value pairs.
        ///   - license: License string.
        ///   - compatibility: Compatibility information.
        ///   - body: The skill content.
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
            paths: [String] = [],
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
            self.paths = paths
            self.shell = shell
            self.metadata = metadata
            self.license = license
            self.compatibility = compatibility
            self.body = body
        }

        var relativePath: String {
            "skills/\(name)/SKILL.md"
        }

        var isEmpty: Bool {
            body.isEmpty
        }

        /// Generates the skill file contents with manifest and body.
        ///
        /// - Returns: The formatted skill file content, or `nil` if the skill is empty.
        /// - Throws: Any YAML serialization error.
        func contents() throws -> String? {
            guard !isEmpty else { return nil }

            var lines = ["---"]
            lines.append("name: \(GmBridgeYaml.scalar(name))")
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
                lines.append("arguments: \(arguments.joined(separator: " "))")
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
            if !paths.isEmpty {
                lines.append("paths: \(paths.joined(separator: ", "))")
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
