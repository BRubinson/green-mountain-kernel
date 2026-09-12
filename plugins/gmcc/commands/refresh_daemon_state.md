---
name: refresh_daemon_state
description: Ensure the latest GMCC daemon is installed AND running. Runs the staleness-checked build, then retires the running process whenever it predates the installed binaries (the handshake only auto-retires across a wire-version bump). Ends with gm_hook status.
argument-hint: "[--force]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# /refresh_daemon_state

Bring the daemon system fully current: newest binaries in `~/gmfs/bin/`,
newest build actually serving the socket. Invocation protocol and self-heal
rule in `$GM_PLUGIN_ROOT/skills/gm_daemon/SKILL.md`.

---

## Pre-Flight

**Boot Validation**: If `$GM_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

Restart Claude Code from within a git repository, then retry.
```
Exit without proceeding.

---

## Execution

1. **Install** — run:
   ```bash
   bash $GM_PLUGIN_ROOT/scripts/install_gm.sh
   ```
   This fetches the newest published `daemon-v*` release and no-ops when that
   version is already active. Note whether it printed `installed` (binaries
   replaced) or `already active` / `leaving it alone` (no-op).

   If `.gm_version` carries a `-BETA` suffix the user is running a locally
   built daemon, and the installer says so and stops rather than replacing
   work in progress. Use the source path instead, from a checkout of the repo
   (it is NOT in the plugin payload):
   ```bash
   bash gmk/scripts/rebuild_local.sh
   ```
   Append `--force` to either if the user asked for a clean reinstall/rebuild.
   These two are the ONLY things that put binaries on disk — no client path
   ever compiles or downloads anything.

2. **Ensure the RUNNING daemon is the installed build**:
   - If step 1 replaced binaries, the running daemon (if any) is definitionally
     stale — retire it (step 2a).
   - If step 1 no-oped, check what's serving the socket:
     `gm_hook daemon status` (never autostarts). If nothing is running,
     `gm_hook ping` brings the installed build up. If one is running,
     compare its reported `build_date` against the installed binary's mtime
     (`stat -f %Sm -t %Y-%m-%dT%H:%M:%SZ ~/gmfs/bin/gm_daemon` is local
     time — convert or compare epochs); if the running build date is older
     than the binary, retire it.

   2a. **Retiring a stale daemon**:
   ```bash
   gm_hook call SHUTDOWN --json '{}'   # drains, checkpoints the WAL, removes socket + pidfile
   gm_hook ping                        # the next client call starts the installed build
   ```
   Treat "daemon unreachable" on the shutdown call as already-stopped and
   continue.

   Do NOT rely on the protocol handshake here: it only retires a stale
   daemon across a wire-version bump, not a same-version rebuild.

3. **Verify** — run `gm_hook ping` and `gm_hook status`; the ping build
   sha/date must now reflect the just-installed binaries.

**Self-heal**: if a call fails because `gm_hook` is missing, run the build
(step 1) and retry once.

---

## Output

Report: rebuilt vs already-current, whether a retire+restart happened and
why, then the running build sha/date + `gm_hook status` summary. End with:

```
[GMB] daemon current — build {sha} running, binaries at ~/gmfs/bin/
```
