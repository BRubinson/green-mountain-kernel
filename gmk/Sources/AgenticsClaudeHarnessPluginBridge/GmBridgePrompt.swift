import Foundation

/// A `prompts/*.prompt.md` file — a reusable prompt body the plugin ships.
///
/// Separate from `GmBridgeCommand` though both are markdown under a directory: a
/// command is INVOKED, taking `$ARGUMENTS` and granting tools from its
/// frontmatter, while a prompt is HANDED TO an agent as text. Collapsing them
/// would put files in the slash-command listing that nobody can usefully type,
/// and that listing has a character budget.
struct GmBridgePrompt: Equatable, Sendable, GmBridgeFile {

    /// The prompt's name WITHOUT the `.prompt.md` suffix.
    var name: String

    var body: String

    /// Creates a prompt from a name and body.
    /// - Parameters:
    ///   - name: The prompt's name without the `.prompt.md` suffix.
    ///   - body: The markdown body text of the prompt.
    init(name: String, body: String) {
        self.name = name
        self.body = body
    }

    /// The DOUBLE extension is the convention, not a mistake: the harness reads
    /// `prompts/<name>.prompt.md`, and a bare `.md` here would be a file nothing
    /// looks for.
    var relativePath: String {
        "prompts/\(name).prompt.md"
    }

    var isEmpty: Bool { body.isEmpty }

    /// Returns the prompt body with a trailing newline, or nil if empty.
    /// - Returns: The prompt body ending with a newline, or nil if the body is empty.
    func contents() -> String? {
        guard !isEmpty else { return nil }
        return body.hasSuffix("\n") ? body : body + "\n"
    }
}
