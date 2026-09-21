import Foundation

enum GmBridgeClaudePluginSettings {

    struct SubagentStatusLine: Codable, Equatable, Sendable {

        var type: String

        var command: String

        init(command: String) {
            self.type = "command"
            self.command = command
        }
    }

    struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { "settings.json" }

        var agent: String?

        var subagentStatusLine: SubagentStatusLine?

        init(
            agent: String? = nil,
            subagentStatusLine: SubagentStatusLine? = nil
        ) {
            self.agent = agent
            self.subagentStatusLine = subagentStatusLine
        }

        var isEmpty: Bool {
            agent == nil && subagentStatusLine == nil
        }
    }
}
