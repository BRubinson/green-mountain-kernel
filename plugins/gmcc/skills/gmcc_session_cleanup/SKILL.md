---
name: gmcc_session_cleanup
description: GM-CDE session-scoped cleanup auditor. Audits ONLY the current session — its prompts/ artifact tree on disk vs the daemon db rows (prompt stubs, artifact pointers, file changes) — and interactively resolves each finding with the user.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Session Cleanup Skill

Audits the **current session** — the artifact tree at the session's
artifact home (`$GMCC_CKFS_ROOT/{ckfs_relative_storage_path}`, the relative
path on the session row) cross-checked against the daemon db rows
(`SESSION_GET`, `PROMPT_LIST`, the pen's `prompt_get` and `file_change_list`,
`ARTIFACT_LIST`) — and interactively resolves each finding.

This is the **session-scoped counterpart** to `gmcc_cleanup` (the
`/gmcc_environment_cleanup` command). The environment auditor deliberately
**excludes** the running session's paths from its walk, so the inside of
the active session is never inspected there. This skill fills that gap: it
looks *only* at the current session and never walks siblings or the
broader `$GMCC_CKFS_ROOT`.

---

## When to Use

- After manually editing/deleting files inside the session's `prompts/` folder.
- When artifact pointers dangle or `prompt_get` shows artifacts that aren't on disk.
- Periodically, to keep the active session's disk and db in sync.

---

## Scope (hard boundary)

**Walk ONLY the session's artifact home + this session's db rows.** Never recurse
into `$GMCC_CKFS_ROOT` broadly, never inspect sibling sessions, never touch
`_archive/`. Db reads go through the pen tools or `gmcc_hook call <TYPE>`;
repairs are the matching write verbs or filesystem moves within the session.

---

## What Counts as Non-Compliant

### (a) Prompt folder ↔ prompt row integrity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Missing memory/ dir | prompt row exists but `prompts/{seq}_{name}/memory/` doesn't | `mkdir -p` it (default) |
| Orphan prompt folder | `prompts/{seq}_{name}/` on disk but no row with that `seq` in `PROMPT_LIST` | If it contains a yaml triad → archive to cold storage; if memory/-only → flag for user (archive or leave) |
| Pre-daemon yaml files | `*_data.gmcc.yaml` / `*_initial.yaml` / `*_clarified.yaml` inside a prompt folder, or `session_data.gmcc.yaml` / `gmcc_session_file_index.yaml` at the session root | Archive to `_archive/cold_storage/` (default) — nothing reads these. Or skip |
| Loose file at prompts/ root | any file directly under `prompts/` (not in a `{seq}_{name}/` folder) | Move into the correct prompt folder, or archive to cold storage |
| Folder/row name drift | on-disk folder `{seq}_{name}` doesn't match the row's `seq`/`name` | Rename folder to match the row (source of truth), or skip |

### (b) Artifact pointer integrity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Unregistered artifact | a file under `memory/` with no `prompt_artifact` row (`ARTIFACT_LIST {"prompt_uuid":"U"}`) | Register via `ARTIFACT_ADD {"prompt_uuid":"U","file_path":"…","note":"…"}` (default), or skip |
| Report written as a file | any `memory/{qualified,architecture,explore,review}.md` | DRIFT: every report is db-native. If no rows exist yet, transfer the content through the normal verbs — exploration: `bot_summary` then `explore_complete`; review: `REVIEW_OPEN` then `REVIEW_COMPLETE` (use `gmcc_hook call ... --json-file` for an overview too large for a shell argument) — then archive the file to cold storage |
| Dangling pointer | artifact row whose `file_path` doesn't exist on disk | Flag for user — restore the file if recoverable, or accept (pointers are history; there is no delete verb for them) |

### (c) File-change trail sanity

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| Stale file-change path | a `file_change_list` entry whose `path` no longer exists in the repo | Report only (the trail is append-only history — deletions/renames are normal); optionally record a follow-up entry with `file_change_add` at kind `delete` or `rename` |

### (d) Daemon/session health

| Finding | Example | Default suggestion |
|---------|---------|--------------------|
| No session row | no session row resolves for this repo/branch | `gmcc_hook context ensure` via the `gmcc_session_creation` skill (default) |
| Daemon unreachable | `gmcc_hook ping` fails | Self-heal: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, retry |

---

## Walk Strategy

Bounded to the session. Order:

1. **Health first** — `gmcc_hook ping`, then `gmcc_hook context ensure` to
   resolve this repo/branch to its uuids; without a reachable daemon +
   session row, only filesystem findings can be audited (offer to fix
   health first).
2. **Session root** — expect only `prompts/`; anything else (including
   `session_data.gmcc.yaml` / `gmcc_session_file_index.yaml`) is a
   finding.
3. **Db → disk** — for each stub in
   `gmcc_hook call PROMPT_LIST --json '{"session_uuid":"<U>"}'`: check the
   `{seq}_{name}/memory/` dir, then `ARTIFACT_LIST` rows vs disk files.
4. **Disk → db** — for each `prompts/{seq}_{name}/` folder: check a
   matching row exists; flag stray yamls and unknown files.
5. **File-change trail** — `file_change_list` path sanity.

Never judge the *content* of `memory/*.md` files (free-form artifacts) —
only presence and registration.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is
always the recommended, non-destructive default. Standard options:

| Option | What it does |
|--------|--------------|
| **Register / repair** (default for db-vs-disk drift) | The matching write call (`ARTIFACT_ADD`, `gmcc_hook context ensure`) or `mkdir -p`/rename. |
| **Archive** | `mv` into `$GMCC_CKFS_ROOT/_archive/cold_storage/{relative_path}` (structure-preserving, reversible). |
| **Skip** | Leave the finding in place. Always available. |

---

## Output Format

After the walk, before any prompts:

```
[GMB] Session Audit Report

Session: {code} ({session_uuid})
Daemon: {reachable | UNREACHABLE}
Total findings: {n}
- Prompt folder ↔ row integrity: {n}
- Artifact pointers: {n}
- File-change trail: {n}
- Pre-daemon yaml: {n}

Beginning interactive resolution. You can abort at any time — completed actions are NOT rolled back.
```

After resolution, print a resolved/skipped tally. Db repairs are audited
automatically in the daemon event log
(`gmcc_hook call EVENT_LIST --json '{"limit":50}'`); filesystem actions are
reported in chat only.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete** — the destructive option is archive to cold storage (move, not delete).
- **Never write the db directly** — every db repair goes over the socket, through a pen tool or `gmcc_hook call`.
- **Stay in scope** — never act on anything outside the session's artifact home (plus this session's db rows).
- **--dry-run** — when invoked with `--dry-run`, walk and report only; skip the resolution loop entirely.
