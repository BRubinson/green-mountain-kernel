// The FoundationModels session built over a precompiled profile.

import Foundation
import FoundationModels

@available(macOS 27, *)
extension AgentGmkSessionProfile {

    /// Language model profile with fixed instructions and all tools.
    ///
    /// A single precompiled instruction body for the whole session, allowing the
    /// framework to keep its key-value cache.
    /// - Returns: A language model profile for this agent session.
    func languageModelProfile() -> some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instruction.text)
            GmAgentTools.all
        }
    }
}
