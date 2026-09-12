---
name: gmcc_cleanup_system
description: GM-CDE host-wiring auditor. Checks the things that live outside any one repo — stray ~/.zshrc gmcc env block, daemon binary reachability, env-vs-db root agreement, settings.json permission grants, session dope drift — and interactively resolves each one. The ckfs/db data audit is /gmcc_cleanup's job.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC System Cleanup Skill

Audits the HOST wiring that makes GMCC work outside any one repo — shell
config, binary reachability, permission grants — and interactively resolves
each finding.

Sessions get their env from `gmcc_hook context env` at SessionStart, which
prepends `~/gmcc/bin` to PATH so `gmcc_hook` resolves bare inside a session; a
terminal outside a session calls `~/gmcc/bin/gmcc_hook` by path. Every path
question is answered by `gmcc_hook paths --json`. This skill's job is keeping
that wiring healthy and clearing anything that competes with it.

---

## When to Use

- After a plugin upgrade or `/gm_init` on an old machine
- When `gmcc_hook` stops resolving, or resolves to the wrong (prod/sandbox) binary
- When SessionStart prints a `[GMB] WARN: ... disagreement` line
- Any time a `# >>> gmcc env >>>` block might exist in `~/.zshrc`

---

## Step 1: Detect

Run the checks below and collect findings before asking anything. If the
daemon is unreachable, that is finding 1 — offer the build/restart remedy
first, then re-run the rest.

```bash
# binaries
for b in gmcc_daemon gmcc_mcp gmcc_hook; do
  [ -x "${GMCC_ROOT:-$HOME/gmcc}/bin/$b" ] || echo "MISSING $b"
done
command -v gmcc_hook >/dev/null || echo "gmcc_hook not on the session PATH"

# daemon + the roots the db actually answers from
gmcc_hook ping
gmcc_hook paths --json

# the env's claim, to compare against those roots
echo "$GMCC_CKFS_ROOT" ; echo "${GMCC_ROOT:-<prod>}"

# a competing shell block
grep -n '>>> gmcc env >>>' ~/.zshrc
```

## Step 2: Resolve (one AskUserQuestion per finding; first option = default)

| Finding | Meaning | Default remedy |
|---|---|---|
| `zshrc_gmcc_block` | A `#### >>> gmcc env >>>` block exists in `~/.zshrc`. GMCC never writes shell profiles and nothing reads that block; its variables compete with the session env | **Delete the whole marker-bounded block.** This is the ONE rm-class action in the GMCC cleanup surface: print the exact lines to be removed first, require explicit confirmation, edit only between the markers |
| `binary_missing` | One of the three binaries is absent from `${GMCC_ROOT:-$HOME/gmcc}/bin` | `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` |
| `hook_not_on_path` | Bare `gmcc_hook` does not resolve inside the session | The session env never provisioned — restart Claude Code from inside a git repo; meanwhile call `~/gmcc/bin/gmcc_hook` by path. Never write the user's shell profile |
| `ckfs_root_mismatch` / `gmcc_root_mismatch` | The env's claim disagrees with the roots `gmcc_hook paths --json` reports from the db | Show both values and let the user pick which is right, then `gmcc_hook call CONFIG_SET --json '{"key":"ckfs_root","value":"<correct>"}'` (keys: `ckfs_root`, `kbite_root`, `kbite_open_root`, `kbite_digested_root`) |
| `dope_files_ahead` | The repo `.gmcc` tree is newer than (or absent from) the session scope | `gmcc_hook call DOPE_INGEST --json '{"scope_uuid":"<U>"}'` |
| `dope_db_ahead` | Session dope edits were never published to the repo files | `gmcc_hook call DOPE_WRITE_REPO --json '{"scope_uuid":"<U>"}'` (or accept — boot never overwrites db-ahead state) |
| `daemon_unreachable` | Socket dead or binaries stale | `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gmcc_hook ping` (the handshake retires the old daemon) |

Scope uuids for the dope remedies come from
`gmcc_hook call DOPE_LIST --json '{"session_uuid":"<U>"}'`.

### Permission-grant drift (settings.json)

Expected entries in `~/.claude/settings.json`: `$GMCC_CKFS_ROOT` in
`permissions.additionalDirectories`; `Read($GMCC_CKFS_ROOT/**)`,
`Edit($GMCC_CKFS_ROOT/**)`, `mcp__plugin_gmcc_pen__*`, and
`Bash($HOME/gmcc/bin/gmcc_hook *)` in `permissions.allow`.

`mcp__plugin_gmcc_pen__*` is the load-bearing one: the pen is how Claude
records the workflow, so a missing grant makes every write prompt.
`Bash($HOME/gmcc/bin/gmcc_hook *)` covers the shell-callable client — hooks,
context env, health, and the `gmcc_hook call <MESSAGE_TYPE>` passthrough that
reaches every verb with no pen tool of its own.

Missing → offer the same idempotent jq merge `/gm_init` documents (adds what's
missing, scrubs retired rules, preserves everything else). Takes effect on the
next Claude Code restart.

## Step 3: Verify + report

Re-run the Step 1 checks. Report resolved/skipped per finding, plus anything
still open.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation.
- The zshrc block deletion is marker-bounded, previews the exact removed
  lines, and never touches lines outside the markers.
- **Never write shell profiles** — PATH advice is printed, not applied.
- **Never write the db directly** — db-side remedies go over the socket.
- `adopt` is never offered here; it belongs to boot sync alone, and setting it
  by hand would let a stale on-disk tree overwrite db-side dope work.
