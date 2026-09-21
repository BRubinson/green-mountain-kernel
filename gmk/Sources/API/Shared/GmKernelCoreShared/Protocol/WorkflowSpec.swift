import Foundation

// LIVES IN THE BASE LAYER, not beside the Store. `Protocol/VerbRegistry.swift`
// names `WorkflowSpec.Phase`, so filing this under persistence would be a
// base-depends-on-middle cycle once the modules separate, and gm_mcp reads it
// while linking the SDK alone. Nothing here is persistence: no GRDB, no Store,
// no database access — declarative phase and instruction data that happens to
// describe a db-derived workflow.

/// The workflow phase registry: the per-variant ordered phase graph for the
/// daemon-held bot state machine, and the instruction text each phase hands
/// whoever asks for it. Phase is DERIVED from db evidence at every BOT_NEXT —
/// no stored cursor, so resume is the only code path there is. A new phase or
/// variant is an entry here rather than a schema change.

/// PHASE IS NOT PROMPT STATUS. The prompt row carries three states while this
/// file describes twelve phases, and that is not a mismatch: phases are derived
/// from evidence rather than read off the prompt. Derivation never reads status,
/// and the only status moves are to `initiated` when a briefing opens and to
/// `done` at the end. Phase boundaries are crossed by opening and sealing the
/// phase's own rows.

/// THE PROSE NAMES A SKILL, NEVER A TOOL. This text is served verbatim through
/// `BOT_NEXT` to the agents doing the work, and a block naming the wrong write
/// path is the wrong write path everywhere at once — so it names the phase's
/// skill and lets the skill name the ops. CDE workflow work is pen-only: a tool
/// an agent cannot see is a missing GRANT to report, never a cue to shell to the
/// wire, whose unbudgeted output the harness silently truncates.
enum WorkflowSpec {

    /// Phase codes, in canonical order of appearance across variants.
    enum Phase: String, CaseIterable, Sendable {
        case briefing
        case explore
        case clarifyOpen = "clarify_open"
        case clarifyUser = "clarify_user"
        case carePackage = "care_package"
        case archOptions = "arch_options"
        case architecture
        case planGate = "plan_gate"
        case implement
        case review
        case reviewFix = "review_fix"
        case done
    }

    /// The ordered phase graph per variant. `task` is deliberately absent —
    /// its write-nothing contract means no workflow row exists to walk.
    static func phases(for variant: BotVariant) -> [Phase] {
        switch variant {
        case .bot:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser,
                .architecture, .planGate, .implement, .review, .reviewFix, .done,
            ]
        case .rpi:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                .architecture, .planGate, .implement, .review, .reviewFix, .done,
            ]
        case .team:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                .archOptions, .architecture, .planGate, .implement, .review,
                .reviewFix, .done,
            ]
        }
    }

    /// The exploration agent set each variant must complete before leaving
    /// the explore phase (the synthesis row is gated separately — its
    /// complete IS the prompt-level seal).
    static func expectedExplorationAgents(for variant: BotVariant) -> [ExplorationAgentType] {
        switch variant {
        case .bot, .rpi:
            return [.general]
        case .team:
            return [.aggressive, .conservative, .pragmatic, .alternative]
        }
    }

    /// One line per (variant, phase): the skill that carries the phase's real
    /// instructions, plus who acts. The skill slug IS the phase's raw value, so
    /// a new phase cannot point at a skill nobody wrote without saying so.
    ///
    /// NO TOOL NAME APPEARS HERE. The served roster is where an op is declared
    /// and the skill is where it is taught; a third copy in compiled-in prose is
    /// a third thing to keep true, and it was the one nothing checked.
    static func instructions(variant: BotVariant, phase: Phase) -> String {
        "Load the skill `gmcc:cde_rpir_\(phase.rawValue)` and follow it. "
            + staffing(variant: variant, phase: phase)
    }

    /// Who does the work. Variant-specific only where the staffing genuinely
    /// differs; elsewhere it is the one rule the skill assumes of its reader.
    private static func staffing(variant: BotVariant, phase: Phase) -> String {
        switch phase {
        case .briefing:
            return "The primary opens the row; a briefer fills it."
        case .explore:
            switch variant {
            case .bot: return "Explore IN CONTEXT — no subagents — then run the clarifier pass yourself."
            case .rpi: return "ONE general-persona explorer, then ONE clarifier."
            case .team: return "One explorer per methodology, then ONE clarifier."
            }
        case .clarifyOpen:
            return "One reader ranks across every agent, seals synthesis, then authors the suite."
        case .clarifyUser:
            return "The primary asks the user; nobody answers on their behalf."
        case .carePackage:
            return "One curator. The clarified intent lives in the package and nowhere else."
        case .archOptions:
            return "One architect per methodology; wait for every option before deciding."
        case .architecture:
            switch variant {
            case .bot: return "Design in context, then persist the rows yourself."
            case .rpi: return "ONE subagent proposes; the primary persists."
            case .team: return "The primary decides among the options, then expands the winner."
            }
        case .planGate:
            return "The primary proposes; the user signs off."
        case .implement:
            switch variant {
            case .bot: return "Implement in context."
            case .rpi: return "Up to 2 implementers, one file-path slice each."
            case .team: return "Author the workflow; every write happens inside an agent."
            }
        case .review:
            switch variant {
            case .bot: return "Review in context."
            case .rpi: return "ONE general-persona reviewer."
            case .team: return "One reviewer per methodology."
            }
        case .reviewFix:
            return "The fixes are implementation and carry implementation's proof."
        case .done:
            return "The primary closes the prompt."
        }
    }
}
