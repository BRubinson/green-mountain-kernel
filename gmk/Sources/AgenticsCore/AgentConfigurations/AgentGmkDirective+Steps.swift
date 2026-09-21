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

// Assembly belongs to `AgentGmkSessionProfile.compile()` alone. The markdown an
// agent is spawned with and the instructions a native session runs on must be the
// same text, which only holds while one function produces both — so do not add a
// second assembly here.
