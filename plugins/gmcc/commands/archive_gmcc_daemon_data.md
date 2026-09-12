---
name: archive_gmcc_daemon_data
description: Archive the daemon's runtime data — move ~/gmcc/gmcc.db (+ -wal/-shm sidecars and daemon.log) into ~/gmcc/_archive/cold_storage/{timestamp}/ and bring the daemon back on a fresh, empty db. Touches ONLY the ~/gmcc runtime; never reads or writes the ckfs artifact tree ($GMCC_CKFS_ROOT).
argument-hint: ""
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /archive_gmcc_daemon_data

Cold-storage the live daemon db and start over clean. Daemon invocation
protocol in `$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

**Scope guarantee**: this command operates exclusively on the `~/gmcc/`
runtime directory. The ckfs artifact tree (`$GMCC_CKFS_ROOT`) is never
touched — a fresh db repopulates its project → instance → session chain from
git context via `gmcc_hook context ensure` (reusing the ckfs storage paths),
so the artifact tree on disk is unaffected.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

If `~/gmcc/gmcc.db` does not exist, report "nothing to archive" and stop.

---

## Execution

1. **Confirm** — AskUserQuestion: show the db size, mtime, and current
   table row counts (`gmcc_hook status`), and confirm the user wants
   the live db archived and replaced with an empty one. Abort on anything
   but an explicit yes.

2. **Stop the daemon** — `gmcc_hook call SHUTDOWN --json '{}'` (drains,
   WAL checkpoints, removes socket + pidfile, exit 0). Treat "daemon
   unreachable" as already-stopped and continue.

3. **Archive** — one universal cold-storage bucket, mirroring the ckfs
   convention but inside the runtime dir:
   ```bash
   ARCHIVE=~/gmcc/_archive/cold_storage/$(date -u +%Y%m%dT%H%M%SZ)
   mkdir -p "$ARCHIVE"
   mv ~/gmcc/gmcc.db "$ARCHIVE/"
   mv ~/gmcc/gmcc.db-wal "$ARCHIVE/" 2>/dev/null || true
   mv ~/gmcc/gmcc.db-shm "$ARCHIVE/" 2>/dev/null || true
   mv ~/gmcc/daemon.log "$ARCHIVE/" 2>/dev/null || true
   ```
   MOVE, never copy-then-delete, and never touch `~/gmcc/bin/` or
   `~/gmcc/backups/` (those are live-db snapshots, not archives).

4. **Fresh start** — `gmcc_hook ping`; the next client call starts the
   daemon, which recreates `gmcc.db` from the m0001 baseline and migrates it
   forward. Then run `gmcc_hook context ensure` from the repo root so the
   current project/instance/session rows exist again (idempotent).

5. **Verify** — `gmcc_hook status`: fresh schema version, near-zero
   row counts (just the ensured context chain).

**Self-heal**: if `gmcc_hook` is missing at any step, run
`bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` and retry once.

---

## Output

Report what was moved (files + destination folder), the fresh-db status
summary, and end with:

```
[GMB] daemon data archived to {archive path} — fresh db in service
```
