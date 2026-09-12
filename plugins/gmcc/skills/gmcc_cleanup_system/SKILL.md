---
name: gmcc_cleanup_system
description: GM-CDE host-wiring auditor. Checks the things that live outside any one repo — stray ~/.zshrc gmcc env block, daemon binary reachability, env-vs-db root agreement, settings.json permission grants, session dope drift — and interactively resolves each one. The gmfs/db data audit is /gmcc_cleanup's job.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC System Cleanup Skill

Audits the HOST wiring that makes GMCC work outside any one repo — shell
config, binary reachability, permission grants — and interactively resolves
each finding.

Sessions get their env from `gm_hook context env` at SessionStart, which
prepends `~/gmfs/bin` to PATH so `gm_hook` resolves bare inside a session; a
terminal outside a session calls `~/gmfs/bin/gm_hook` by path. Every path
question is answered by `gm_hook paths --json`. This skill's job is keeping
that wiring healthy and clearing anything that competes with it.

---

## When to Use

- After a plugin upgrade or `/gm_init` on an old machine
- When `gm_hook` stops resolving, or resolves to the wrong (prod/sandbox) binary
- When SessionStart prints a `[GMB] WARN: ... disagreement` line
- Any time a `# >>> gmcc env >>>` block might exist in `~/.zshrc`

---

## Step 1: Detect

Run the checks below and collect findings before asking anything. If the
daemon is unreachable, that is finding 1 — offer the install/restart remedy
first, then re-run the rest.

```bash
# binaries
for b in gm_daemon gm_mcp gm_hook; do
  [ -x "${GM_FS_ROOT:-$HOME/gmfs}/bin/$b" ] || echo "MISSING $b"
done
command -v gm_hook >/dev/null || echo "gm_hook not on the session PATH"

# active version (a -BETA stamp = locally built, not drift)
cat "${GM_FS_ROOT:-$HOME/gmfs}/bin/.gm_version" 2>/dev/null || echo "no version stamp"
# what is published, and whether an upgrade exists (network; exit 1 = upgrade available)
bash "$GM_PLUGIN_ROOT/scripts/install_gm.sh" --check

# daemon + the roots the db actually answers from
gm_hook ping
gm_hook paths --json

# the env's claim, to compare against those roots
echo "$GM_FS_ROOT" ; echo "${GM_FS_ROOT:-<prod>}"

# a competing shell block
grep -n '>>> gmcc env >>>' ~/.zshrc
```

## Step 2: Resolve (one AskUserQuestion per finding; first option = default)

| Finding | Meaning | Default remedy |
|---|---|---|
| `zshrc_gmcc_block` | A `#### >>> gmcc env >>>` block exists in `~/.zshrc`. GMCC never writes shell profiles and nothing reads that block; its variables compete with the session env | **Delete the whole marker-bounded block.** This is the ONE rm-class action in the GMCC cleanup surface: print the exact lines to be removed first, require explicit confirmation, edit only between the markers |
| `binary_missing` | One of the three binaries is absent from `${GM_FS_ROOT:-$HOME/gmfs}/bin` | `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh` |
| `binary_version_drift` | `install_gm.sh --check` reports a newer published release than the active `.gm_version` (a `-BETA` stamp is a local build, not drift — leave it) | `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh` |
| `binary_link_broken` | A binary in `${GM_FS_ROOT:-$HOME/gmfs}/bin` is a dangling symlink — its staged version directory under `releases/` was deleted | `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh` (re-stages and re-points `releases/active`) |
| `hook_not_on_path` | Bare `gm_hook` does not resolve inside the session | The session env never provisioned — restart Claude Code from inside a git repo; meanwhile call `~/gmfs/bin/gm_hook` by path. Never write the user's shell profile |
| `gmfs_root_mismatch` / `gmcc_root_mismatch` | The env's claim disagrees with the roots `gm_hook paths --json` reports from the db | Show both values and let the user pick which is right, then `gm_hook call CONFIG_SET --json '{"key":"gmfs_root","value":"<correct>"}'` (keys: `gmfs_root`, `kbite_root`, `kbite_open_root`, `kbite_digested_root`) |
| `dope_files_ahead` | The repo `.gmcc` tree is newer than (or absent from) the session scope | `gm_hook call DOPE_INGEST --json '{"scope_uuid":"<U>"}'` |
| `dope_db_ahead` | Session dope edits were never published to the repo files | `gm_hook call DOPE_WRITE_REPO --json '{"scope_uuid":"<U>"}'` (or accept — boot never overwrites db-ahead state) |
| `daemon_unreachable` | Socket dead or binaries stale | `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh`, then `gm_hook ping` (the handshake retires the old daemon) |

Scope uuids for the dope remedies come from
`gm_hook call DOPE_LIST --json '{"session_uuid":"<U>"}'`.

### Permission-grant drift (settings.json)

Expected entries in `~/.claude/settings.json`: `$GM_FS_ROOT` in
`permissions.additionalDirectories`; `Read($GM_FS_ROOT/**)`,
`Edit($GM_FS_ROOT/**)`, `mcp__plugin_gmcc_pen__*`, and
`Bash($HOME/gmfs/bin/gm_hook *)` in `permissions.allow`.

`mcp__plugin_gmcc_pen__*` is the load-bearing one: the pen is how Claude
records the workflow, so a missing grant makes every write prompt.
`Bash($HOME/gmfs/bin/gm_hook *)` covers the shell-callable client — hooks,
context env, health, and the `gm_hook call <MESSAGE_TYPE>` passthrough that
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
