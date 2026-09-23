import Foundation

/// COMPUTED, NOT A CONSTANT: the phase index at the bottom is built from
/// `GmBridgeSkillPhase.all`, so a phase skill is cited here automatically and one
/// removed stops being cited.
///
/// See `GM_CONCEPT_GMCC`.
var GM_CONCEPT_CDE: String {
    """
    # CDE — Contextual Development Environment

    The harness: toolkit and runtime where agents coordinate, persist work, and reach tools and subagents.

    ## The harness surface

    - **Skills** — named workflows that encapsulate whole steps; plugin-resident; reach for one when it matches the entire task.
    - **Commands** — direct harness operations (`/fast`, `/config`, `!bash`); use for quick one-offs.
    - **Subagents** — delegated context for multi-step work; each has its own tool budget. A subagent's RECORDED output (files, database rows, artifacts) survives; its closing message is receipt only.
    - **Hooks** — lifecycle automation the harness runs on detected conditions (changes, failures, pushes); configured in `settings.json`.
    - **MCP tools** — typed read/write surface for dope, kbites, project record, wire protocol. PRIMARY write path.

    ## Tool discipline

    Prefer typed tools where they exist. Use native READ / EDIT / WRITE over bash equivalents. Batch independent calls in one turn (they run in parallel). Fall back to bash only when pipes, globs, or unexposed commands are needed. Search before reading whole files.

    ## Delegation

    Spawn a subagent when: work spans multiple steps, tool set is narrower than primary context, or work can run in parallel. Keep it in primary when the result decides the next step. Context is finite and recurring — everything loaded stays loaded; do not re-derive what is established.

    ## Workflows live elsewhere

    Specific workflows (lifecycle, phases, roles) are configured outside the harness. The CDE is the general environment they run inside.

    ## The workflow phases

    Each RPIR phase is a skill of its own, carrying that phase's calls and its gate. Load the one the run has reached; do not load the walk:

    \(GmBridgeSkillPhase.index)
    """
}
