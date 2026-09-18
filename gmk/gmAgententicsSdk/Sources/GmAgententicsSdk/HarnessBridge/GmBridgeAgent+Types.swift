import Foundation

public enum GmBridgeAgent {

    public typealias Model = GmBridgeClaudeTypeModel

    public typealias Effort = GmBridgeClaudeTypeEffort

    public typealias Native = GmBridgeClaudeTypeNativeTool

    public enum Memory: String, Equatable, Hashable, Sendable, CaseIterable {

        case user

        case project

        case local
    }

    public enum Isolation: String, Equatable, Hashable, Sendable, CaseIterable {

        case worktree
    }

    public struct File: Equatable, Sendable, GmBridgeFile {

        public var name: String

        public var description: String

        public var model: Model?

        public var effort: Effort?

        public var maxTurns: Int?

        public var nativeTools: [Native]

        public var mcpTools: [GmBridgeMcpTool]

        public var disallowedTools: [Native]

        public var skills: [String]

        public var memory: Memory?

        public var background: Bool?

        public var isolation: Isolation?

        public var prompt: String

        public init(
            name: String,
            description: String,
            model: Model? = nil,
            effort: Effort? = nil,
            maxTurns: Int? = nil,
            nativeTools: [Native] = [],
            mcpTools: [GmBridgeMcpTool] = [],
            disallowedTools: [Native] = [],
            skills: [String] = [],
            memory: Memory? = nil,
            background: Bool? = nil,
            isolation: Isolation? = nil,
            prompt: String
        ) {
            self.name = name
            self.description = description
            self.model = model
            self.effort = effort
            self.maxTurns = maxTurns
            self.nativeTools = nativeTools
            self.mcpTools = mcpTools
            self.disallowedTools = disallowedTools
            self.skills = skills
            self.memory = memory
            self.background = background
            self.isolation = isolation
            self.prompt = prompt
        }

        public var relativePath: String {
            "agents/\(name).md"
        }

        public var toolNames: [String] {
            nativeTools.map(\.rawValue) + mcpTools.map(\.qualifiedName)
        }

        public func contents() -> String? {
            var lines = ["---"]
            lines.append("name: \(GmBridgeYaml.scalar(name))")
            lines.append("description: \(GmBridgeYaml.scalar(description))")
            if let model {
                lines.append("model: \(model.rawValue)")
            }
            if let effort {
                lines.append("effort: \(effort.rawValue)")
            }
            if let maxTurns {
                lines.append("maxTurns: \(maxTurns)")
            }
            if !toolNames.isEmpty {
                lines.append("tools: \(GmBridgeYaml.list(toolNames))")
            }
            if !disallowedTools.isEmpty {
                lines.append(
                    "disallowedTools: \(GmBridgeYaml.list(disallowedTools.map(\.rawValue)))"
                )
            }
            if !skills.isEmpty {
                lines.append("skills: \(GmBridgeYaml.list(skills))")
            }
            if let memory {
                lines.append("memory: \(memory.rawValue)")
            }
            if let background {
                lines.append("background: \(GmBridgeYaml.bool(background))")
            }
            if let isolation {
                lines.append("isolation: \(isolation.rawValue)")
            }
            lines.append("---")

            let body = prompt.hasSuffix("\n") ? prompt : prompt + "\n"
            return lines.joined(separator: "\n") + "\n\n" + body
        }
    }
}
