import Foundation

/// A plain file that lives INSIDE a skill directory, beside its `SKILL.md`.
///
/// `GmBridgeSkill.File.relativePath` is hard-coded to `skills/<name>/SKILL.md`,
/// so a reference document beside it is otherwise unrepresentable. Deliberately
/// not a skill: a skill carries frontmatter, tool grants and an invocation
/// contract, while a reference is loaded by being READ, and modelling these as
/// skills spends entries in the character-budgeted skill listing on files nothing
/// invokes.
struct GmBridgeResource: Equatable, Sendable, GmBridgeFile {

    /// The skill directory this belongs to (`gmcc`), not a path.
    var skill: String

    /// One line: WHEN a reader should open this, not what it contains.
    ///
    /// It exists so the skill can carry an INDEX of its reference documents rather
    /// than leaving them orphaned on disk. A file the skill never names is a file
    /// the model never learns exists.
    var summary: String

    /// The path BENEATH the skill directory (`ref/bot_workflows.md`).
    ///
    /// Carries its own subdirectory rather than assuming `ref/`, because the
    /// harness places no constraint on the layout inside a skill and the next
    /// one may not be a reference document.
    var path: String

    var body: String

    init(skill: String, path: String, summary: String = "", body: String) {
        self.skill = skill
        self.path = path
        self.summary = summary
        self.body = body
    }

    /// `ref/bot_workflows.md` — the path a skill body cites, relative to the
    /// skill's own directory, which is how the harness resolves a sibling file.
    var citedPath: String { path }

    var relativePath: String {
        "skills/\(skill)/\(path)"
    }

    var isEmpty: Bool { body.isEmpty }

    func contents() -> String? {
        guard !isEmpty else { return nil }
        // Verbatim, with a guaranteed trailing newline. NO frontmatter is
        // synthesised: these are documents a skill points at, and inventing
        // metadata for them would change what the reader sees.
        return body.hasSuffix("\n") ? body : body + "\n"
    }
}
