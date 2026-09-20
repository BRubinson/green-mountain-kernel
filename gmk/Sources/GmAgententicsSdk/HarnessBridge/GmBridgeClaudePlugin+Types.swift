import Foundation

enum GmBridgeClaudePlugin {

    struct Author: Codable, Equatable, Sendable {

        var name: String

        var email: String?

        var url: String?

        init(name: String, email: String? = nil, url: String? = nil) {
            self.name = name
            self.email = email
            self.url = url
        }
    }

    struct Experimental: Codable, Equatable, Sendable {

        var themes: [String]?

        var monitors: [String]?

        var evals: [String]?

        init(
            themes: [String]? = nil,
            monitors: [String]? = nil,
            evals: [String]? = nil
        ) {
            self.themes = themes
            self.monitors = monitors
            self.evals = evals
        }

        var isEmpty: Bool {
            themes == nil && monitors == nil && evals == nil
        }
    }

    struct File: Encodable, Equatable, Sendable, GmBridgeJsonFile {

        var relativePath: String { ".claude-plugin/plugin.json" }

        var name: String

        var displayName: String?

        var version: String?

        var description: String?

        var author: Author?

        var homepage: String?

        var repository: String?

        var license: String?

        var keywords: [String]?

        var metadata: [String: String]?

        var defaultEnabled: Bool?

        var skills: [String]?

        var commands: [String]?

        var agents: [String]?

        var workflows: [String]?

        var hooks: [String]?

        var mcpServers: [String]?

        // THERE IS DELIBERATELY NO `outputStyles` FIELD. Claude Code validates this
        // manifest strictly and answers an unknown key with "outputStyles: Invalid
        // input", refusing to load any of the plugin. Output styles are shipped by
        // existing in `output-styles/`; the manifest never lists them.

        var lspServers: [String]?

        var experimental: Experimental?

        init(
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
            self.lspServers = lspServers
            self.experimental = experimental
        }
    }
}
