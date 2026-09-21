// The FoundationModels session built over a precompiled profile.

import Foundation
import FoundationModels

@available(macOS 27, *)
extension AgentGmkSessionProfile {

    /// The session profile for this identity: one fixed instruction body and the
    /// full tool surface. The caller picks the model.
    ///
    /// There is no `DynamicInstructions` here any more. The body is a single
    /// precompiled string, so the framework sees the same instructions for the
    /// whole session and its key-value cache survives.
    func languageModelProfile() -> some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instruction.text)
            GmAgentTools.all
        }
    }
}
