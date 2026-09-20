import Foundation

extension GmBridgeMcp {

    public static let serverKey = "cde"

    public static let pluginName = GmBridgeClaudePlugin.current.name

    public static let qualifiedServer = "plugin_\(pluginName)_\(serverKey)"

    /// The pen launcher, as an inline shell command rather than a script file.
    ///
    /// MCP stdio `command`/`args`/`env` substitute exactly three placeholders
    /// (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`) and are
    /// spawned with NO SHELL, so `${GM_FS_ROOT:-$HOME/gmfs}` would pass through as
    /// a literal and `[ -x ]` could not be tested. Hence `/bin/sh` with the script
    /// as an argument. The `exit 1` on a missing binary is the opposite of the hook
    /// contract: a silently absent pen looks to an agent like a pen with no tools.
    public static let launcher = "/bin/sh"

    public static let launcherArgs = [
        "-c",
        #"""
        GM_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin"; \
        if [ ! -x "$GM_BIN/gm_mcp" ]; then \
          echo "[GMB] gm_mcp missing at $GM_BIN/gm_mcp — run: bash \"$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh\"" >&2; \
          exit 1; \
        fi; exec "$GM_BIN/gm_mcp"
        """#,
    ]

    public static let current = File(
        mcpServers: [
            serverKey: Server.stdio(command: launcher, args: launcherArgs, alwaysLoad: true)
        ]
    )
}
