---
name: gmcc_daemon
description: Build, install, and control the GMCC daemon. Runs scripts/build_daemon.sh and drives gmcc_hook for status and lifecycle. The daemon owns the SQLite db at ~/gmcc/gmcc.db; everything else is a socket client.
argument-hint: "[build | status | restart]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /gmcc_daemon

Manage the GMCC daemon system. Full invocation protocol (the ops verbs, the
raw passthrough, the self-heal rule, the single-writer model) in
`$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

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

Read the `gmcc_daemon` skill (`$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`)
for the complete protocol, then dispatch on the argument:

- **`build`** (default when binaries are missing/stale): run
  `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh` and report the output. It
  is the only thing that builds. Append `--force` if the user asked for a
  clean rebuild.
- **`status`**: run `gmcc_hook status` and report daemon pid, schema
  version, and table counts. (`gmcc_hook daemon status` is the narrower
  "is it up" check — it never autostarts.)
- **`restart`**: `gmcc_hook call SHUTDOWN --json '{}'` to drain and stop,
  then `gmcc_hook ping` — the next client call starts the installed build.
- **No argument**: run the build (staleness-checked — it no-ops when binaries
  are current), then `gmcc_hook status`.

First run on a machine needs nothing extra: the daemon creates `~/gmcc/`,
the log, and the db (migrated to the current schema) as it comes up, so a
`gmcc_hook ping` after the build is the whole of setup.

**Self-heal**: if a `gmcc_hook` invocation fails because the binary is
missing, run the build first, then retry once.

---

## Output

Relay the script/client output. On success end with:

```
[GMB] daemon ready — binaries at ~/gmcc/bin/
```
