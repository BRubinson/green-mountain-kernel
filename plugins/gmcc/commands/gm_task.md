---
name: gm_task
description: Load GMCC session context (via pen reads), then just do the task. Writes no prompt rows or report summaries — GMCC persistence happens only via the automatic file-change hook, an optional doper briefing for meaty tasks, or an explicitly requested retroactive write-back.
argument-hint: <task / request>
disable-model-invocation: true
allowed-tools: Bash(gmcc_hook:*)
---

# GM-CDE Task (Context-loaded, no ceremony)

You are executing a task with full GMCC context loaded, but **without** the
prompt-authoring ceremony of `/gm_bot`. You load context, you do the work,
and you leave the prompt/report surface of the daemon db untouched — unless
the user explicitly asks you to write something back.

The contract that distinguishes this command from `/gm_bot`:

> **Default behavior authors NOTHING in the daemon db or the ckfs.**
> No prompt row, no clarify/arch/explore/review summaries, no artifact
> registrations. Editing the user's *repository* files is the task and is
> expected — and those Edit/Write changes are captured automatically by the
> plugin's PostToolUse hook (unattributed when no prompt is active). That
> capture is harness plumbing and needs nothing from you. The two sanctioned
> exceptions: the optional doper briefing below, and an explicitly requested
> retroactive write-back (final section).

SessionStart injects the pen sheet. The pen tools are typed, so there are no
flags to guess; `gmcc_hook verbs --json` lists every MessageType the daemon
serves for the reads that have no pen tool.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

Current session state (inlined at invocation — one shell, because the two
list calls need the session uuid the first call returns):

!`U=$(gmcc_hook context ensure | sed -n 's/.*"session_uuid" : "\(.*\)".*/\1/p'); echo "session_uuid=$U"; gmcc_hook call PROMPT_LIST --json "{\"session_uuid\":\"$U\",\"with_reports\":true}"; gmcc_hook call DOPE_LIST --json "{\"session_uuid\":\"$U\"}"`

If that errored with "daemon unreachable", self-heal:
`bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then re-run it (the next
client call brings the daemon back up).

---

## Phase 1: Deeper Context (read-only, on demand)

The inlined state above covers the default scope: every prompt's
clarification/architecture/exploration/review stubs, change summary, and dope
scopes. Pull detail only where the task needs it:

- `mcp__plugin_gmcc_pen__clarify_get` / `arch_get` / `explore_get` /
  `review_get` for full detail on the prompts that matter (each narrows —
  pass a rating window or an option/change uuid rather than pulling
  everything). `gmcc_hook call SEARCH --json '{"query":"<topic>","session_uuid":"<U>","limit":20}'`
  finds prior work across prompts — do not grep the ckfs for it.
  `gmcc_hook call ARTIFACT_LIST --json '{"prompt_uuid":"<P>"}'` shows files
  registered against a prompt.
- **Dope on demand.** `mcp__plugin_gmcc_pen__dope_search` (FTS5, dot-path
  hits) then targeted `mcp__plugin_gmcc_pen__dope_get` with `code` — never
  full-tree dumps.
- **KBites on demand.** If a task clearly benefits from a kbite:
  `mcp__plugin_gmcc_pen__kbite_search` for ranked stubs, read the briefs, then
  `mcp__plugin_gmcc_pen__kbite_file_get` for the content that matters
  (`gmcc_hook call KBITE_GET --json '{"code":"{name}"}'` for the overview;
  purpose file at `{kbite_root}/{name}/KBITE_PURPOSE.md`, kbite_root from
  `gmcc_hook paths --json`). Prefer kbites already active for the session. Do
  not block on an AskUserQuestion for kbite selection — only load what the
  task needs.

### Optional: session-owned briefing for meaty tasks

For a substantial task that would benefit from real context assembly,
delegate it to the doper instead of hand-searching (this is a sanctioned
db write — `agent_briefing` rows are context plumbing, not work records).
There is no prompt row, so the briefing is SESSION-owned:

```bash
gmcc_hook call BRIEFING_OPEN --json '{"session_uuid":"{U}","briefing_for_step":"initial"}'
```

The response carries the briefing uuid.

```
Task tool:
  subagent_type: gmcc:doper
  prompt: |
    Owner session uuid: {U}
    Step: initial
    Topic: {one line — what this task is about}
