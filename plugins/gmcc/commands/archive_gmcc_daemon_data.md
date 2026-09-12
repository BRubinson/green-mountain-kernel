---
name: archive_gmcc_daemon_data
description: Archive the daemon's runtime data — move ~/gmfs/gm.db (+ -wal/-shm sidecars and daemon.log) into ~/gmfs/_archive/cold_storage/{timestamp}/ and bring the daemon back on a fresh, empty db. Touches ONLY the ~/gmfs runtime; never reads or writes the gmfs artifact tree ($GM_FS_ROOT).
argument-hint: ""
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /archive_gmcc_daemon_data

Cold-storage the live daemon db and start over clean. Daemon invocation
protocol in `$GM_PLUGIN_ROOT/skills/gm_daemon/SKILL.md`.

**Scope guarantee**: this command operates exclusively on the `~/gmfs/`
runtime directory. The gmfs artifact tree (`$GM_FS_ROOT`) is never
touched — a fresh db repopulates its project → instance → session chain from
git context via `gm_hook context ensure` (reusing the gmfs storage paths),
so the artifact tree on disk is unaffected.

---

## Pre-Flight

**Boot Validation**: If `$GM_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

If `~/gmfs/gm.db` does not exist, report "nothing to archive" and stop.

---

## Execution

1. **Confirm** — AskUserQuestion: show the db size, mtime, and current
   table row counts (`gm_hook status`), and confirm the user wants
   the live db archived and replaced with an empty one. Abort on anything
   but an explicit yes.

2. **Stop the daemon** — `gm_hook call SHUTDOWN --json '{}'` (drains,
   WAL checkpoints, removes socket + pidfile, exit 0). Treat "daemon
   unreachable" as already-stopped and continue.

3. **Archive** — one universal cold-storage bucket, mirroring the gmfs
   convention but inside the runtime dir:
   ```bash
   ARCHIVE=~/gmfs/_archive/cold_storage/$(date -u +%Y%m%dT%H%M%SZ)
   mkdir -p "$ARCHIVE"
   mv ~/gmfs/gm.db "$ARCHIVE/"
   mv ~/gmfs/gm.db-wal "$ARCHIVE/" 2>/dev/null || true
   mv ~/gmfs/gm.db-shm "$ARCHIVE/" 2>/dev/null || true
   mv ~/gmfs/daemon.log "$ARCHIVE/" 2>/dev/null || true
   ```
   MOVE, never copy-then-delete, and never touch `~/gmfs/bin/` or
   `~/gmfs/backups/` (those are live-db snapshots, not archives).

4. **Fresh start** — `gm_hook ping`; the next client call starts the
   daemon, which recreates `gm.db` from the m0001 baseline and migrates it
   forward. Then run `gm_hook context ensure` from the repo root so the
   current project/instance/session rows exist again (idempotent).

5. **Verify** — `gm_hook status`: fresh schema version, near-zero
   row counts (just the ensured context chain).

**Self-heal**: if `gm_hook` is missing at any step, run
`bash $GM_PLUGIN_ROOT/scripts/install_gm.sh` and retry once.

---

## Output

Report what was moved (files + destination folder), the fresh-db status
summary, and end with:

```
[GMB] daemon data archived to {archive path} — fresh db in service
```
