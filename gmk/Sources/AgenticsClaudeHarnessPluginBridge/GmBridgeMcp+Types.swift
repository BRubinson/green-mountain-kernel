import Foundation

enum GmBridgeMcp {

    enum Transport: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case stdio

        case http

        case sse

        case ws
    }

    struct Server: Codable, Equatable, Hashable, Sendable {

        var type: Transport?

        var command: String?

        var args: [String]?

        var env: [String: String]?

        var url: String?

        var headers: [String: String]?

        var alwaysLoad: Bool?

        init(
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

        static func stdio(
            command: String,
            args: [String]? = nil,
            env: [String: String]? = nil,
            alwaysLoad: Bool? = nil
        ) -> Server {
            Server(command: command, args: args, env: env, alwaysLoad: alwaysLoad)
        }
    }

    struct File: Codable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { ".mcp.json" }

        var mcpServers: [String: Server]

        init(mcpServers: [String: Server]) {
            self.mcpServers = mcpServers
        }

        var isEmpty: Bool {
            mcpServers.isEmpty
        }
    }
}
