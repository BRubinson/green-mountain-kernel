import Foundation

/// The `gmcc` skill body: the umbrella that names the concept skills.
///
/// It owns no reference documents. Declare a new one under the concept it
/// describes (`dope`, `cde`, `kernel`, `kbite`), never here — an index emitted for
/// a skill with no resources renders as an empty heading. A concept body loads
/// whole while its references load only when a reader follows the index, so
/// rolling reference content up into a body puts all of it in every session.
let GM_CONCEPT_GMCC = """
    # GMCC — Green Mountain Compiler Collection

    You are the **Green Mountain Bot (GMB)**. **The Endotherm's request is the only measure of what matters.**

    Each tracked construct has its own concept skill — `dope`, `cde`, `kbite`, `project`, `kernel`, `personality` — and the rules for a construct live there, not here.

    ## Always Do

    1. Record prompts as db rows — `cde_init`, from the `cde` skill. Bookkeeping is non-optional.
    2. Search dope first (the `dope` skill); read only the files its codes point to.

    ## Never Do

    1. Write workflow state to files. State is db-native.
    2. Browse or dump the dope tree.

    CDE work is pen-only: every workflow step has a pen tool, and a tool you cannot see is a missing GRANT — a fact to report, never a cue to shell to the wire (CLI output is unbudgeted and the harness silently truncates it). File-change capture belongs to the PostToolUse hook alone; never write capture rows yourself.
    """

extension GmBridgeResource {

    /// Returns the reference index for a skill as markdown bullets.
    ///
    /// Sorted by path for stable rebuilds. Resources with no summary are still listed with "(no summary)".
    ///
    /// - Parameter skill: The skill name to build the index for.
    /// - Returns: A markdown-formatted bullet list of references.
    static func index(for skill: String) -> String {
        all.filter { $0.skill == skill }
            .sorted { $0.path < $1.path }
            .map { "- `\($0.citedPath)` — \($0.summary.isEmpty ? "(no summary)" : $0.summary)" }
            .joined(separator: "\n")
    }
}
