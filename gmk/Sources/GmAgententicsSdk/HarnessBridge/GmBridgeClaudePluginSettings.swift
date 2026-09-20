import Foundation

extension GmBridgeClaudePluginSettings {

    /// The plugin's default settings, deliberately empty.
    ///
    /// A plugin-root `settings.json` honors exactly `agent` and
    /// `subagentStatusLine`, dropping every other key silently. Setting `agent:`
    /// runs the main thread as a subagent, replacing Claude Code's own system
    /// prompt and restricting the session to that agent file's `tools:` list, so
    /// the identity arrives as an appending output style instead. Empty means no
    /// `settings.json` is emitted, hence the style's `force-for-plugin: true`.
    public static let current = File()
}
