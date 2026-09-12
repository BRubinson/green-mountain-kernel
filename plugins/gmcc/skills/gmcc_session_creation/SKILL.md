---
name: gmcc_session_creation
description: Standalone GM-CDE session bootstrapper. Ensures the current session's db rows (gmcc_hook context ensure) and physical artifact home (prompts/) exist, independent of the SessionStart hook. Idempotent — never clobbers existing state.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob
---

# GMCC Session Creation Skill

Bootstraps (or repairs) the **current** session on demand. The
`SessionStart` hook (`scripts/gmcc_session_startup.sh`) already does this
automatically the first time Claude Code starts in a repo, but this skill
exists as a **standalone, manually-invocable** path for when:

- the hook never ran (e.g. session started outside a git repo, then `cd`'d in),
- the daemon was unreachable at SessionStart so no db rows were ensured,
- the session's `prompts/` artifact home was deleted,
- `/gmcc_session_cleanup` finds missing session state and delegates here.

**It does NOT modify `gmcc_session_startup.sh` or the SessionStart flow.**

---

## When to Use

- Manually, when the db has no rows for the active session.
- To recreate a deleted session artifact home (the `prompts/` directory under the session's `ckfs_relative_storage_path`).
- As the repair target invoked by `/gmcc_session_cleanup`.

---

## Core Principle: Idempotency

Both steps are natively idempotent: `gmcc_hook context ensure` upserts (reusing
existing uuids, seeding kbite inheritance only at row-create time) and
`mkdir -p` is a no-op on existing dirs. Running this twice on a healthy
session changes nothing.

---

## Pre-Flight

**Boot Validation**: If `$GMCC_BOOTED` is not set:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

Verify `$GMCC_CKFS_ROOT` is set. If unset, the environment never booted —
instruct the user to restart Claude Code from inside a git repo and exit.

---

## Execution

### 1. Db rows (+ artifact home)

```bash
gmcc_hook context ensure
```

Run from inside the repo (git context is auto-detected). This upserts the
db rows and creates the session's artifact home, and prints the resulting
uuids as JSON. If it fails with the daemon unreachable, self-heal first:

```bash
bash "$GMCC_PLUGIN_ROOT/scripts/build_daemon.sh"
gmcc_hook context ensure
```

### 2. Physical artifact home

Resolve the session's `ckfs_relative_storage_path` from the session row:

```bash
gmcc_hook call SESSION_GET --json '{"session_uuid":"<SESSION_UUID>"}'
mkdir -p "$GMCC_CKFS_ROOT/{ckfs_relative_storage_path}/prompts"
```

(a no-op when `gmcc_hook context ensure` already created it).

The response reports `project_uuid` / `instance_uuid` / `session_uuid` and
`created_*` booleans telling you which rows were newly created vs. already
present.

### 3. Summary

Print what was created vs. already-present:
```
GMCC Session Creation: {session code}

- prompts/            {created | already present}
- project row         {created | already present}
- instance row        {created | already present}
- session row         {created | already present}

Session ready: {artifact home} (artifacts) + ~/gmcc/gmcc.db (data)
```

---

## Notes

- This skill writes no yaml. Any `session_data.gmcc.yaml` /
  `gmcc_session_file_index.yaml` still on disk is inert —
  `/gmcc_environment_cleanup` archives it to cold storage.
- Kbite inheritance is seeded db-side at row-create time by
  `gmcc_hook context ensure`. Explicit registry ops afterward are
  `KBITE_ADD` / `KBITE_REMOVE` / `KBITE_LIST` — the db is the sole registry.
