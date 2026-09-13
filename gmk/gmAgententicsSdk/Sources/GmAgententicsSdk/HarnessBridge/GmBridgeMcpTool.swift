import Foundation

public struct GmBridgeMcpTool: Codable, Equatable, Hashable, Sendable {

    public static let server = GmBridgeMcp.qualifiedServer

    public var name: String

    public var title: String?

    public var description: String?

    public var inputSchema: GmBridgeJsonValue

    public var outputSchema: GmBridgeJsonValue?

    public var annotations: Annotations?

    public var icons: [Icon]?

    public init(
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

    public var qualifiedName: String {
        "mcp__\(Self.server)__\(name)"
    }

    public struct Annotations: Codable, Equatable, Hashable, Sendable {

        public var title: String?

        public var readOnlyHint: Bool?

        public var destructiveHint: Bool?

        public var idempotentHint: Bool?

        public var openWorldHint: Bool?

        public init(
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

    public struct Icon: Codable, Equatable, Hashable, Sendable {

        public var src: String

        public var mimeType: String?

        public var sizes: [String]?

        public init(src: String, mimeType: String? = nil, sizes: [String]? = nil) {
            self.src = src
            self.mimeType = mimeType
            self.sizes = sizes
        }
    }
}

@available(GmAgentOs 1.0, *)
extension GmBridgeMcpTool {

    public static let all: [GmBridgeMcpTool] = GmAgentTools.all.map(GmBridgeMcpTool.init)

    public static func tools(in family: GmAgentToolFamily) -> [GmBridgeMcpTool] {
        GmAgentTools.tools(in: family).map(GmBridgeMcpTool.init)
    }

    public static var qualifiedNames: [String] {
        all.map(\.qualifiedName)
    }
}
