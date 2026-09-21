---
name: cde
description: The harness integration for agentic development
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_prompt, mcp__plugin_gmcc_cde__cde_rpir_briefing, mcp__plugin_gmcc_cde__cde_rpir_explore, mcp__plugin_gmcc_cde__cde_rpir_clarify, mcp__plugin_gmcc_cde__cde_rpir_architecture, mcp__plugin_gmcc_cde__cde_rpir_review, mcp__plugin_gmcc_cde__cde_rpir_search
---

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

- `gmcc:cde_rpir_briefing` — The BRIEFING phase: the prompt's opinion-free orientation page, sealed before anything else moves.
- `gmcc:cde_rpir_explore` — The EXPLORE phase: one finding list per explorer, written as the codebase is read.
- `gmcc:cde_rpir_clarify_open` — The CLARIFY_OPEN phase: rank the whole record, seal the synthesis, author the question suite.
- `gmcc:cde_rpir_clarify_user` — The CLARIFY_USER phase: the one conversation with the Endotherm, and its recorded answers.
- `gmcc:cde_rpir_care_package` — The CARE_PACKAGE phase: the clarified intent curated into the package architecture reads.
- `gmcc:cde_rpir_arch_options` — The ARCH_OPTIONS phase: rival plans written in parallel, one per lens.
- `gmcc:cde_rpir_architecture` — The ARCHITECTURE phase: the plan, persistence changes first and general changes built over them.
- `gmcc:cde_rpir_plan_gate` — The PLAN_GATE phase: the Endotherm approves the plan before a stone is cut.
- `gmcc:cde_rpir_implement` — The IMPLEMENT phase: the approved change landed, only in the files the plan names.
- `gmcc:cde_rpir_review` — The REVIEW phase: what was built judged against what was asked.
- `gmcc:cde_rpir_review_fix` — The REVIEW_FIX phase: the settled findings resolved and the rest ruled on.
- `gmcc:cde_rpir_done` — The DONE phase: the prompt closed and the activation claim released.
