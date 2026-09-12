---
name: gmcc_environment_cleanup
description: Audit the GMCC gmfs/db environment — daemon/db health, db-vs-disk drift, leftover pre-daemon yaml runtime files, archive hygiene — and interactively resolve each finding with the user. Host wiring (PATH shim, retired zshrc block, grants) is /gmcc_cleanup_system. Environment-wide counterpart to /gmcc_session_cleanup.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# /gmcc_environment_cleanup

Run the GM-CDE environment auditor. Checks daemon/db health over the daemon
socket, walks the gmfs root (bounded), reports non-compliant state, prompts
per-finding for an action. Full spec in `$GM_PLUGIN_ROOT/skills/gmcc_cleanup/SKILL.md`.
Host wiring (retired `~/.zshrc` gmcc block, terminal PATH, permission
grants, env-vs-db root agreement) is `/gmcc_cleanup_system`'s audit —
suggest it when host drift shows up.

---

## Pre-Flight

**Boot Validation**: If `$GM_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

Verify `$GM_FS_ROOT` exists. If not, suggest `/gm_init` and exit.

---

## Execution

Read the `gmcc_cleanup` skill (`$GM_PLUGIN_ROOT/skills/gmcc_cleanup/SKILL.md`) for the complete walk strategy and finding categories.

Follow that skill's protocol:

1. Check daemon health (`gm_hook ping` / `gm_hook status` /
   `gm_hook context ensure`).
2. Walk `$GM_FS_ROOT` per the bounded strategy in the skill.
3. Collect findings.
4. Print the audit report.
5. **NEVER auto-fix.** For each finding, AskUserQuestion with the per-category options (default first, always non-destructive).
6. Apply the user's chosen action (db repairs go through the daemon only — the pen tools, or `gm_hook call <MESSAGE_TYPE>`; filesystem moves into `_archive/cold_storage/`).
7. Print the cleanup-complete summary.

---

## Special Modes

**Dry-run mode** (`/gmcc_environment_cleanup --dry-run`): walks and reports findings, but skips the interactive resolution loop entirely. Useful for auditing without committing to changes.

---

## Output

See the skill file's "Output Format" section for the exact templates.
