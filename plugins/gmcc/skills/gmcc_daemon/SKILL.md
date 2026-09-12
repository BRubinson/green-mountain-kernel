---
name: gmcc_daemon
description: How to invoke the GMCC daemon system - the three binaries (gmcc_daemon the single-writer server, gmcc_mcp the pen Claude records through, gmcc_hook the shell-callable client and raw-wire passthrough), which door to use for what, the typed error contract, and the build/self-heal rule when binaries are missing or stale. Use whenever recording file changes to the daemon db, driving prompts/clarifications/architectures/artifacts/kbites over the daemon, searching kbite knowledge, checking daemon/db health, or building the daemon.
---

# GMCC Daemon

A Swift package at `$GMCC_PLUGIN_ROOT/daemon/` shipping three binaries and a
shared library:

- **`gmcc_daemon`** — the persistent server, and the ONLY process that touches
  the SQLite db at `~/gmcc/gmcc.db` (single-writer model; WAL,
  foreign_keys=ON).
- **`gmcc_mcp`** — the pen. The MCP server Claude Code connects to, exposing the
  workflow machine as typed tools. This is Claude's record.
- **`gmcc_hook`** — the shell-callable client: hook events, session
  provisioning, health, the verb catalogue, and the raw-wire passthrough. It is
  on the session PATH.
- **`GMCCDaemonKit`** — shared library; GMVibes imports it by local package
  reference and speaks the same protocol.

Transport: NDJSON over a unix socket at `~/gmcc/daemon.sock`. Clients autostart
the daemon when the socket is dead. The handshake is DIRECTIONAL: across a
protocol-version bump a newer client makes the stale daemon self-exit, while an
older client is rejected and the daemon stays up. Within one protocol version a
rebuilt daemon is NOT auto-retired — stop the running one and let the next call
autostart the new binary.

Note: `~/gmcc/` (runtime: binaries, socket, db, log, pidfile, backups) is
distinct from `~/gmcc_ckfs/` (the CKFS tree). Neither is in git. The daemon
writes the db ONLY — it never touches ckfs files.

## Which door

| What you are doing | Door |
|---|---|
| Claude recording workflow state | the matching pen tool |
| any verb with no pen tool | `gmcc_hook call <MESSAGE_TYPE> --json '{...}'` |
| a shell hook, or a person at a terminal | the named `gmcc_hook` ops |

### The pen

Claude's own tool list is the signature reference — every pen tool carries its
typed schema, so nothing has to be looked up in prose. `bot_next` is the entry
point: it returns the current phase, its instructions, the uuid bundle and the
gate blockers without being told a uuid. `gmcc_hook pen-sheet` prints the same
context block SubagentStart hands a spawning agent.

### gmcc_hook ops

```
hook post-tool-use | subagent-start   wired in hooks/hooks.json — never run by hand
context ensure [--hook-payload]       provision project/instance/session from $PWD + branch
context env [--plugin-root P]         emit the session env block
paths [--json]                        resolved runtime roots
status | ping | daemon status         health (daemon status never autostarts)
verbs [--json] [--writes-only]        the verb catalogue
pen-sheet                             the agent context block
call <MESSAGE_TYPE> [--json '<payload>' | --json-file <path>]
```

### The passthrough

`gmcc_hook verbs --json` is the catalogue: every MessageType the daemon serves,
whether it reads or writes, and which pen tool covers it when one does. Keys are
sent verbatim and the wire is snake_case; the field list for a MessageType is its
`*Request` struct in
`daemon/Sources/GMCCDaemonKit/Protocol/Messages.swift`.

```bash
gmcc_hook call KBITE_GET --json '{"code":"swift_code_edit"}'
gmcc_hook call REVIEW_OPEN --json '{"prompt_uuid":"<U>"}'
gmcc_hook call EXPLORE_COMPLETE --json-file /tmp/overview.json
```

`--json-file` exists because ARG_MAX is smaller than the daemon's content caps:
a large overview, finding or intent body cannot be passed inline at all.
Responses are the raw wire JSON — the same shape a pen tool returns.

Exit codes: `0` ok · `1` the call failed (daemon unreachable, db or domain
error) · `2` usage: unknown command, unknown MessageType, or malformed payload.

Domain error codes (typed — branch on these, never parse messages): `NOT_FOUND`
(the uuid itself is unknown), `VERSION_CONFLICT` (stale `expected_version` —
re-run the matching get, take `.version`, retry), `INVALID_TRANSITION` (illegal
status jump; the reason names the legal next states), `CONTENT_LOCKED` (content
edit outside draft), `SUMMARY_ABSENT` (the owner exists but that summary/scope
was never opened — open it with the family's open/init call; never fall back to
a file).

Workflow semantics (prompt lifecycle, briefings, ratings, who seals what) live
in `skills/gmcc/ref/bot_workflows.md`, not here. For editing the repo's `.gmcc`
dope files directly, load `skills/gmcc/ref/doped_files.md`.

## Build / self-heal

If `gmcc_hook` is not on the PATH, or a call reports the daemon binary missing,
build first:

```bash
bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh
```

The script is staleness-checked (no-ops when binaries are current; `--force` to
override), stamps BuildInfo (git sha + date, returned by `gmcc_hook ping`), and
installs all three binaries into `~/gmcc/bin/`. It never restarts anything: a
rebuild leaves the running daemon stale, so stop it and let the next call
autostart the new binary. The SessionStart hook
`scripts/check_daemon_stale.sh` names any binary that is missing or older than
the sources — treat it as a prompt to run the build.

The full dev loop when changing daemon code:

```bash
cd $GMCC_PLUGIN_ROOT/daemon && swift test         # full suite; must stay green
bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh    # release build → ~/gmcc/bin/
gmcc_hook call SHUTDOWN --json '{}'               # stop the stale daemon
gmcc_hook ping                                    # autostarts the new one
```

Two lifecycle commands wrap these rules end-to-end: `/refresh_daemon_state`
(build if stale + restart if the running build predates the installed binaries +
verify) and `/archive_gmcc_daemon_data` (stop → move `gmcc.db*` + `daemon.log`
to `~/gmcc/_archive/cold_storage/{ts}/` → restart on a fresh db; never touches
the ckfs tree).

**Schema migration rule**: the db is append-only — schema changes land as new
migrations and existing databases upgrade in place at daemon boot, preserving
all data. **NEVER delete `~/gmcc/gmcc.db*`** to fix a schema error; take a
backup (`gmcc_hook call BACKUP --json '{}'`) before risky work. If calls fail
with "no such column" DB_ERRORs after an upgrade, the running daemon predates
the installed binaries: run `/refresh_daemon_state` so the new daemon applies
its pending migrations.

## Inspecting the db (read-only)

For debugging you may READ the db directly (`sqlite3 ~/gmcc/gmcc.db`), but never
write to it from outside the daemon — every write goes over the socket. Each
domain table carries the BaseEntity wrap (id serial PK, uuid v4 join key,
version — the optimistic-concurrency token, created_at/updated_at); all FKs
reference `uuid`; `daemon_event.id` is the append-only event-log replay cursor
(`gmcc_hook call EVENT_LIST --json '{"since_id":N}'`).
