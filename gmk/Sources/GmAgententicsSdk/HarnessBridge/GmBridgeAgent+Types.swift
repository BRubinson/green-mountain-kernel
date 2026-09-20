import ClaudeForFoundationModels
import Foundation

enum GmBridgeAgent {

    typealias Model = GmBridgeClaudeTypeModel

    typealias Effort = GmBridgeClaudeTypeEffort

    typealias Native = GmBridgeClaudeTypeNativeTool

    enum Memory: String, Equatable, Hashable, Sendable, CaseIterable {

        case user

        case project

        case local
    }

    enum Isolation: String, Equatable, Hashable, Sendable, CaseIterable {

        case worktree
    }

    struct File: Equatable, Sendable, GmBridgeFile {

        var name: String

        var description: String

        var model: Model?

        var effort: Effort?

        var maxTurns: Int?

        var nativeTools: [Native]

        var mcpTools: [GmBridgeMcpTool]

        var disallowedTools: [Native]

        var skills: [String]

        var memory: Memory?

        var background: Bool?

        var isolation: Isolation?

        var prompt: String

        init(
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

        var relativePath: String {
            "agents/\(name).md"
        }

        var toolNames: [String] {
            nativeTools.map(\.rawValue) + mcpTools.map(\.qualifiedName)
        }

        func contents() -> String? {
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
