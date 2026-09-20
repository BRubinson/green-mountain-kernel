import Foundation

extension GmBridgeClaudePlugin {

    /// The env var that overrides the plugin's NAME for one writer run.
    ///
    /// The whole plugin identity derives from `current.name`: `plugin.json`'s
    /// name, every `mcp__plugin_<name>_cde__*` tool grant and the `/<name>:`
    /// slash-command namespace. Setting it for a single `gm_bridge_writer` run
    /// emits a complete alias tree with no string substitution, so a
    /// `--plugin-dir` tree does not collide with the marketplace `gmcc`.
    public static let pluginNameEnvVar = "GM_BRIDGE_PLUGIN_NAME"

    public static let current = File(
        name: ProcessInfo.processInfo.environment[pluginNameEnvVar] ?? "gmcc",
        version: GmVersion.current,
        description: """
            Green Mountain Coding Collection — a harness integration for the \
            Green Mountain Kernel, bringing integrated, opinionated coding \
            practices.
            """
        // NO `outputStyles:` KEY. Claude Code validates this manifest strictly and
        // answers an unknown key with "outputStyles: Invalid input", disabling the
        // entire plugin. A plugin ships output styles by putting them in
        // `output-styles/`, where `force-for-plugin: true` in a style's own
        // frontmatter applies it. See GmBridgeOutputStyle.all.
    )
}
