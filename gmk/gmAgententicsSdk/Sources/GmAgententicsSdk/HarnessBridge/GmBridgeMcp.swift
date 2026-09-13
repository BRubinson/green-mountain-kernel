import Foundation

extension GmBridgeMcp {

    public static let serverKey = "cde"

    public static let pluginName = GmBridgeClaudePlugin.current.name

    public static let qualifiedServer = "plugin_\(pluginName)_\(serverKey)"

    public static let launcher = "\(GmBridgeClaudeTypePath.pluginRoot)/scripts/run_mcp.sh"

    public static let current = File(
        mcpServers: [
            serverKey: Server.stdio(command: launcher, alwaysLoad: true)
        ]
    )
}
