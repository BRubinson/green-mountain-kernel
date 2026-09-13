import Foundation

extension GmBridgeClaudePluginSettings {

    /// The plugin's default settings.
    ///
    /// `agent` boots EVERY session as `primarch`, which is the whole point: the
    /// base primary should arrive already wearing the primarch profile rather
    /// than acquiring it from whatever a command happens to load. It is also the
    /// only lever a plugin has for this — a plugin-root `settings.json` honors
    /// exactly `agent` and `subagentStatusLine`, and silently drops every other
    /// key.
    ///
    /// This reverses an earlier reading of the same field. The objection was
    /// that naming an agent here boots every session into a workflow subagent's
    /// narrow toolset; that is true of the seven phase agents and false of
    /// `primarch`, which carries the full native surface plus the whole tool
    /// roster precisely because it is the primary.
    public static let current = File(agent: "primarch")
}
