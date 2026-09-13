// The methodology lenses a fan-out agent is spawned wearing.

import Foundation

enum AgentGmkPersonality: String, Sendable, Hashable, Codable, CaseIterable {

    case compliant
    case aggressive
    case pragmatic
    case alternative
    case conservative

    var text: String {
        switch self {
        case .compliant: return GM_AGENT_COMPLIANT_PERSONALITY
        case .aggressive: return GM_AGENT_AGGRESSIVE_PERSONALITY
        case .pragmatic: return GM_AGENT_PRAGMATIC_PERSONALITY
        case .alternative: return GM_AGENT_ALTERNATIVE_PERSONALITY
        case .conservative: return GM_AGENT_CONSERVATIVE_PERSONALITY
        }
    }

    static var lenses: [AgentGmkPersonality] {
        allCases.filter { $0 != .compliant }
    }
}
