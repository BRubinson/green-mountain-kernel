import Foundation

/// A `prompts/*.prompt.md` file — a reusable prompt body the plugin ships.
///
/// WHY THIS TYPE HAD TO EXIST. The bridge modelled skills, commands, agents,
/// hooks, scripts and every manifest, and had NO representation for the
/// `prompts/` directory at all. Two files, 502 lines, with no source — so a
/// generated plugin silently dropped both and the crunch pipeline lost the
/// bodies its agents are handed.
///
/// SEPARATE FROM `GmBridgeCommand`, though both are markdown under a directory.
/// A command is INVOKED — it takes `$ARGUMENTS`, it appears in the slash-command
/// listing, and its frontmatter grants tools. A prompt is HANDED TO an agent as
/// text. Collapsing them would put two files in the command listing that nobody
/// can usefully type, and the listing has a character budget.
public struct GmBridgePrompt: Equatable, Sendable, GmBridgeFile {

    /// The prompt's name WITHOUT the `.prompt.md` suffix.
    public var name: String

    public var body: String

    public init(name: String, body: String) {
        self.name = name
        self.body = body
    }

    /// The DOUBLE extension is the convention, not a mistake: the harness reads
    /// `prompts/<name>.prompt.md`, and a bare `.md` here would be a file nothing
    /// looks for.
    public var relativePath: String {
        "prompts/\(name).prompt.md"
    }

    public var isEmpty: Bool { body.isEmpty }

    public func contents() throws -> String? {
        guard !isEmpty else { return nil }
        return body.hasSuffix("\n") ? body : body + "\n"
    }
}
