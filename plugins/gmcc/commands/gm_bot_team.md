---
name: gm_bot_team
description: Agent-team GMCC workflow (variant team). Dynamic workflows drive briefing+explore+clarify-open, implementation, and review-fix; four methodology personas per fan-out phase; architecture optioning with one decide step.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gmcc_hook:*)
---

# GM-CDE Bot Team (variant: team)

You are executing the **team** variant: methodology fan-outs
(conservative / aggressive / pragmatic / alternative) run as persona subagents
or inside dynamic workflows you author; the daemon machine
(`mcp__plugin_gmcc_pen__bot_next`) serves every phase's instructions and its
gate blockers. Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set, or agent teams are unavailable
(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), report the error and exit
(fallback: /gm_bot_rpi).

Then confirm the pen is actually served to this session: `mcp__plugin_gmcc_pen__*`
must be in your own tool list. Every persona in this variant records through the
pen and nothing else, so if the tools are absent no spawn can write — the fan-out
burns four agents and lands nothing. Absent pen = report it and exit; the session
must be restarted, not worked around. `claude mcp list` reporting the server
healthy does NOT settle it: that check spawns a fresh probe process, while what
matters is whether THIS session registered the tools.

## Arguments

Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
`--command /gm_bot_team` at create and `--variant team` at start/resume.

## Variant contract (team)

- **Workflow-driven phases** — briefing + explore + clarify-open,
  implementation, and review-fix run as dynamic workflows you HAND-AUTHOR,
  guided by `mcp__plugin_gmcc_pen__bot_next` output. Script code is pure
  orchestration: it never touches the db directly — every read/write happens inside agent()
  subagents, through the MCP pen tools and nothing else. Capture is the
  PostToolUse hook alone — there is no gate-time backstop, so a write the
  hook cannot see is not recorded at all.
- **Explore** — four `gmcc:code-explorer` personas, each opening its OWN
  summary (`bot_summary`, agent_type = its methodology) and completing it.
  Findings stay unranked; calibration is cross-agent and belongs to one
  reader.
- **Clarify** — ONE `gmcc:clarifier` runs the merged pass: it reads every
  persona's findings, applies the ONE prompt-scoped calibrated rank batch,
  opens and seals the `synthesis` summary, and pens the question/note
  suite. YOU seal the suite, run the user conversation (AskUserQuestion
  mirroring the option rows) and the answers; then the care package
  (curated COPIES of ranked findings + dope/kbite refs + the
  clarified-intent blob), finalize, set-status architecting.
- **Architecture optioning** — four `gmcc:code-architect` personas each pen
  their OWN option row (`arch_option_add`). You pick the winner with
  `mcp__plugin_gmcc_pen__arch_decide` (rationale recorded; siblings rejected; offer the
  losers' best features to the user), and ONLY the selected option expands
  into change rows — persistence first, change kinds + dope refs.
- **Plan gate** — propose → user sign-off with the full persistence delta
  table → approve → implementing.
- **Review** — four `gmcc:code-quality-reviewer` personas pen finding rows,
  each rating only its own; you run the ONE calibrated rank batch across all
  of them (`mcp__plugin_gmcc_pen__review_rank` — calibration is cross-agent
  and belongs to one reader) and complete with the verdict, clarify fix
  intent with the user, run review-fix (as a workflow when the fixes fan
  out), done.

Spawn every persona by `subagent_type` — `gmcc:doper`, `gmcc:code-explorer`,
`gmcc:clarifier`, `gmcc:code-architect`, `gmcc:code-quality-reviewer` — and pass
NO spawn name. A name routes the spawn down the teammate path, where the agent
definition never binds: the persona comes up with a general tool set instead of
its own, holds no pen tools, and registers under the name rather than its type.
Resume a running persona by the agent id its spawn returned.

Spawn prompts carry ONLY the methodology, the summary uuid where the def asks
for one, and the one-line target — plus the explicit `prompt_uuid` pull line
(personas hold no activation claim). Do not paste briefings or dope dumps into
spawn prompts. There is no tear-down step.

## Error handling

Persona spawn failure → fall back to the rpi shape for that phase, say so.
A persona that reports missing pen tools is a spawn that did not bind its
definition — re-check the Pre-Flight pen line and the no-name rule; a write
the pen cannot make is a write nothing records.
Everything else (VERSION_CONFLICT, SUMMARY_ABSENT, daemon unreachable, dead
doper): `bot_workflows.md`.
