---
name: gm_vibes_dev_update_snapshot
description: Create or refresh the local-dev sandbox at gmcc_ckfs/development/local_sandbox — a snapshot of the gmcc-marketplace repo, the gmcc sqlite (via a BACKUP read), and a sub-ckfs, fully isolated behind GMCC_ROOT so a dev daemon + GMVibes stack runs without touching prod.
argument-hint: [status]
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# GM Vibes Dev Snapshot

A sandbox is a second GMCC runtime selected by `GMCC_ROOT`: its own binaries,
its own `gmcc.db`, its own ckfs. Sessions started inside the snapshot repo
auto-sandbox from its `.gmcc_sandbox` marker, so a sandboxed daemon and a
sandboxed client never touch the prod db.

## The invariants (check them, do not work around them)

- Run from the **gmcc-marketplace repo root**, in a **prod** session
  (`GMCC_ROOT` unset).
- The prod db is touched ONLY by a BACKUP read — never copy
  `~/gmcc/gmcc.db` in place, and never write the live ckfs.
- Kbites are multi-GB; they are never copied. The sandbox gets empty kbite
  roots by design.
- Every path the sandbox daemon reports must live under the sandbox. Env and
  db must agree; a disagreement is a warning at boot and means the isolation
  is broken.

## `status`

If the argument is `status`, report on the existing snapshot and stop:

```sh
SANDBOX=~/gmcc_ckfs/development/local_sandbox
export GMCC_ROOT="$SANDBOX/gmcc" GMCC_CKFS_ROOT="$SANDBOX/ckfs"
"$GMCC_ROOT/bin/gmcc_hook" paths --json
```

Every value must be under `$SANDBOX`. If any is not, STOP and report — do
not keep using that sandbox.

## Refresh / create

1. **Snapshot the db.** `gmcc_hook call BACKUP --json '{}'` writes a
   timestamped SQLite online-backup into `~/gmcc/backups/`. The response
   names the file; that file is the sandbox's starting db.

2. **Lay out the snapshot.**
   ```sh
   SANDBOX=~/gmcc_ckfs/development/local_sandbox
   mkdir -p "$SANDBOX/gmcc/bin" "$SANDBOX/ckfs/projects" "$SANDBOX/ckfs/kbites"
   cp <backup file from step 1> "$SANDBOX/gmcc/gmcc.db"
   PROD_BIN="$HOME/gmcc/bin"
   cp "$PROD_BIN"/gmcc_daemon "$PROD_BIN"/gmcc_mcp "$PROD_BIN"/gmcc_hook "$SANDBOX/gmcc/bin/"
   git clone <repo root> "$SANDBOX/repo"
   ```

3. **Mark the clone as a sandbox** — the SessionStart hook PARSES this file
   (never sources it), so keep it to exactly these two lines:
   ```sh
   cat > "$SANDBOX/repo/.gmcc_sandbox" <<EOF
   export GMCC_ROOT="$SANDBOX/gmcc"
   export GMCC_CKFS_ROOT="$SANDBOX/ckfs"
   EOF
   ```

4. **Retarget the staged db's roots** so env and db agree by construction.
   Run each against the SANDBOX runtime (the first call autostarts the
   sandbox daemon from the staged binaries):
   ```sh
   export GMCC_ROOT="$SANDBOX/gmcc" GMCC_CKFS_ROOT="$SANDBOX/ckfs"
   HOOK="$GMCC_ROOT/bin/gmcc_hook"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"ckfs_root\",\"value\":\"$SANDBOX/ckfs\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_root\",\"value\":\"$SANDBOX/ckfs/kbites\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_open_root\",\"value\":\"$SANDBOX/ckfs/kbites/open\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_digested_root\",\"value\":\"$SANDBOX/ckfs/kbites/digested\"}"
   ```

5. **Write the launchers.** Finder cannot pass env, so GMVibes must be
   launched through a script:
   ```sh
   cat > "$SANDBOX/launch_hook.sh" <<EOF
   #!/bin/sh
   export GMCC_ROOT="$SANDBOX/gmcc"
   export GMCC_CKFS_ROOT="$SANDBOX/ckfs"
   exec "\$GMCC_ROOT/bin/gmcc_hook" "\$@"
   EOF
   cat > "$SANDBOX/launch_gmvibes.sh" <<EOF
   #!/bin/sh
   export GMCC_ROOT="$SANDBOX/gmcc"
   export GMCC_CKFS_ROOT="$SANDBOX/ckfs"
   exec open -n "\${1:-/Applications/GMVibes.app}"
   EOF
   chmod +x "$SANDBOX/launch_hook.sh" "$SANDBOX/launch_gmvibes.sh"
   ```

6. **Verify isolation before declaring success:**
   ```sh
   "$SANDBOX/launch_hook.sh" status          # sandbox daemon pid, schema, counts
   "$SANDBOX/launch_hook.sh" paths --json    # every path must be under $SANDBOX
   "$SANDBOX/launch_hook.sh" call SESSION_LIST --json '{}'   # non-empty = the db came across
   ```
   If any `paths` value points outside the sandbox, STOP and report.

7. **Report**: the sandbox root, the backup file the db came from, the two
   launchers, and that re-running this command is always the safe recovery
   for a partial snapshot.

## Never

- Never start a launchd job or install a PATH entry from inside a sandbox —
  both are prod singletons.
- Never copy the live `~/gmcc/gmcc.db` directly; the BACKUP read is the only
  sanctioned way to take its contents.
- Never point sandbox kbite roots at the live kbite trees.
