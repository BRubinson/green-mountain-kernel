import Foundation
import FoundationModels

extension GmBridgeMcpTool {

    static func flattenedName(
        family: GmAgentToolFamily,
        name: String
    ) -> String {
        let prefix = "\(family.rawValue)_"
        return name.hasPrefix(prefix) ? name : prefix + name
    }

    static func inputSchema(for tool: any GmAgentTool) -> GmBridgeJsonValue {
        guard
            let data = try? JSONEncoder().encode(tool.parameters),
            let schema = try? JSONDecoder().decode(GmBridgeJsonValue.self, from: data)
        else {
            return .emptyObjectSchema
        }
        return schema
    }

    init(_ tool: any GmAgentTool) {
        self.init(
            name: Self.flattenedName(family: tool.family, name: tool.name),
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
