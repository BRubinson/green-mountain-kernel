// Which Claude model and effort level each agent role runs on.

import Foundation
import ClaudeForFoundationModels

let GM_AGENT_PLACEHOLDER_AUTH: AuthMode = .apiKey("gm-placeholder")

@available(GmAgentOs 1.0, *)
extension AgentGmkDirective {

    func languageModel(auth: AuthMode = GM_AGENT_PLACEHOLDER_AUTH) -> ClaudeLanguageModel {
        switch self {
        case .primarch:
            return ClaudeLanguageModel(name: .opus5, auth: auth, fixedEffort: .high)
        case .briefer:
            return ClaudeLanguageModel(name: .haiku4_5, auth: auth)
        case .explorer:
            return ClaudeLanguageModel(name: .sonnet5, auth: auth, fixedEffort: .medium)
        case .intentClarifier:
            return ClaudeLanguageModel(name: .opus5, auth: auth, fixedEffort: .high)
        case .architect:
            return ClaudeLanguageModel(name: .opus5, auth: auth, fixedEffort: .high)
        case .implementor:
            return ClaudeLanguageModel(name: .sonnet5, auth: auth, fixedEffort: .high)
        case .reviewer:
            return ClaudeLanguageModel(name: .opus5, auth: auth, fixedEffort: .high)
        case .kbiteChewer:
            return ClaudeLanguageModel(name: .sonnet5, auth: auth, fixedEffort: .high)
        }
    }
}
