// The FoundationModels session built over a precompiled profile.

import Foundation
import FoundationModels
import ClaudeForFoundationModels

@available(GmAgentOs 1.0, *)
extension AgentGmkSessionProfile {

    /// The session profile for this identity: one fixed instruction body, the
    /// full tool surface, and the model the role runs on.
    ///
    /// There is no `DynamicInstructions` here any more. The body is a single
    /// precompiled string, so the framework sees the same instructions for the
    /// whole session and its key-value cache survives.
    func languageModelProfile(
        auth: AuthMode = GM_AGENT_PLACEHOLDER_AUTH
    ) -> some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instruction.text)
            GmAgentTools.all
        }
        .model(directive.languageModel(auth: auth))
    }
}