```

Gate on it BY UUID as the spawn's very next call:
`mcp__plugin_gmcc_pen__briefing_get --briefing-uuid {B}`, where {B} came from
your own BRIEFING_OPEN response; poll it until it reads ready. Then work from
its ref set (dope dot-paths, kbite files; briefings are opinion-free ref
pre-selections) plus your own deeper pulls. `wait_for_briefing` is the
prompt-owned form and does not apply here — this briefing hangs off the
session, and you hold its uuid anyway.

---

## Phase 2: Do the Task

Execute the user's request directly in the primary context using
Read / Edit / Write / Grep / Glob / Bash (and Task for subagents if a search
genuinely warrants it).

- Edit the user's repository files freely — that is the work. The
  PostToolUse hook captures those changes automatically; do not add manual
  `file_change_add` bookkeeping on top of it.
- **Do not** author GMCC record entities (no prompt rows, no report summaries, no
  artifact registrations, nothing under `$GMCC_CKFS_ROOT`).
- If the task balloons in scope and would benefit from the full clarify → plan →
  review pipeline, suggest the user re-run it under `/gm_bot` (or `/gm_bot_rpi`
  / `/gm_bot_team`) rather than reaching for GMCC bookkeeping here.

When finished, give a concise summary: what you did, files touched, anything
deferred. Do **not** persist that summary anywhere — it stays in the chat.

---

## Retroactive Write-Back (only on explicit request)

Skip this section entirely unless the user, at some point in the conversation,
explicitly asks you to record the work (e.g. "save that to the session",
"record the files you changed", "write this up as a prompt"). Honor exactly
what they ask for; do not volunteer writes.

Two write targets are supported.

### A. Record / attribute changed files

Edit/Write-driven changes were already captured automatically (unattributed).
`mcp__plugin_gmcc_pen__file_change_add` is needed only for:

- files changed through Bash (scripts, generators, `git mv`) — the hook sees
  the Bash call, not the paths inside it:
  `file_change_add(path: "<repo-relative path>", kind: "edit|create|delete|rename", prompt_uuid: "<U>")`
- attributing the work to a prompt row (e.g. one created via write-back B):
  pass `prompt_uuid` on the rows you add.

Run from inside the repo — git context is auto-detected.
`mcp__plugin_gmcc_pen__file_change_list` shows what the machine believes you
have touched.

### B. Record a prompt

Capture the task after the fact as a prompt row (no clarify pipeline is run,
so it lands as `draft`):

```bash
gmcc_hook call PROMPT_CREATE --json '{
  "session_uuid": "{U}",
  "name": "{name}",
  "backstory": "",
  "goal": "<what the task aimed to achieve>",
  "detail": "<how it was done — the specifics>",
  "command": "/gm_task"
}'
```

(Retroactive capture is the one case where the bot authors `goal`/`detail` —
it is recording work already done at the user's request, not splitting a
human prompt. For a long write-up put the whole payload in a file and use
`--json-file <path>`: shell argument limits are far below the daemon's
content caps.) If you have artifacts to drop there, mkdir the memory dir at
the RETURNED `ckfs_relative_storage_path` (relative to
`gmcc_hook paths --json` → ckfs_root) — never re-derive `{seq}_{name}`
yourself; the daemon slugs the name — registering each with:

```bash
gmcc_hook call ARTIFACT_ADD --json '{"prompt_uuid":"{P}","file_path":"{abs path}","note":"..."}'
```

After any write-back, state plainly what was persisted and where.
