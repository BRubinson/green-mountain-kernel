import Foundation

extension GmBridgeMcp {

    static let serverKey = "cde"

    static let pluginName = GmBridgeClaudePlugin.current.name

    static let qualifiedServer = "plugin_\(pluginName)_\(serverKey)"

    /// The pen launcher, as an inline shell command rather than a script file.
    ///
    /// The pen ships INSIDE the plugin (`bin/gm_mcp`, compiled with the client
    /// closure), so no root has to be resolved to find it; it still dials the
    /// kernel through `Paths.root`. `/bin/sh -c` stays because MCP stdio
    /// `command`/`args` are spawned with NO SHELL and `[ -x ]` needs one. The
    /// `exit 1` on a missing binary is the opposite of the hook contract: a
    /// silently absent pen looks to an agent like a pen with no tools.
    static let launcher = "/bin/sh"

    static let launcherArgs = [
        "-c",
        #"""
        GM_MCP="${CLAUDE_PLUGIN_ROOT}/bin/gm_mcp"; \
        if [ ! -x "$GM_MCP" ]; then \
          echo "[GMB] gm_mcp missing at $GM_MCP — this plugin tree was written without build_plugin_binaries.sh" >&2; \
          exit 1; \
        fi; exec "$GM_MCP"
        """#,
    ]

    /// No server-wide `alwaysLoad`: the five tools worth pinning carry their own
    /// per-tool `_meta` pin, and pinning the whole server spends context on the
    /// nine that are cheaper to load on demand.
    static let current = File(
        mcpServers: [
            serverKey: Server.stdio(command: launcher, args: launcherArgs)
        ]
    )
}
