import Foundation

public enum GmBridgeMcp {

    public enum Transport: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case stdio

        case http

        case sse

        case ws
    }

    public struct Server: Codable, Equatable, Hashable, Sendable {

        public var type: Transport?

        public var command: String?

        public var args: [String]?

        public var env: [String: String]?

        public var url: String?

        public var headers: [String: String]?

        public var alwaysLoad: Bool?

        public init(
            type: Transport? = nil,
            command: String? = nil,
            args: [String]? = nil,
            env: [String: String]? = nil,
            url: String? = nil,
            headers: [String: String]? = nil,
            alwaysLoad: Bool? = nil
        ) {
            self.type = type
            self.command = command
            self.args = args
            self.env = env
            self.url = url
            self.headers = headers
            self.alwaysLoad = alwaysLoad
        }

        public static func stdio(
            command: String,
            args: [String]? = nil,
            env: [String: String]? = nil,
            alwaysLoad: Bool? = nil
        ) -> Server {
            Server(command: command, args: args, env: env, alwaysLoad: alwaysLoad)
        }
    }

    public struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { ".mcp.json" }

        public var mcpServers: [String: Server]

        public init(mcpServers: [String: Server]) {
            self.mcpServers = mcpServers
        }

        public var isEmpty: Bool {
            mcpServers.isEmpty
        }
    }
}
