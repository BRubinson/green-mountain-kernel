---
name: gm_daemon
description: Install, build, and control the GMCC daemon. Runs scripts/install_gm.sh (or scripts/rebuild_local.sh for a source build) and drives gm_hook for status and lifecycle. The daemon owns the SQLite db at ~/gmfs/gm.db; everything else is a socket client.
argument-hint: "[install | build | status | restart]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /gm_daemon

Manage the GMCC daemon system. Full invocation protocol (the ops verbs, the
raw passthrough, the self-heal rule, the single-writer model) in
`$GM_PLUGIN_ROOT/skills/gm_daemon/SKILL.md`.

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

Read the `gm_daemon` skill (`$GM_PLUGIN_ROOT/skills/gm_daemon/SKILL.md`)
for the complete protocol, then dispatch on the argument:

- **`install`** (default when binaries are missing or the version drifted): run
  `bash $GM_PLUGIN_ROOT/scripts/install_gm.sh` and report the output. It
  fetches the pinned release, and falls back to a source build only when there
  is nothing to download. Append `--force` to reinstall over a matching version.
- **`build`**: run `bash $GM_PLUGIN_ROOT/scripts/rebuild_local.sh` and report
  the output. This is the developer path — it compiles the package. Append
  `--force` if the user asked for a clean rebuild. Prefer `install` unless the
  user is editing daemon sources.
- **`status`**: run `gm_hook status` and report daemon pid, schema
  version, and table counts. (`gm_hook daemon status` is the narrower
  "is it up" check — it never autostarts.)
- **`restart`**: `gm_hook call SHUTDOWN --json '{}'` to drain and stop,
  then `gm_hook ping` — the next client call starts the installed build.
- **No argument**: run the build (staleness-checked — it no-ops when binaries
  are current), then `gm_hook status`.

First run on a machine needs nothing extra: the daemon creates `~/gmfs/`,
the log, and the db (migrated to the current schema) as it comes up, so a
`gm_hook ping` after the build is the whole of setup.

**Self-heal**: if a `gm_hook` invocation fails because the binary is
missing, run the build first, then retry once.

---

## Output

Relay the script/client output. On success end with:

```
[GMB] daemon ready — binaries at ~/gmfs/bin/
```
