import Foundation

extension GmBridgeMcp {

    public static let serverKey = "cde"

    public static let pluginName = GmBridgeClaudePlugin.current.name

    public static let qualifiedServer = "plugin_\(pluginName)_\(serverKey)"

    /// The pen launcher, as an inline shell command rather than a script file.
    ///
    /// `run_mcp.sh` is gone; this replaces it. THE SHAPE IS NOT A STYLE CHOICE —
    /// two things about MCP stdio servers force it:
    ///
    /// 1. `command`/`args`/`env` substitute EXACTLY THREE placeholders
    ///    (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`).
    ///    `${GM_FS_ROOT:-$HOME/gmfs}` is not among them and would be passed
    ///    through as a literal.
    /// 2. The server is spawned with NO SHELL, so even a valid variable would
    ///    not expand and `[ -x ]` could not be tested.
    ///
    /// So the command is `/bin/sh` and the script is an argument. Writing
    /// `command: "${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_mcp"` instead — the obvious
    /// move, and the one an earlier draft of this change made — produces a pen
    /// that never starts on any machine where `GM_FS_ROOT` is unset, which is
    /// every first session.
    ///
    /// The `exit 1` on a missing binary is deliberate and is the OPPOSITE of the
    /// hook contract. A hook must never fail; a pen launcher must fail LOUDLY,
    /// because a silently absent pen looks to an agent like a pen with no tools.
    public static let launcher = "/bin/sh"

    public static let launcherArgs = ["-c", #"""
        GM_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin"; \
        if [ ! -x "$GM_BIN/gm_mcp" ]; then \
          echo "[GMB] gm_mcp missing at $GM_BIN/gm_mcp — run: bash \"$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh\"" >&2; \
          exit 1; \
        fi; exec "$GM_BIN/gm_mcp"
        """#]

    public static let current = File(
        mcpServers: [
            serverKey: Server.stdio(command: launcher, args: launcherArgs, alwaysLoad: true)
        ]
    )
}
