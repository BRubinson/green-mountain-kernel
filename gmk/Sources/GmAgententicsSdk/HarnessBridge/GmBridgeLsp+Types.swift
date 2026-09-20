import Foundation

public enum GmBridgeLsp {

    public enum Transport: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

        case stdio

        case socket
    }

    public struct Server: Encodable, Equatable, Sendable {

        public var command: String

        public var extensionToLanguage: [String: String]

        public var args: [String]?

        public var transport: Transport?

        public var env: [String: String]?

        public var initializationOptions: GmBridgeJsonValue?

        public var settings: GmBridgeJsonValue?

        public var workspaceFolder: String?

        public var startupTimeout: Int?

        public var shutdownTimeout: Int?

        public var restartOnCrash: Bool?

        public var maxRestarts: Int?

        public var diagnostics: Bool?

        public init(
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

    public struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { ".lsp.json" }

        public var servers: [String: Server]

        public init(servers: [String: Server]) {
            self.servers = servers
        }

        public var isEmpty: Bool {
            servers.isEmpty
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(servers)
        }
    }
}
