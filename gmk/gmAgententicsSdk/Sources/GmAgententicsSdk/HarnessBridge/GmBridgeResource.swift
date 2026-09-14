import Foundation

/// A plain file that lives INSIDE a skill directory, beside its `SKILL.md`.
///
/// WHY THIS TYPE HAD TO EXIST. `GmBridgeSkill.File.relativePath` is hard-coded
/// to `skills/<name>/SKILL.md`. That is correct for the skill itself and makes
/// the four files under `skills/gmcc/ref/` STRUCTURALLY unrepresentable — not
/// merely unwritten. No amount of filling in skill bodies could have produced
/// them, because the skill type can only name one path. This is the smallest
/// type that closes that hole: a path and some bytes.
///
/// DELIBERATELY NOT A SKILL. A skill carries frontmatter, tool grants, a model
/// and an invocation contract; a reference document carries none of that and
/// gets loaded by being READ, not by being invoked. Modelling these as skills
/// would put four more entries in the skill listing — which has a character
/// budget — for four files nothing invokes.
public struct GmBridgeResource: Equatable, Sendable, GmBridgeFile {

    /// The skill directory this belongs to (`gmcc`), not a path.
    public var skill: String

    /// One line: WHEN a reader should open this, not what it contains.
    ///
    /// It exists so the skill can carry an INDEX of its reference documents
    /// rather than leaving them orphaned on disk. A file the skill never names
    /// is a file the model never learns exists — which is exactly what these
    /// four were before v30: 38KB sitting beside a 1.3KB SKILL.md with nothing
    /// pointing at them.
    public var summary: String

    /// The path BENEATH the skill directory (`ref/bot_workflows.md`).
    ///
    /// Carries its own subdirectory rather than assuming `ref/`, because the
    /// harness places no constraint on the layout inside a skill and the next
    /// one may not be a reference document.
    public var path: String

    public var body: String

    public init(skill: String, path: String, summary: String = "", body: String) {
        self.skill = skill
        self.path = path
        self.summary = summary
        self.body = body
    }

    /// `ref/bot_workflows.md` — the path a skill body cites, relative to the
    /// skill's own directory, which is how the harness resolves a sibling file.
    public var citedPath: String { path }

    public var relativePath: String {
        "skills/\(skill)/\(path)"
    }

    public var isEmpty: Bool { body.isEmpty }

    public func contents() throws -> String? {
        guard !isEmpty else { return nil }
        // Verbatim, with a guaranteed trailing newline. NO frontmatter is
        // synthesised: these are documents a skill points at, and inventing
        // metadata for them would change what the reader sees.
        return body.hasSuffix("\n") ? body : body + "\n"
    }
}
