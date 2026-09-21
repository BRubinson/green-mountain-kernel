import Foundation
import FoundationModels

extension GmBridgeMcpTool {

    static func inputSchema(for tool: any GmAgentTool) -> GmBridgeJsonValue {
        guard
            let data = try? JSONEncoder().encode(tool.parameters),
            let schema = try? JSONDecoder().decode(GmBridgeJsonValue.self, from: data)
        else {
            return .emptyObjectSchema
        }
        return schema
    }

    /// The tool's declared name IS the served name. The family is a grant
    /// grouping, never a prefix — every name already spells its own family.
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
