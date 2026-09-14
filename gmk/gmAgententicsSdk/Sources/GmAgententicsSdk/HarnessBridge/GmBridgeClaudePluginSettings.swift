import Foundation

extension GmBridgeClaudePluginSettings {

    /// The plugin's default settings — now EMPTY, on purpose.
    ///
    /// A plugin-root `settings.json` honors exactly `agent` and
    /// `subagentStatusLine` and silently drops every other key, so this file
    /// could only ever have carried `agent`. It no longer does.
    ///
    /// THIS REVERSES THE PREVIOUS REVERSAL, and on mechanism rather than taste.
    /// `agent:` runs the main thread AS a subagent, which means Claude Code
    /// applies that agent's system prompt INSTEAD of its own — taking the
    /// built-in software-engineering instructions with it — and restricts the
    /// session to the agent file's `tools:` list. The restriction was not
    /// theoretical: it cut the primarch to 17 MCP tools and forced its own
    /// writes through `gm_hook` because the pen tools its instruction set names
    /// were not in the grant.
    ///
    /// The identity now arrives as an APPENDING output style
    /// (`keep-coding-instructions: true`), which ADDS to Claude Code's system
    /// prompt instead of replacing it and imposes no tool restriction at all.
    /// See `GmBridgeOutputStyle.all`.
    ///
    /// CONSEQUENCE, EXPECTED AND NOT A BUG: `isEmpty` is now true, `contents()`
    /// returns nil, and `settings.json` IS NOT EMITTED. That is why the style
    /// must carry `force-for-plugin: true` — no settings file survives to select
    /// it.
    ///
    /// THE SEVEN SUBAGENTS ARE UNAFFECTED. A style never reaches a subagent, and
    /// a subagent body has never carried the engineering instructions. Explore,
    /// brief, architect and review deliberately keep it that way.
    public static let current = File()
}
