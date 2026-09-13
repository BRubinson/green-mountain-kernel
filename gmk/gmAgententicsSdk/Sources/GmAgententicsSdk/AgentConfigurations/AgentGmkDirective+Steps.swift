// Each role's step set.

import Foundation

extension AgentGmkDirective {

    var steps: String {
        switch self {
        case .primarch: return GM_AGENT_PRIMARCH_INSTRUCTION
        case .briefer: return GM_AGENT_BRIEFER_INSTRUCTION
        case .explorer: return GM_CDE_AGENT_EXPLORE_INSTRUCTION
        case .intentClarifier: return GM_CDE_AGENT_INTENT_CLARIFIER_INSTRUCTION
        case .architect: return GM_CDE_AGENT_ARCHITECT_INSTRUCTION
        case .implementor: return GM_CDE_AGENT_IMPLEMENTOR_INSTRUCTION
        case .reviewer: return GM_CDE_AGENT_REVIEWER_INSTRUCTION
        case .kbiteChewer: return GM_AGENT_KBITE_CHEWER_INSTRUCTION
        }
    }
}

// THE ASSEMBLY MOVED, and this note is kept rather than the code because the
// deletion is the point. `session(personality:)`, `solo(personality:)`,
// `primary` and `assemble(...)` lived here and composed a body from core +
// personality + directives + steps. `AgentGmkSessionProfile.compile()` now does
// that, once per process, for all twelve profiles.
//
// Two assemblies is the exact drift this refactor exists to remove: the markdown
// an agent is spawned with and the instructions a native session runs on have to
// be the same text, and they can only be guaranteed the same if one function
// produces both. Do not reintroduce a second one here.
