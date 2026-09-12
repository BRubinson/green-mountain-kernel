---
name: gm_vibes_dev_update_snapshot
description: Create or refresh the local-dev sandbox at gmfs/development/local_sandbox — a snapshot of the green-mountain-kernel repo, the gmcc sqlite (via a BACKUP read), and a sub-gmfs, fully isolated behind GM_FS_ROOT so a dev daemon + GMVibes stack runs without touching prod.
argument-hint: [status]
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# GM Vibes Dev Snapshot

A sandbox is a second GMCC runtime selected by `GM_FS_ROOT`: its own binaries,
its own `gm.db`, its own gmfs. Sessions started inside the snapshot repo
auto-sandbox from its `.gmcc_sandbox` marker, so a sandboxed daemon and a
sandboxed client never touch the prod db.

## The invariants (check them, do not work around them)

- Run from the **green-mountain-kernel repo root**, in a **prod** session
  (`GM_FS_ROOT` unset).
- The prod db is touched ONLY by a BACKUP read — never copy
  `~/gmfs/gm.db` in place, and never write the live gmfs.
- Kbites are multi-GB; they are never copied. The sandbox gets empty kbite
  roots by design.
- Every path the sandbox daemon reports must live under the sandbox. Env and
  db must agree; a disagreement is a warning at boot and means the isolation
  is broken.

## `status`

If the argument is `status`, report on the existing snapshot and stop:

```sh
SANDBOX=~/gmfs/development/local_sandbox
export GM_FS_ROOT="$SANDBOX/gmcc" GM_FS_ROOT="$SANDBOX/gmfs"
"$GM_FS_ROOT/bin/gm_hook" paths --json
```

Every value must be under `$SANDBOX`. If any is not, STOP and report — do
not keep using that sandbox.

## Refresh / create

1. **Snapshot the db.** `gm_hook call BACKUP --json '{}'` writes a
   timestamped SQLite online-backup into `~/gmfs/backups/`. The response
   names the file; that file is the sandbox's starting db.

2. **Lay out the snapshot.**
   ```sh
   SANDBOX=~/gmfs/development/local_sandbox
   mkdir -p "$SANDBOX/gmcc/bin" "$SANDBOX/gmfs/projects" "$SANDBOX/gmfs/kbites"
   cp <backup file from step 1> "$SANDBOX/gmcc/gm.db"
   PROD_BIN="$HOME/gmfs/bin"
   cp "$PROD_BIN"/gm_daemon "$PROD_BIN"/gm_mcp "$PROD_BIN"/gm_hook "$SANDBOX/gmcc/bin/"
   git clone <repo root> "$SANDBOX/repo"
   ```

3. **Mark the clone as a sandbox** — the SessionStart hook PARSES this file
   (never sources it), so keep it to exactly these two lines:
   ```sh
   cat > "$SANDBOX/repo/.gmcc_sandbox" <<EOF
   export GM_FS_ROOT="$SANDBOX/gmcc"
   export GM_FS_ROOT="$SANDBOX/gmfs"
   EOF
   ```

4. **Retarget the staged db's roots** so env and db agree by construction.
   Run each against the SANDBOX runtime (the first call autostarts the
   sandbox daemon from the staged binaries):
   ```sh
   export GM_FS_ROOT="$SANDBOX/gmcc" GM_FS_ROOT="$SANDBOX/gmfs"
   HOOK="$GM_FS_ROOT/bin/gm_hook"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"gmfs_root\",\"value\":\"$SANDBOX/gmfs\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_root\",\"value\":\"$SANDBOX/gmfs/kbites\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_open_root\",\"value\":\"$SANDBOX/gmfs/kbites/open\"}"
   "$HOOK" call CONFIG_SET --json "{\"key\":\"kbite_digested_root\",\"value\":\"$SANDBOX/gmfs/kbites/digested\"}"
   ```

5. **Write the launchers.** Finder cannot pass env, so GMVibes must be
   launched through a script:
   ```sh
   cat > "$SANDBOX/launch_hook.sh" <<EOF
   #!/bin/sh
   export GM_FS_ROOT="$SANDBOX/gmcc"
   export GM_FS_ROOT="$SANDBOX/gmfs"
   exec "\$GM_FS_ROOT/bin/gm_hook" "\$@"
   EOF
   cat > "$SANDBOX/launch_gmvibes.sh" <<EOF
   #!/bin/sh
   export GM_FS_ROOT="$SANDBOX/gmcc"
   export GM_FS_ROOT="$SANDBOX/gmfs"
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
- Never copy the live `~/gmfs/gm.db` directly; the BACKUP read is the only
  sanctioned way to take its contents.
- Never point sandbox kbite roots at the live kbite trees.
