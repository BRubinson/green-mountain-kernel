import Foundation

extension GmBridgeOutputStyle {

    /// The primarch identity, shipped as an APPENDING output style.
    ///
    /// `keepCodingInstructions: true` is the whole reason this file stopped
    /// being empty. A plugin has no other way to ADD to Claude Code's system
    /// prompt: there is no settings key for it, `--append-system-prompt` is a
    /// CLI flag a plugin cannot set, and a subagent body REPLACES the system
    /// prompt rather than extending it. Leaving this nil would omit the key and
    /// silently default to `false`, stripping the built-in software-engineering
    /// instructions — which is the exact failure this style was created to undo.
    ///
    /// `forceForPlugin: true` is what APPLIES it. `settings.json` is no longer
    /// emitted at all (its only key was dropped in the same change), so nothing
    /// else survives to select this style. Without the flag it would sit on disk
    /// inert until someone chose it by hand on every machine.
    ///
    /// THE BODY IS NOT RETYPED HERE. It is `instruction.text` — the same
    /// precompiled string `GmBridgeAgent.file()` hands the agent markdown, and
    /// the same one a live `LanguageModelSession` runs on. One authoring site is
    /// what stops the style, the agent file and the native session from drifting
    /// into three descriptions of one identity.
    ///
    /// ONLY THE PRIMARCH GETS ONE. An output style reaches the main conversation
    /// and nothing else; a subagent runs its own body as its system prompt and
    /// has never carried the engineering instructions. That is the intended
    /// split, not a gap — explore, brief, architect and review stay as they are.
    /// NO `displayName`, DELIBERATELY. Setting it emits a frontmatter `name:`
    /// key, and "the file name becomes the style name UNLESS you set name in the
    /// frontmatter" — so a pretty display name would make the style's real name
    /// `GMB Primarch` while the file stem and the `outputStyles` entry in
    /// plugin.json both said `primarch`. Three spellings of one identifier, with
    /// `force-for-plugin` masking the disagreement by applying the style anyway.
    /// Omitting it makes all three `primarch` by construction.
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
