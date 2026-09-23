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

        /// Creates an LSP server configuration.
        /// - Parameters:
        ///   - command: The command to launch the server.
        ///   - extensionToLanguage: Mapping of file extensions to language identifiers.
        ///   - args: Optional command-line arguments.
        ///   - transport: The communication transport (stdio or socket).
        ///   - env: Optional environment variables for the server process.
        ///   - initializationOptions: Optional JSON initialization parameters.
        ///   - settings: Optional configuration settings.
        ///   - workspaceFolder: Optional workspace folder path.
        ///   - startupTimeout: Optional startup timeout in milliseconds.
        ///   - shutdownTimeout: Optional shutdown timeout in milliseconds.
        ///   - restartOnCrash: Whether to restart on unexpected termination.
        ///   - maxRestarts: Maximum number of restart attempts.
        ///   - diagnostics: Whether to enable diagnostic logging.
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

        /// Creates an LSP configuration file with the given servers.
        /// - Parameter servers: A dictionary mapping server names to configurations.
        init(servers: [String: Server]) {
            self.servers = servers
        }

        var isEmpty: Bool {
            servers.isEmpty
        }

        /// Encodes the LSP file structure to the given encoder.
        /// - Parameter encoder: The encoder to write the servers dictionary to.
        /// - Throws: Any encoding error during serialization.
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(servers)
        }
    }
}
