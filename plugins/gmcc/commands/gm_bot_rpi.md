---
name: gm_bot_rpi
description: Subagent GMCC workflow (variant rpi). One general-persona subagent per phase adopts every methodology's goals at once; up to 2 implementation subagents; the care package carries clarified intent into architecture.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gmcc_hook:*)
---

# GM-CDE Bot RPI (variant: rpi)

You are executing the **rpi** variant: ONE general-persona subagent per
phase (it adopts all four methodology lenses at once — summary/agent type
`general`), plus up to 2 implementation subagents. The lifecycle lives in
the daemon — `mcp__plugin_gmcc_pen__bot_next` serves each phase's
instructions and gates.
Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

Exit without proceeding.

Then confirm `mcp__plugin_gmcc_pen__*` is in your own tool list. Every subagent
this variant spawns records through the pen and nothing else, so an unserved pen
means no spawn can write. Absent pen = report it and exit; the session must be
restarted, not worked around. `claude mcp list` reporting the server healthy does
NOT settle it — that check spawns a fresh probe process, while what matters is
whether THIS session registered the tools.

## Arguments

Same as /gm_bot (resume by seq / create by slug — STAY TRUE), with
`--command /gm_bot_rpi` at create and `--variant rpi` at start/resume.

## Variant contract (rpi)

- Haiku doper briefing, then spawn ONE `gmcc:code-explorer` with
  `Methodology: general` — it opens its own summary via the pen tools,
  writes its rows, completes it. No 4-spawn batches; findings stay unranked
  at the end of explore.
- Clarification: spawn ONE `gmcc:clarifier` for the merged pass — it ranks
  prompt-wide, opens and seals the `synthesis` summary, and pens the
  question/note suite. You seal the suite, run the user conversation,
  answer, then build the CARE PACKAGE (package-open → package-add refs →
  package-complete with the clarified intent), finalize, set-status
  architecting.
- Architecture: ONE `gmcc:code-architect` (general, solo mode —
  proposal-only); you persist the rows (persistence first), propose →
  sign-off (full persistence delta table) → approve → implementing.
- Implement with up to 2 implementation subagents (persistence first;
  capture is the PostToolUse hook alone). Review: ONE `gmcc:code-quality-reviewer`
  (general); you complete with the verdict and run the fix loop; done.

Spawn prompts carry ONLY: the methodology (`general`), the summary uuid
where the def asks for one, and the one-line target. Do not paste briefings
or dope dumps into a spawn prompt — agents pull their own context through
the pen tools.
