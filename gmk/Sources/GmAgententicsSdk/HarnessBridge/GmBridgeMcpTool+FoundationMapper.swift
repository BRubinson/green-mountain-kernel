import Foundation
import FoundationModels

@available(GmAgentOs 1.0, *)
extension GmBridgeMcpTool {

    public static func flattenedName(
        family: GmAgentToolFamily,
        name: String
    ) -> String {
        let prefix = "\(family.rawValue)_"
        return name.hasPrefix(prefix) ? name : prefix + name
    }

    public static func inputSchema(for tool: any GmAgentTool) -> GmBridgeJsonValue {
        guard
            let data = try? JSONEncoder().encode(tool.parameters),
            let schema = try? JSONDecoder().decode(GmBridgeJsonValue.self, from: data)
        else {
            return .emptyObjectSchema
        }
        return schema
    }

    public init(_ tool: any GmAgentTool) {
        self.init(
            name: Self.flattenedName(family: tool.family, name: tool.name),
            description: tool.description,
            inputSchema: Self.inputSchema(for: tool)
        )
    }
}

@available(GmAgentOs 1.0, *)
extension GmAgentTool {

    public var bridgeTool: GmBridgeMcpTool {
        GmBridgeMcpTool(self)
    }

    public var qualifiedName: String {
        bridgeTool.qualifiedName
    }
}
