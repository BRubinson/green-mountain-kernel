import Foundation

struct GmBridgeMcpTool: Codable, Equatable, Hashable, Sendable {

    static let server = GmBridgeMcp.qualifiedServer

    var name: String

    var title: String?

    var description: String?

    var inputSchema: GmBridgeJsonValue

    var outputSchema: GmBridgeJsonValue?

    var annotations: Annotations?

    var icons: [Icon]?

    /// Creates an MCP tool descriptor.
    /// - Parameters:
    ///   - name: The unqualified tool name.
    ///   - title: The display title, or nil for none.
    ///   - description: A short description of the tool's purpose.
    ///   - inputSchema: The JSON schema for input parameters.
    ///   - outputSchema: The JSON schema for the output, if any.
    ///   - annotations: Metadata hints about the tool's properties.
    ///   - icons: Icon resources for the tool.
    init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: GmBridgeJsonValue = .emptyObjectSchema,
        outputSchema: GmBridgeJsonValue? = nil,
        annotations: Annotations? = nil,
        icons: [Icon]? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.icons = icons
    }

    var qualifiedName: String {
        "mcp__\(Self.server)__\(name)"
    }

    struct Annotations: Codable, Equatable, Hashable, Sendable {

        var title: String?

        var readOnlyHint: Bool?

        var destructiveHint: Bool?

        var idempotentHint: Bool?

        var openWorldHint: Bool?

        /// Creates tool annotation metadata.
        /// - Parameters:
        ///   - title: Display title for the annotations.
        ///   - readOnlyHint: Whether the tool only reads, affecting display.
        ///   - destructiveHint: Whether the tool may have side effects.
        ///   - idempotentHint: Whether repeated calls are safe.
        ///   - openWorldHint: Whether the tool affects external systems.
        init(
            title: String? = nil,
            readOnlyHint: Bool? = nil,
            destructiveHint: Bool? = nil,
            idempotentHint: Bool? = nil,
            openWorldHint: Bool? = nil
        ) {
            self.title = title
            self.readOnlyHint = readOnlyHint
            self.destructiveHint = destructiveHint
            self.idempotentHint = idempotentHint
            self.openWorldHint = openWorldHint
        }
    }

    struct Icon: Codable, Equatable, Hashable, Sendable {

        var src: String

        var mimeType: String?

        var sizes: [String]?

        /// Creates a tool icon descriptor.
        /// - Parameters:
        ///   - src: The icon resource URL or path.
        ///   - mimeType: The MIME type of the icon, or nil for auto-detection.
        ///   - sizes: Supported icon sizes (e.g., "16x16", "32x32").
        init(src: String, mimeType: String? = nil, sizes: [String]? = nil) {
            self.src = src
            self.mimeType = mimeType
            self.sizes = sizes
        }
    }
}

extension GmBridgeMcpTool {

    /// Every tool the bridge declares — the SERVED roster.
    ///
    /// The MCP server answers to exactly this set, refusals included.
    static let all: [GmBridgeMcpTool] = GmAgentTools.all.map(GmBridgeMcpTool.init)

    /// The tools worth GRANTING in an `allowed-tools` list.
    ///
    /// Served and grantable are different sets. The `*_not_supported` family
    /// placeholders are served so an agent that goes looking finds an answer, but
    /// granting one spends a frontmatter slot in every skill, command and agent
    /// that takes the family, for a tool whose only behaviour is to throw. Keyed on
    /// the suffix, so an individually-refusing tool that names a real capability
    /// stays grantable and its specific refusal stays reachable.
    static var grantable: [GmBridgeMcpTool] {
        all.filter { !$0.name.hasSuffix("_not_supported") }
    }

    /// Fetches MCP tools that belong to a tool family.
    /// - Parameter family: The tool family to filter by.
    /// - Returns: An array of bridge MCP tools in the family.
    static func tools(in family: GmAgentToolFamily) -> [GmBridgeMcpTool] {
        GmAgentTools.tools(in: family).map(GmBridgeMcpTool.init)
    }

    static var qualifiedNames: [String] {
        all.map(\.qualifiedName)
    }
}
