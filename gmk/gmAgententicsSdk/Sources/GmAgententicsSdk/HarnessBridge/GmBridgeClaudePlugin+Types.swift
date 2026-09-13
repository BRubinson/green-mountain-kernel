import Foundation

public enum GmBridgeClaudePlugin {

    public struct Author: Codable, Equatable, Sendable {

        public var name: String

        public var email: String?

        public var url: String?

        public init(name: String, email: String? = nil, url: String? = nil) {
            self.name = name
            self.email = email
            self.url = url
        }
    }

    public struct Experimental: Codable, Equatable, Sendable {

        public var themes: [String]?

        public var monitors: [String]?

        public var evals: [String]?

        public init(
            themes: [String]? = nil,
            monitors: [String]? = nil,
            evals: [String]? = nil
        ) {
            self.themes = themes
            self.monitors = monitors
            self.evals = evals
        }

        public var isEmpty: Bool {
            themes == nil && monitors == nil && evals == nil
        }
    }

    public struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        public var relativePath: String { ".claude-plugin/plugin.json" }

        public var name: String

        public var displayName: String?

        public var version: String?

        public var description: String?

        public var author: Author?

        public var homepage: String?

        public var repository: String?

        public var license: String?

        public var keywords: [String]?

        public var metadata: [String: String]?

        public var defaultEnabled: Bool?

        public var skills: [String]?

        public var commands: [String]?

        public var agents: [String]?

        public var workflows: [String]?

        public var hooks: [String]?

        public var mcpServers: [String]?

        public var outputStyles: [String]?

        public var lspServers: [String]?

        public var experimental: Experimental?

        public init(
            name: String,
            displayName: String? = nil,
            version: String? = nil,
            description: String? = nil,
            author: Author? = nil,
            homepage: String? = nil,
            repository: String? = nil,
            license: String? = nil,
            keywords: [String]? = nil,
            metadata: [String: String]? = nil,
            defaultEnabled: Bool? = nil,
            skills: [String]? = nil,
            commands: [String]? = nil,
            agents: [String]? = nil,
            workflows: [String]? = nil,
            hooks: [String]? = nil,
            mcpServers: [String]? = nil,
            outputStyles: [String]? = nil,
            lspServers: [String]? = nil,
            experimental: Experimental? = nil
        ) {
            self.name = name
            self.displayName = displayName
            self.version = version
            self.description = description
            self.author = author
            self.homepage = homepage
            self.repository = repository
            self.license = license
            self.keywords = keywords
            self.metadata = metadata
            self.defaultEnabled = defaultEnabled
            self.skills = skills
            self.commands = commands
            self.agents = agents
            self.workflows = workflows
            self.hooks = hooks
            self.mcpServers = mcpServers
            self.outputStyles = outputStyles
            self.lspServers = lspServers
            self.experimental = experimental
        }
    }
}
