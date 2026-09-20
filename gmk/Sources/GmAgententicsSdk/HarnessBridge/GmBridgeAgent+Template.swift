import Foundation

extension GmBridgeAgent {

    static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GmBridgeAgent {

    /// Builds one agent file from the session profile it embodies.
    ///
    /// The prompt is NOT assembled here — it is `profile.instruction.text`, the
    /// same precompiled body the live `LanguageModelSession` runs on. That is the
    /// point of routing through the profile: the markdown a subagent is spawned
    /// with and the instructions a native session is given cannot drift, because
    /// there is only one assembly and both read it.
    static func file(
        _ profile: AgentGmkSessionProfile,
        name: String,
        description: String,
        model: Model? = nil,
        native: [Native] = [],
        tools: [any GmAgentTool] = []
    ) -> File {
        File(
            name: name,
            description: oneLine(description),
            model: model,
            nativeTools: native,
            mcpTools: tools.map(GmBridgeMcpTool.init),
            prompt: profile.instruction.text
        )
    }
}
