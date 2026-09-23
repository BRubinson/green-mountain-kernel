import Foundation

extension GmBridgeAgent {

    /// Collapses a string to a single line with normalized whitespace.
    ///
    /// - Parameter value: The string to collapse.
    /// - Returns: The string with newlines converted to spaces and trimmed.
    static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GmBridgeAgent {

    /// Builds one agent file from the session profile it embodies.
    ///
    /// The prompt is sourced from `profile.instruction.text`, the precompiled body
    /// that the live `LanguageModelSession` runs on. This routing ensures that the
    /// markdown a subagent is spawned with and the instructions a native session
    /// is given cannot drift, because there is only one assembly and both read it.
    ///
    /// - Parameters:
    ///   - profile: The session profile containing the instruction and configuration.
    ///   - name: The agent file name.
    ///   - description: The agent description; collapsed to one line.
    ///   - model: The model to use; nil for the profile's default.
    ///   - native: Native tools to include; empty by default.
    ///   - tools: MCP tools to include; empty by default.
    /// - Returns: The agent file ready to register.
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
            prompt: profile.instruction.text,
            model: model,
            nativeTools: native,
            mcpTools: tools.map(GmBridgeMcpTool.init)
        )
    }
}
