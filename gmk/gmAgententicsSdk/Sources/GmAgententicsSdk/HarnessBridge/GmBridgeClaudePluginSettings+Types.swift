import Foundation

public enum GmBridgeClaudePluginSettings {

    public struct SubagentStatusLine: Codable, Equatable, Sendable {

        public var type: String

        public var command: String

        public init(command: String) {
            self.type = "command"
            self.command = command
        }
    }

    public struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { "settings.json" }

        public var agent: String?

        public var subagentStatusLine: SubagentStatusLine?

        public init(
            agent: String? = nil,
            subagentStatusLine: SubagentStatusLine? = nil
        ) {
            self.agent = agent
            self.subagentStatusLine = subagentStatusLine
        }

        public var isEmpty: Bool {
            agent == nil && subagentStatusLine == nil
        }
    }
}
