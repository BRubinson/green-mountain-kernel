import Foundation

/// The `gmcc` skill body.
///
/// COMPUTED, NOT A CONSTANT, and the reason is the reference index at the
/// bottom: it is BUILT FROM `GmBridgeResource.all`, so a reference document
/// added to the bridge appears in the skill automatically and one that is
/// removed stops being cited. Hand-listing them is how four files came to sit
/// beside this skill with nothing pointing at them — 38KB the model never
/// learned existed, because a file on disk is not a file in context.
///
/// PROGRESSIVE DISCLOSURE IS THE POINT. This body stays short — it is loaded
/// into every session that boots gmcc, and the skill listing has a character
/// budget. The reference documents are 38KB and are loaded only when a reader
/// follows the index. Rolling their content UP into this file would put all of
/// it in every session; leaving them uncited put none of it anywhere. The index
/// is the middle: cheap to carry, and it names the door.
var GM_CONCEPT_GMCC: String {
    """
    # GMCC — Green Mountain Compiler Collection

    You are the **Green Mountain Bot (GMB)**. **The Endotherm's request is the only measure of what matters.**

    ## DOPE — Domain Optimized Project Essence

    DOPE is the project's model of itself: scopes, domains, entities, and the cogs describing what this repo IS MADE OF.

    The `.gmcc/` tree is authoritative at boot; sessions boot-sync their dope scope from it. The db is authoritative for granular edits afterward. Publish changes with `dope_update_session`.

    ## Access: Dot-Path Codes

    Dope refs are DOT-PATH CODES (`domain.entity.property`), never uuids or file paths.

    - Search the dope tree first — `dope_search_session`, or `dope_search_global` to look across every project
    - Take the codes that hit
    - Adjacent browsing and full-tree dumps are FORBIDDEN
    - Reach for dope before reading files

    ## Always Do

    1. Record prompts as db rows — `cde_init`, from the `cde` skill. Bookkeeping is non-optional.
    2. Search dope first; read only the files codes point to.

    ## Never Do

    1. Write workflow state to files. State is db-native.
    2. Browse or dump the dope tree.

    ## Reference

    Detail lives beside this file rather than in it — READ THE ONE YOU NEED, not all of them:

    \(GmBridgeResource.index(for: "gmcc"))

    CDE work is pen-only: every workflow step has a pen tool, and a tool you cannot see is a missing GRANT — a fact to report, never a cue to shell to the wire (CLI output is unbudgeted and the harness silently truncates it). File-change capture belongs to the PostToolUse hook alone; never write capture rows yourself.
    """
}

extension GmBridgeResource {

    /// The reference index for one skill, as markdown bullets.
    ///
    /// Sorted by path so the skill body is stable across regenerations — an
    /// unordered index makes every rebuild look like a content change.
    /// A resource with no `summary` is still listed: an unexplained door beats a
    /// hidden one, and the blank is visible pressure to write the line.
    public static func index(for skill: String) -> String {
        all.filter { $0.skill == skill }
            .sorted { $0.path < $1.path }
            .map { "- `\($0.citedPath)` — \($0.summary.isEmpty ? "(no summary)" : $0.summary)" }
            .joined(separator: "\n")
    }
}
