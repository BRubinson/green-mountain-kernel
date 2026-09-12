---
name: gmcc_boot
description: GMCC boot validation system. Automatically initializes GMCC environment on SessionStart. Invoke directly for boot diagnostics and troubleshooting.
user-invocable: true
allowed-tools: Bash, Read
---

# GMCC Boot System

The GMCC boot system runs automatically on SessionStart via the `gmcc_session_startup.sh` hook.

## Boot Sequence

When Claude Code starts a session:

1. **SessionStart hooks fire** (defined in `hooks.json`): `gmcc_session_startup.sh` then `check_daemon_stale.sh` (which names any daemon binary that is missing or older than the sources).
2. **gmcc_session_startup.sh executes** — a few jobs only: confirm we're in a git repository, hold the hook payload, find the plugin root, and find the right `gmcc_hook` binary (prod runtime, or the sandbox runtime named by a `.gmcc_sandbox` marker at the repo root). Everything else is owned by that binary.
   - If not in git repo: exits silently (no GMCC vars set)
   - If in git repo: pipes the hook payload into `gmcc_hook context ensure --hook-payload` (upserts project / instance / session db rows for the current repo + branch, pins the claude session binding, creates the session's artifact home, and runs the dope boot sync; warns and continues if the daemon is unavailable), then prints `gmcc_hook pen-sheet` into context
3. **`gmcc_hook context env` writes the environment to `$CLAUDE_ENV_FILE`** — the binary, not the script, owns the env contract. The surviving set is: `GMCC_BOOTED=1` (the boot signal), `GMCC_PLUGIN_ROOT`, `GMCC_CKFS_ROOT`, `PATH` (prepended so bare `gmcc_hook` resolves to the correct prod/sandbox binary), plus `GMCC_ROOT` when sandboxed. Each ships as one `export KEY='VALUE'` line: that file is a shell script Claude Code runs as a preamble before every Bash command, so a bare assignment would set a shell variable no child process inherits, and an unquoted value would stop at its first space. Session/project/kbite paths are NOT env vars — get roots from `gmcc_hook paths --json` and per-row locations from the `ckfs_relative_storage_path` fields of `SESSION_GET`. The diagnostics in this skill echo whatever is actually set at runtime.

## Boot Validation for Commands

All `gm_` commands MUST validate boot state before execution.

### Pre-Flight Boot Check Pattern

Add this check at the start of every command's Pre-Flight section:

```markdown
## Pre-Flight

**Boot Validation**:
Check if GMCC environment is ready:

If `$GMCC_BOOTED` is not set or empty:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. This happens when:
1. You are not in a git repository, OR
2. The SessionStart hook did not run (session started elsewhere)

To fix:
- Ensure you are in a git repository
- Restart Claude Code to trigger the SessionStart hook

Run /gmcc_boot for diagnostics.
```
Exit without proceeding.

If `$GMCC_BOOTED` is set: Continue with remaining pre-flight checks.
```

### Exception: Init Commands

The following commands should NOT check `GMCC_BOOTED`:
- `/gm_init` - Initializes the system (runs before boot is possible)

These commands have their own validation logic.

---

## Diagnostics (When Invoked Directly)

When a user invokes `/gmcc_boot` directly, run diagnostics:

### Step 1: Display Environment State

```bash
echo "=== GMCC Boot Diagnostics ==="
echo ""
echo "Boot Status:"
echo "  GMCC_BOOTED: ${GMCC_BOOTED:-NOT SET}"
echo ""
echo "Environment Variables (all GMCC_* + CLAUDE_PLUGIN_ROOT):"
env | grep -E '^GMCC_' | sort | sed 's/^/  /'
echo "  CLAUDE_PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT:-NOT SET}"
echo ""
```

### Step 2: Check Prerequisites

```bash
echo "Prerequisites:"
echo "  Git repository: $(git rev-parse --git-dir > /dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "  Ckfs root: $([ -d "${GMCC_CKFS_ROOT:-$HOME/gmcc_ckfs}" ] && echo 'YES' || echo 'NO — run /gm_init')"
for b in gmcc_daemon gmcc_mcp gmcc_hook; do
  echo "  $b: $([ -x "${GMCC_ROOT:-$HOME/gmcc}/bin/$b" ] && echo 'installed' || echo 'MISSING — run build_daemon.sh')"
done
echo "  gmcc_hook on PATH: $(command -v gmcc_hook > /dev/null 2>&1 && echo "YES - $(command -v gmcc_hook)" || echo 'NO — session PATH not provisioned')"
echo ""
echo "Daemon / DB:"
gmcc_hook ping 2>&1 | sed 's/^/  /'
gmcc_hook status 2>&1 | sed 's/^/  /'
echo ""
echo "Context rows (idempotent upsert — created_* false everywhere means the rows were already there):"
gmcc_hook context ensure 2>&1 | sed 's/^/  /'
```

### Step 3: Provide Guidance

Based on diagnostics, provide guidance:

**If GMCC_BOOTED is NOT SET**:
```
Issue: GMCC boot did not complete.

Most likely causes:
1. Not in a git repository - navigate to a git repo and restart Claude Code
2. Session started in a non-git directory - restart Claude Code from within a git repo
3. Plugin not installed correctly - verify GMCC plugin is enabled

To fix: Restart Claude Code from within a git repository.
```

**If a binary is missing or `gmcc_hook ping` fails**:
```
Issue: daemon system unavailable.

Run: bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
Then: ~/gmcc/bin/gmcc_hook context ensure
(See skills/gmcc_daemon/SKILL.md — self-heal rule.)
```

**If `gmcc_hook context ensure` errors, or reports uuids that then 404**:
```
Issue: db rows not ensured for this repo/branch.

Run: gmcc_hook context ensure   (from inside the repo)
```

**If all checks pass**:
```
GMCC boot status: READY

Daemon reachable, db rows present. You can run any gm_ command.
```

---

## Manual Boot (Emergency Fallback)

If the SessionStart hook fails to run, you can manually trigger boot by sourcing the detection script:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gmcc_session_startup.sh"
```

**Note**: This is a fallback for debugging. Normal boot should happen automatically.

---

## Troubleshooting

### "GMCC not booted" error when running commands

1. **Check if in git repo**: Run `git status` - if it fails, you're not in a git repository
2. **Restart Claude Code**: The SessionStart hook only runs on session start
3. **Verify plugin installed**: Check `~/.claude/settings.json` includes `gmcc@gmcc-marketplace`

### Environment variables partially set

This usually means the SessionStart hook ran but there was a problem:
- Check `gmcc_session_startup.sh` script for errors
- Verify git repository is accessible
- Run `/gmcc_boot` for full diagnostics

### Boot works but daemon calls fail

The env can boot fine while the daemon system is missing or stale:
1. Heed the `check_daemon_stale.sh` SessionStart warning — run `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`
2. `gmcc_hook daemon status` reports without autostarting; `/refresh_daemon_state` and `/gmcc_daemon` cover build + restart
3. `gmcc_hook context ensure` (idempotent) recreates missing db rows for the current repo/branch
