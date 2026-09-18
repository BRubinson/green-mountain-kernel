---
name: cde
description: The harness integration for agentic development
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_load_prompt, mcp__plugin_gmcc_cde__cde_set_status, mcp__plugin_gmcc_cde__cde_search_file_changes, mcp__plugin_gmcc_cde__rpir_next, mcp__plugin_gmcc_cde__rpir_open_briefing, mcp__plugin_gmcc_cde__rpir_write_brief, mcp__plugin_gmcc_cde__rpir_close_brief, mcp__plugin_gmcc_cde__rpir_load_exploration_brief, mcp__plugin_gmcc_cde__rpir_open_exploration, mcp__plugin_gmcc_cde__rpir_write_explorations, mcp__plugin_gmcc_cde__rpir_rank_explorations, mcp__plugin_gmcc_cde__rpir_complete_exploration, mcp__plugin_gmcc_cde__rpir_get_exploration, mcp__plugin_gmcc_cde__rpir_open_clarification, mcp__plugin_gmcc_cde__rpir_write_clarification_questions, mcp__plugin_gmcc_cde__rpir_write_clarification_notes, mcp__plugin_gmcc_cde__rpir_answer_clarification_question, mcp__plugin_gmcc_cde__rpir_seal_clarification, mcp__plugin_gmcc_cde__rpir_finalize_clarification, mcp__plugin_gmcc_cde__rpir_open_care_package, mcp__plugin_gmcc_cde__rpir_write_care_package, mcp__plugin_gmcc_cde__rpir_close_care_package, mcp__plugin_gmcc_cde__rpir_get_clarification, mcp__plugin_gmcc_cde__rpir_get_care_package, mcp__plugin_gmcc_cde__rpir_open_architecture, mcp__plugin_gmcc_cde__rpir_open_architecture_option, mcp__plugin_gmcc_cde__rpir_write_architecture_persistence_changes, mcp__plugin_gmcc_cde__rpir_write_architecture_field_changes, mcp__plugin_gmcc_cde__rpir_write_architecture_general_changes, mcp__plugin_gmcc_cde__rpir_summarize_architecture, mcp__plugin_gmcc_cde__rpir_propose_architecture, mcp__plugin_gmcc_cde__rpir_approve_architecture, mcp__plugin_gmcc_cde__rpir_revise_architecture, mcp__plugin_gmcc_cde__rpir_decide_architecture, mcp__plugin_gmcc_cde__rpir_get_architecture, mcp__plugin_gmcc_cde__rpir_open_review, mcp__plugin_gmcc_cde__rpir_write_reviews, mcp__plugin_gmcc_cde__rpir_rank_reviews, mcp__plugin_gmcc_cde__rpir_complete_review, mcp__plugin_gmcc_cde__rpir_resolve_review_finding, mcp__plugin_gmcc_cde__rpir_get_review, mcp__plugin_gmcc_cde__rpir_search_exploration, mcp__plugin_gmcc_cde__rpir_search_clarification, mcp__plugin_gmcc_cde__rpir_search_architecture, mcp__plugin_gmcc_cde__rpir_search_architecture_option, mcp__plugin_gmcc_cde__rpir_search_review
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

## Reference

Detail lives beside this file rather than in it — read it only when it names your situation:

- `ref/bot_workflows.md` — The workflow machine: phases, gates, who writes what, and the two write channels. Read before driving or debugging a bot/rpi/team run.
