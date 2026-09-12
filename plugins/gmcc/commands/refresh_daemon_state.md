---
name: refresh_daemon_state
description: Ensure the latest GMCC daemon is installed AND running. Runs the staleness-checked build, then retires the running process whenever it predates the installed binaries (the handshake only auto-retires across a wire-version bump). Ends with gmcc_hook status.
argument-hint: "[--force]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# /refresh_daemon_state

Bring the daemon system fully current: newest binaries in `~/gmcc/bin/`,
newest build actually serving the socket. Invocation protocol and self-heal
rule in `$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

---

## Execution

1. **Build/install** — run:
   ```bash
   bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
   ```
   Append `--force` if the user passed it (clean rebuild). The script is
   staleness-checked: note whether it printed `installed:` (rebuilt) or
   `up to date` (no-op). It is the ONLY thing that builds — no client path
   ever compiles anything.

2. **Ensure the RUNNING daemon is the installed build**:
   - If step 1 rebuilt, the running daemon (if any) is definitionally
     stale — retire it (step 2a).
   - If step 1 no-oped, check what's serving the socket:
     `gmcc_hook daemon status` (never autostarts). If nothing is running,
     `gmcc_hook ping` brings the installed build up. If one is running,
     compare its reported `build_date` against the installed binary's mtime
     (`stat -f %Sm -t %Y-%m-%dT%H:%M:%SZ ~/gmcc/bin/gmcc_daemon` is local
     time — convert or compare epochs); if the running build date is older
     than the binary, retire it.

   2a. **Retiring a stale daemon**:
   ```bash
   gmcc_hook call SHUTDOWN --json '{}'   # drains, checkpoints the WAL, removes socket + pidfile
   gmcc_hook ping                        # the next client call starts the installed build
   ```
   Treat "daemon unreachable" on the shutdown call as already-stopped and
   continue.

   Do NOT rely on the protocol handshake here: it only retires a stale
   daemon across a wire-version bump, not a same-version rebuild.

3. **Verify** — run `gmcc_hook ping` and `gmcc_hook status`; the ping build
   sha/date must now reflect the just-installed binaries.

**Self-heal**: if a call fails because `gmcc_hook` is missing, run the build
(step 1) and retry once.

---

## Output

Report: rebuilt vs already-current, whether a retire+restart happened and
why, then the running build sha/date + `gmcc_hook status` summary. End with:

```
[GMB] daemon current — build {sha} running, binaries at ~/gmcc/bin/
```
