---
name: gmcc_session_cleanup
description: Audit the CURRENT session — the prompts/ artifact tree vs the daemon db rows (prompt stubs, artifact pointers, file changes) — and interactively resolve each finding. Session-scoped counterpart to /gmcc_environment_cleanup.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gmcc_session_cleanup

Run the GM-CDE **session-scoped** cleanup auditor. Cross-checks only the
current session — the session's artifact home on disk
(`$GMCC_CKFS_ROOT/{session ckfs_relative_storage_path}`, from
`gmcc_hook call SESSION_GET --json '{"session_uuid":"{U}"}'`) vs this
session's db rows (not the whole environment — that is
`/gmcc_environment_cleanup`), reports non-compliant state, and prompts
per-finding for an action. Full spec in
`$GMCC_PLUGIN_ROOT/skills/gmcc_session_cleanup/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify the session's artifact home exists: `gmcc_hook context ensure` gives
the session uuid, then resolve
`$GMCC_CKFS_ROOT/{ckfs_relative_storage_path}` from
`gmcc_hook call SESSION_GET --json '{"session_uuid":"{U}"}'`. If not, the environment never
resolved a session — suggest restarting Claude Code from inside a git repo (or
running the `gmcc_session_creation` skill) and exit.

---

## Execution

Read the `gmcc_session_cleanup` skill
(`$GMCC_PLUGIN_ROOT/skills/gmcc_session_cleanup/SKILL.md`) for the complete
session-scoped walk strategy and finding categories.

Follow that skill's protocol:

1. Health first: `gmcc_hook ping`, `gmcc_hook context ensure`.
2. Cross-check db → disk and disk → db per the skill (prompt rows vs
   folders, artifact pointers vs `memory/*.md`, file-change trail).
3. Print the audit report.
4. **NEVER auto-fix.** For each finding, AskUserQuestion with the per-category
   options (default first, always non-destructive).
5. Apply the user's chosen action (db repairs go through the daemon only —
   the pen tools, or `gmcc_hook call <MESSAGE_TYPE>`; never touch the
   sqlite file).
6. Print the cleanup-complete summary.

---

## Special Modes

**Dry-run mode** (`/gmcc_session_cleanup --dry-run`): walks and reports findings,
but skips the interactive resolution loop entirely. Useful for auditing the
session without committing to changes.

---

## Output

See the skill file's "Output Format" section for the exact templates.
