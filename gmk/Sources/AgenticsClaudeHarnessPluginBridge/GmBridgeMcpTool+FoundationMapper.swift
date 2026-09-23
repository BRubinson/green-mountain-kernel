import Foundation
import FoundationModels

extension GmBridgeMcpTool {

    /// Encodes a tool's parameters into a JSON schema.
    /// - Parameter tool: The agent tool.
    /// - Returns: A JSON value representing the schema, or an empty object schema if encoding fails.
    static func inputSchema(for tool: any GmAgentTool) -> GmBridgeJsonValue {
        guard
            let data = try? JSONEncoder().encode(tool.parameters),
            let schema = try? JSONDecoder().decode(GmBridgeJsonValue.self, from: data)
        else {
            return .emptyObjectSchema
        }
        return schema
    }

    /// Creates a bridge tool from an agent tool.
    ///
    /// The tool's declared name is the served name; the family is a grant
    /// grouping, never a prefix.
    ///
    /// - Parameter tool: The agent tool to wrap.
    init(_ tool: any GmAgentTool) {
        self.init(
            name: tool.name,
            description: tool.description,
            inputSchema: Self.inputSchema(for: tool)
        )
    }
}

extension GmAgentTool {

    var bridgeTool: GmBridgeMcpTool {
        GmBridgeMcpTool(self)
    }

    var qualifiedName: String {
        bridgeTool.qualifiedName
    }
}
