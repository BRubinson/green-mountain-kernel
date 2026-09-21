// The eight GMK agent roles, each carrying its directive text and whether it wears a personality lens.

import Foundation

enum AgentGmkDirective: String, Sendable, Hashable, Codable, CaseIterable {

    case primarch
    case briefer
    case explorer
    case intentClarifier
    case architect
    case implementor
    case reviewer
    case kbiteChewer

    var text: String {
        switch self {
        case .primarch: return GM_AGENT_PRIMARCH_DIRECTIVE
        case .briefer: return GM_AGENT_BRIEFER_DIRECTIVE
        case .explorer: return GM_AGENT_EXPLORER_DIRECTIVE
        case .intentClarifier: return GM_AGENT_INTENT_CLARIFIER_DIRECTIVE
        case .architect: return GM_AGENT_ARCHITECT_DIRECTIVE
        case .implementor: return GM_AGENT_IMPLEMENTOR_DIRECTIVE
        case .reviewer: return GM_AGENT_REVIEWER_DIRECTIVE
        case .kbiteChewer: return GM_AGENT_KBITE_CHEWER_DIRECTIVE
        }
    }

    var takesPersonality: Bool {
        switch self {
        case .explorer, .architect, .reviewer: return true
        case .primarch, .briefer, .intentClarifier, .implementor, .kbiteChewer: return false
        }
    }
}
