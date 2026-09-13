import Foundation

// The ARCHIVE's own role vocabulary.
//
// `original/` IS SEALED: nothing in this directory references anything outside
// it, and nothing outside it references anything in here. That is why this enum
// exists at all rather than the archive sharing `GmAgentRole` from `Templates/`.
// A shared enum looks like the obvious economy and is the thing that rots the
// archive — every later edit to the live vocabulary would silently rewrite what
// this transcription claims the plugin said.
//
// The duplication is therefore LOAD-BEARING, not an oversight. These two enums
// are expected to diverge: `GmAgentRole` follows whatever the execution layer
// grows into, and `OriginalGmccRole` only ever changes when `plugins/gmcc/`
// changes and the archive is re-synced by copying.
//
// WHAT THIS CARRIES THAT THE LIVE ENUM DOES NOT: `sourcePath` and
// `subagentType`. Both are facts about the PLUGIN — where a contract was
// transcribed from, and how Claude Code spawns it. They belong to the record of
// what exists today, not to whatever replaces it.

/// The personas GMCC runs today, as transcribed from `plugins/gmcc/`.
public enum OriginalGmccRole: String, Sendable, Hashable, Codable, CaseIterable {

    /// The GMB itself — the primary, in-session contract every other role
    /// assumes is already loaded.
    case primary

    /// Context acquisition. Opinion-free ref pre-selection into a briefing row.
    case doper

    /// Exploration. Writes its own per-agent summary and finding rows.
    case explorer

    /// The single reader between exploration and the user conversation.
    case clarifier

    /// Architecture. Holds the option pen in team flows.
    case architect

    /// Review. Writes finding rows; never ranks them.
    case reviewer

    /// KBite crunch: raw sources in, structured chewed analysis out.
    case kbiteChewer = "kbite_chewer"

    /// Maw web fetch: the Playwright download runner.
    case mawFetcher = "maw_fetcher"

    /// Where this role's text was copied FROM, relative to `plugins/gmcc/`.
    ///
    /// Provenance rather than decoration: it is what makes a re-sync a
    /// mechanical copy instead of an archaeology exercise.
    public var sourcePath: String {
        switch self {
        case .primary: return "skills/gmcc/SKILL.md"
        case .doper: return "agents/doper.md"
        case .explorer: return "agents/code-explorer.md"
        case .clarifier: return "agents/clarifier.md"
        case .architect: return "agents/code-architect.md"
        case .reviewer: return "agents/code-quality-reviewer.md"
        case .kbiteChewer: return "prompts/gmcc_agent_kbite_crunch_chew.prompt.md"
        case .mawFetcher: return "prompts/gmcc_agent_maw_web_fetch.prompt.md"
        }
    }

    /// Whether this role is spawned WITH a methodology and commits fully to it.
    ///
    /// Exactly the three fan-out roles. The doper and the clarifier are
    /// deliberately single-instance — one calibrates, one pre-selects — and
    /// giving either a methodology would defeat the point of having one reader.
    public var takesMethodology: Bool {
        switch self {
        case .explorer, .architect, .reviewer: return true
        case .primary, .doper, .clarifier, .kbiteChewer, .mawFetcher: return false
        }
    }

    /// The `subagent_type` the plugin spawns this role by, when it has one.
    ///
    /// `primary` has none — it is not spawned; it is the session. The two
    /// `prompts/*.prompt.md` roles are declared as prompt files rather than
    /// `agents/*.md` definitions and are spawned by their own names.
    public var subagentType: String? {
        switch self {
        case .primary: return nil
        case .doper: return "gmcc:doper"
        case .explorer: return "gmcc:code-explorer"
        case .clarifier: return "gmcc:clarifier"
        case .architect: return "gmcc:code-architect"
        case .reviewer: return "gmcc:code-quality-reviewer"
        case .kbiteChewer: return "gmcc:gmcc_agent_kbite_crunch_chew"
        case .mawFetcher: return "gmcc:gmcc_agent_maw_web_fetch"
        }
    }
}
