import Foundation

enum GmBridgeLsp {

    enum Transport: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case stdio

        case socket
    }

    struct Server: Encodable, Equatable, Sendable {

        var command: String

        var extensionToLanguage: [String: String]

        var args: [String]?

        var transport: Transport?

        var env: [String: String]?

        var initializationOptions: GmBridgeJsonValue?

        var settings: GmBridgeJsonValue?

        var workspaceFolder: String?

        var startupTimeout: Int?

        var shutdownTimeout: Int?

        var restartOnCrash: Bool?

        var maxRestarts: Int?

        var diagnostics: Bool?

        init(
            command: String,
            extensionToLanguage: [String: String],
            args: [String]? = nil,
            transport: Transport? = nil,
            env: [String: String]? = nil,
            initializationOptions: GmBridgeJsonValue? = nil,
            settings: GmBridgeJsonValue? = nil,
            workspaceFolder: String? = nil,
            startupTimeout: Int? = nil,
            shutdownTimeout: Int? = nil,
            restartOnCrash: Bool? = nil,
            maxRestarts: Int? = nil,
            diagnostics: Bool? = nil
        ) {
            self.command = command
            self.extensionToLanguage = extensionToLanguage
            self.args = args
            self.transport = transport
            self.env = env
            self.initializationOptions = initializationOptions
            self.settings = settings
            self.workspaceFolder = workspaceFolder
            self.startupTimeout = startupTimeout
            self.shutdownTimeout = shutdownTimeout
            self.restartOnCrash = restartOnCrash
            self.maxRestarts = maxRestarts
            self.diagnostics = diagnostics
        }
    }

    struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { ".lsp.json" }

        var servers: [String: Server]

        init(servers: [String: Server]) {
            self.servers = servers
        }

        var isEmpty: Bool {
            servers.isEmpty
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(servers)
        }
    }
}
