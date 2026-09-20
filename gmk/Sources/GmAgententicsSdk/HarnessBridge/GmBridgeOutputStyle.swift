import Foundation

extension GmBridgeOutputStyle {

    /// The primarch identity, shipped as an APPENDING output style.
    ///
    /// `keepCodingInstructions: true` is the only way a plugin can ADD to Claude
    /// Code's system prompt; nil omits the key, defaults to `false` and strips the
    /// built-in engineering instructions. `forceForPlugin: true` is what applies
    /// it, since no `settings.json` is emitted to select it. No `displayName` — it
    /// would emit a frontmatter `name:` disagreeing with the file stem. The body is
    /// `instruction.text`, so style, agent file and native session cannot drift.
    public static let all: [File] = [
        File(
            name: "primarch",
            description:
                "Green Mountain Bot primarch: leads with the answer, keeps the proof.",
            keepCodingInstructions: true,
            forceForPlugin: true,
            body: AgentGmkSessionProfile.primarch.instruction.text
        )
    ]
}
