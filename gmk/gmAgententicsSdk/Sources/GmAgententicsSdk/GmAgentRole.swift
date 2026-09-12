import Foundation

// The AGENT roster: which personas GMCC runs, and the facts about each that are
// true regardless of what is being said to it.
//
// TOP LEVEL RATHER THAN `Templates/`, and the placement is the point. This type
// was born inside `Templates/Instructions.swift` because instructions were the
// first thing that needed it, but "which agents exist" is not a fact about
// templates — it is package-level vocabulary, the agent-side parallel to
// `GmAgentToolFamily` in `GmAgentTool.swift`. Anything that later spawns,
// schedules, budgets or routes an agent needs this enum and has no business
// importing a templates file to get it.
//
// NO FoundationModels IMPORT, deliberately. Nothing here is a `Tool`, an
// `Instructions` or a `Prompt`, so nothing here needs the availability floor
// that the rest of this package carries. A role can be named, switched on,
// logged, encoded and decoded on any platform; only turning one INTO an
// `Instructions` value costs macOS 27, and that conversion lives in
// `GmAgentInstructions` where the cost belongs.
//
// WHAT IS DELIBERATELY NOT HERE: the text. A role knows WHERE its contract was
// copied from (`sourcePath`) but not WHAT it says. Keeping the blocks in
// `Templates/` is what lets this file stay small enough to read in one screen
// while the contracts themselves run to thousands of lines.

/// The personas GMCC runs, each backed by one standing instruction block.
///
/// A role is not a tool family (`GmAgentToolFamily`) and does not map onto one:
/// families partition the tool SURFACE, roles partition the AGENTS that call
/// into it. The clarifier and the reviewer both reach the `cde` family and are
/// nothing alike.
///
/// `Codable` with explicit raw values on the two multi-word cases, because a
/// role is a thing that gets written down — into a spawn record, a log line, a
/// db row — and Swift's default camelCase raw value would make the on-disk
/// spelling a hostage to the Swift identifier. The snake_case spellings match
/// the vocabulary every other persisted enum in this stack uses.
public enum GmAgentRole: String, Sendable, Hashable, Codable, CaseIterable {

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

    /// Whether this role is spawned WITH a methodology
    /// (`ExplorationAgentType`) and commits fully to it.
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
