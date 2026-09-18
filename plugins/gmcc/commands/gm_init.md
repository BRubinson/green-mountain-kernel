---
description: Initialize the GM-CDE system at the user level. Creates the filesystem root, installs the kernel binaries, and brings the daemon up. Run once per machine; per-project, per-instance and per-session state is auto-ensured by the SessionStart hook on first encounter.
argument-hint: "[--force]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

Initialize GM-CDE at the USER level. Once per machine.

**Steps:**
    1. Pre-flight — if the root already exists and `--force` was not passed, report what is present and stop.
    2. Create the filesystem root at `$GM_FS_ROOT` with its directory skeleton and README.
    3. Install the kernel binaries and bring the daemon up; verify it answers.
    4. Put `gm_hook` on the terminal PATH by PRINTING the line to add. Never write the shell profile yourself.
    5. Persist the GMFS permission grant in `~/.claude/settings.json` — `Read`/`Edit` under the root plus the additional directory.
    6. Verify: daemon reachable, env and db agreeing on the root, grant present. Report each.

**Contract:**
    1. Per-project, per-instance and per-session state is auto-ensured by the SessionStart hook. Do NOT create it here.
    2. GMCC never writes the user's shell profile. Remediation lines are printed, not applied.
    3. The database is append-only history. Initialization never wipes an existing one.
