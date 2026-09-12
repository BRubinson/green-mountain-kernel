---
name: gm_bot
description: Lightweight GMCC workflow (variant bot). Authors a prompt into the current session, enters the daemon's workflow machine, and runs every phase in primary context — the only spawn is the haiku doper briefing.
argument-hint: <prompt-name|seq> <task/prompt content>
disable-model-invocation: true
allowed-tools: Bash(gmcc_hook:*)
---

# GM-CDE Bot (variant: bot)

You are executing the **bot** variant: every phase in primary context, no
subagents except the `gmcc:doper` briefing pass. The lifecycle lives in the
daemon — `mcp__plugin_gmcc_pen__bot_next` tells you the current phase, its
instructions, and what blocks the next one. Follow it; this file carries only the variant
contract. Canonical reference: `skills/gmcc/ref/bot_workflows.md`.

## Pre-Flight

If `$GMCC_BOOTED` is not set:

```
[GMB] ERROR: GMCC not booted — run /gmcc_boot for diagnostics.
```

Exit without proceeding.

Then confirm `mcp__plugin_gmcc_pen__*` is in your own tool list. This variant
pens its rows from primary context and spawns the doper, so an unserved pen
means nothing this run produces can be recorded. Absent pen = report it and
exit; the session must be restarted, not worked around. `claude mcp list`
reporting the server healthy does NOT settle it — that check spawns a fresh
probe process, while what matters is whether THIS session registered the tools.

## Arguments

ONE CALL STARTS A RUN. `mcp__plugin_gmcc_pen__prompt_init` takes what the user
typed and does the rest: it resolves session and project from the working
directory and git branch, matches the selector, enters the workflow machine, and
returns the uuid bundle, the derived phase, that phase's instructions, the NEXT
phase's expected agents, the gate blockers, and the briefing's state. There is
nothing to read afterwards to know what to do — no ref doc, no command file, no
source file.

- **Numeric seq, code, name, or a unique fragment of one** → resume:
  `prompt_init(selector: "10", variant: "bot")`. The reply's
  `resolution.created` says whether this is a NEW prompt or a RESUMED one, and
  an ambiguous selector comes back with `candidates` and touches nothing — pick
  one and call again rather than guessing.
- **Slug name + content** → create, by passing the same call the content
  (STAY TRUE: the whole passed prompt goes to `detail` verbatim; goal and
  backstory are never authored):
  `prompt_init(selector: "{name}", variant: "bot", create: true, name: "{name}", detail: "<the user's prompt, verbatim>")`.
  Creation requires `create`, `name` AND `detail` together, so a mistyped
  selector can never silently become a new prompt. Then
  `mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory`, taking the
  path verbatim from the response.
- **No args** → AskUserQuestion for the prompt content.

If the reply carries `warnings`, read them before spawning anything: a session
with no `claude_session_binding` row records no file changes at all, and the run
will look like it worked.

## Variant contract (bot)

- Haiku doper briefing, then YOU run exploration in context: open your
  `general` summary (`mcp__plugin_gmcc_pen__bot_summary --agent-type
  general`), pen the finding rows yourself, complete it. The pen is loaded
  for you too — running the phase in the primary's own context is no reason
  to record it any other way. Every read and every write this variant needs
  is a pen tool, the primary's four included: you are the one reader here,
  so the rank, the decide, the seals and the status moves are yours to make.
- Clarification: you run the merged clarifier pass in context — rank
  prompt-wide from your own self-ratings, open + complete the `synthesis`
  summary, author the questions/notes, seal, run the user conversation
  (AskUserQuestion mirroring the option rows), answer rows, finalize. NO
  care package — the clarified picture stays in your context.
- Architecture: design in context; persistence rows first (change kinds +
  dope refs); propose → user sign-off with the full persistence delta
  table → approve → set-status implementing.
- Implement in context (persistence first; capture is the PostToolUse hook
  alone), review in context against your general review summary, complete
  with a verdict, run the fix loop, set-status done.

Every step's exact commands come from `mcp__plugin_gmcc_pen__bot_next` —
trust the machine, never skip its gate blockers.
