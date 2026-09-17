import Foundation
import GmDaemonSdk

extension GmBridgeClaudePlugin {

    /// The env var that overrides the plugin's NAME for one writer run.
    ///
    /// The whole plugin identity derives from `current.name`: `plugin.json`'s
    /// name, every `mcp__plugin_<name>_cde__*` tool grant (through
    /// `GmBridgeMcp.qualifiedServer`), and the `/<name>:` slash-command
    /// namespace the harness derives from it. So setting this to `gmbeta` for a
    /// single `gm_bridge_writer` invocation emits a COMPLETE, natively-correct
    /// alias tree with no string substitution and no site that can be missed —
    /// which is exactly why `--plugin-dir <gmbeta-tree>` no longer collides with
    /// the marketplace `gmcc`. Unset (the default) it stays `gmcc`, so every
    /// existing invocation is byte-for-byte unchanged.
    public static let pluginNameEnvVar = "GM_BRIDGE_PLUGIN_NAME"

    public static let current = File(
        name: ProcessInfo.processInfo.environment[pluginNameEnvVar] ?? "gmcc",
        version: GmVersion.current,
        description: """
            Green Mountain Coding Collection — a harness integration for the \
            Green Mountain Kernel, bringing integrated, opinionated coding \
            practices.
            """
        // NO `outputStyles:` KEY. It is not part of the plugin manifest schema,
        // and emitting it does not degrade gracefully — Claude Code REJECTS the
        // whole manifest with "outputStyles: Invalid input", which disables the
        // entire plugin rather than just ignoring the key.
        //
        // A plugin ships output styles by PUTTING THEM IN `output-styles/`, and
        // nothing announces them in the manifest. Auto-application is the style
        // file's own business: `force-for-plugin: true` in its frontmatter is
        // what applies it whenever the plugin is enabled. See
        // GmBridgeOutputStyle.all, whose primarch style already carries it.
    )
}
