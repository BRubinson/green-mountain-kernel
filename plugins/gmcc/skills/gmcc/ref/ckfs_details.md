# CKFS Detailed Structure Reference

Read this file on-demand when performing ckfs operations.

Prompt/session/instance/project data AND all four bot reports live in the
daemon's SQLite db at `~/gmcc/gmcc.db`. The ckfs on disk is a **file tree
only** — prompt-scoped scratch files under `memory/`, plus the kbite
content store.

Two channels reach the db: the **pen** (`mcp__plugin_gmcc_pen__*`, served by
`gmcc_mcp`) for everything that has a pen tool, and
`gmcc_hook call <MESSAGE_TYPE> --json '{...}'` for everything else.
`gmcc_hook verbs --json` is the catalogue. See
`skills/gmcc_daemon/SKILL.md`.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest
├── skills/
│   ├── gmcc/SKILL.md              # Core rules (slim)
│   ├── gmcc/ref/                  # Reference files (read on-demand)
│   ├── gmcc_daemon/               # Daemon + pen invocation reference
│   ├── gmcc_kbite/                # KBite knowledge system
│   ├── gmcc_maw/                  # KBite web-fetch skill
│   ├── gmcc_boot/                 # Boot validation
│   └── gmcc_cleanup/              # Environment auditing
├── commands/gm_*.md               # All GM commands
├── agents/*.md                    # Native agent defs (gmcc:code-explorer, doper, …) — identity + pen contract
├── prompts/gmcc_agent_*.md        # Crunch/maw agent prompts (the bot roles live in agents/)
├── scripts/gmcc_session_startup.sh         # SessionStart hook script
├── scripts/gmcc_hook.sh                    # Every non-SessionStart hook; event as argv, payload to `gmcc_hook hook`
├── scripts/build_daemon.sh        # Builds + installs all three binaries
├── scripts/check_daemon_stale.sh  # SessionStart staleness warning
├── scripts/run_mcp.sh             # Launches gmcc_mcp for the pen server
├── daemon/                        # Swift package: GMCCDaemonKit + gmcc_daemon + gmcc_mcp + gmcc_hook
└── hooks/hooks.json               # Hook configuration (SessionStart, SubagentStart, PostToolUse)
```

## Runtime Layout (Per-User)
```
~/gmcc/                                                       # daemon runtime (NOT in git)
├── bin/{gmcc_daemon, gmcc_mcp, gmcc_hook}
├── gmcc.db                                                   # SQLite — single source of truth for runtime data
├── daemon.sock · daemon.log · daemon.pid · backups/

~/gmcc_ckfs/                                                  # $GMCC_CKFS_ROOT — file artifacts only
├── README.md
├── _archive/cold_storage/                                    # universal archive bucket (structure-preserving)
├── projects/
│   └── {project_name}/                                       # project ckfs_relative_storage_path
│       └── instances/
│           └── {project_name}_{hash4}/                       # instance ckfs_relative_storage_path
│               └── sessions/
│                   └── {sanitized_branch}/                   # session's artifact home
│                       └── prompts/
│                           └── {id}_{name}/                  # one folder per prompt
│                               └── memory/                  # usually empty — every report
│                                                             # is a db row
└── kbites/                                                   # kbite_root (gmcc_hook paths --json)
    ├── {kbite_name}/KBITE_PURPOSE.md                         # identity-level
    ├── digested/{kbite_name}/...                             # kbite_digested_root — raw-source archive (text is db-canonical)
    └── open/{kbite_name}/...                                 # kbite_open_root — in-progress maws
```

Each row carries its own `ckfs_relative_storage_path`; the roots come from
`gmcc_hook paths --json`. The db stores **pointers + captions** to the
`memory/*.md` files (`prompt_artifact` rows) — never their bodies. The
daemon never writes files; bot workflows create the folders and write the
markdown, then register each file with `ARTIFACT_ADD`.

## Identity Resolution (How a path becomes a session)

Identity is derived daemon-side by `gmcc_hook context ensure`
(`GitContext`/`ContextBuilder` in Swift). Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `gmcc-marketplace` |
| `instance_code` | `{project_name}_{4-char hash of abs path}` | e.g. `gmcc-marketplace_a3f2` |
| `session_code` | Sanitized current git branch | e.g. `v4_2`, `feature__login` |

### Instance Code Algorithm

```
INSTANCE_CODE = "{basename($REPO_ROOT)}_{first 4 chars of md5($REPO_ROOT)}"
```

- Deterministic from `$REPO_ROOT` (always re-derivable).
- Collision-resistant: requires two repos with the same basename AND the same 4-char hash.
- Machine-safe by construction: only `[a-z0-9\-_]` characters from the basename + hex hash.

### Branch Slugification Rules
- Replace every `/` with `__` (literal two underscores).
- Implementation uses `sed 's|/|__|g'` — NOT `tr`, because `tr` is char-to-char and would collapse `/` into a single `_`.

A project corresponds to exactly one git repo (by basename). An instance is a unique filesystem checkout of that repo — moving the checkout to a new path creates a new instance. A session is one git branch within an instance.

## Lazy Creation on SessionStart

On every SessionStart, `gmcc_session_startup.sh`:

1. Confirms the git repo, locates the plugin root, and locates the right
   `gmcc_hook` binary (prod runtime, or the sandbox runtime named by a
   `.gmcc_sandbox` marker). It computes nothing the daemon computes.
2. Calls `gmcc_hook context ensure --hook-payload` (best-effort):
   idempotently upserts the project → instance → session rows in the db
   (reusing existing uuids, seeding kbite inheritance at create time), pins
   the claude session binding every later hook write resolves through,
   creates the session's artifact home
   (`{ckfs_relative_storage_path}/prompts/` under `$GMCC_CKFS_ROOT` — the
   physical home for prompt `memory/` folders), and runs the dope boot
   sync. If the daemon/binary is unavailable it warns and continues.
3. Prints the pen sheet (`gmcc_hook pen-sheet`) into the session's context.
4. Emits the session env via `gmcc_hook context env` into
   `$CLAUDE_ENV_FILE`: `GMCC_BOOTED`, `GMCC_PLUGIN_ROOT`, `GMCC_CKFS_ROOT`,
   `PATH` (the active runtime's `bin/` first, so bare `gmcc_hook` resolves
   to the correct prod/sandbox binary), plus `GMCC_ROOT` when sandboxed.
   Per-level path vars do not exist — roots come from `gmcc_hook paths` and
   per-row locations from `ckfs_relative_storage_path`.

This means **commands can always assume the env + session dir exist**;
db rows exist whenever the daemon was reachable at SessionStart (and
`gmcc_hook context ensure` may be re-run by any command at any time — it is
idempotent).

## Db-Backed Data Model

Rows follow the BaseEntity wrap (`id` serial PK, `uuid` v4 join key,
`version` optimistic-concurrency token, `created_at`/`updated_at`).
Hierarchy: `project → instance → session → prompt`, plus
`prompt_artifact` (file pointers), `session_file`/`file_change`/
`file_change_range` (edit tracking), `kbite` + `*_active_kbite`
junctions (registry), `daemon_event` (append-only audit log).

Key reads — the pen first, the passthrough for what it does not cover:

```
prompt_get         full content + artifacts + kbite codes + change summary
bot_current_prompt the workflow's prompt row, without being told a uuid
file_change_list   recorded edits for a prompt (or a session, or one path)
```

```bash
gmcc_hook context ensure                                   # uuid triple for $PWD + branch
gmcc_hook call SESSION_GET  --json '{"session_uuid":"U"}'  # session row + prompt stubs + change summaries
gmcc_hook call PROMPT_LIST  --json '{"session_uuid":"U","with_reports":true}'
gmcc_hook call ARTIFACT_LIST --json '{"prompt_uuid":"U"}'
gmcc_hook call SEARCH       --json '{"query":"<topic>"}'   # across reports
```

### Optimistic concurrency (`expected_version`)

Every mutation (`SESSION_UPDATE`, `PROMPT_UPDATE_CONTENT`,
`prompt_set_status`, every pen write) carries `expected_version` — the row
version the edit was based on. Capture `version` from the previous
create/get/mutation (a fresh create returns `version: 0`; each mutation
returns the incremented version). A stale version yields
`VERSION_CONFLICT`: re-get and retry. It is a normal outcome of concurrent
work, not an error to report.

## Prompt Folder Layout

Each prompt is a folder whose `memory/` subdir is usually EMPTY:

```
prompts/{id}_{name}/
    memory/                          # prompt-scoped scratch files only
```

All four phase reports are DB-NATIVE (clarification, architecture,
exploration, review rows). NEVER write a report as a file here. The
`mkdir` of `memory/` at prompt creation stays: it is where any other
prompt-scoped file you register as an artifact lands.

`{id}` is the db prompt row's `seq`; `{name}` its `name`. All identity,
content (`backstory`/`goal`/`detail`), status, and command live on the
prompt row. Any file you write under `memory/` is registered with:

```bash
gmcc_hook call ARTIFACT_ADD --json \
  '{"prompt_uuid":"U","file_path":"<abs path>","note":"<one-sentence caption>"}'
```

(Upserts on `(prompt_uuid, file_path)` — last-run-wins overwrite of the
file is fine; re-register to refresh the note.)

## Prompt Lifecycle

Statuses are lowercase: `draft → clarifying → architecting → implementing
→ reviewing → done`, forward-only + adjacent-only with one skip edge
`implementing → done` (reviewing optional); `INVALID_TRANSITION`
otherwise. Content edits are draft-only (`CONTENT_LOCKED` after).
Gates: entering `clarifying` creates the clarification summary;
`clarifying → architecting` requires it complete; `architecting →
implementing` requires the architecture approved. There is no bypass — an
absent backing row fails the gate.

1. **draft** — `/gm_bot*` runs `prompt_init` with `create: true`, `name`,
   `detail` and `variant`. STAY TRUE: `detail` = the entire passed prompt
   verbatim; `goal` = "" (human/clarify input only); `backstory` inherited
   from the session row. Never split, infer, or author these fields. Then
   `mkdir -p prompts/{seq}_{name}/memory/` from the returned
   `ckfs_relative_storage_path`.
2. **clarifying** — enter with `prompt_set_status status: clarifying` (it
   locks content and the daemon creates the summary). The clarifier then
   writes `clarify_question_add` (+ option rows) and `clarify_note_add`;
   the primary seals with `CLARIFY_SEAL`; the user answers via
   `CLARIFY_ANSWER` (`selected_option_uuids` / `answer_text` / `skip`);
   optional care package; `CLARIFY_FINALIZE` is a PURE GATE — nothing ever
   writes prompt content past draft (STAY TRUE).
3. **architecting → implementing → reviewing → done** — architecture rows
   (persistence first) → `ARCH_PROPOSE`/`ARCH_APPROVE` → implement (the
   PostToolUse hook captures every edit) → optional review → done,
   threading `expected_version` through each step.

Resume across sessions is `prompt_init` with the prompt's selector, then
`bot_next`: status, content and artifact pointers all come back from the
db.

## File Change Tracking

File changes capture themselves. The PostToolUse hook records every
Edit/Write/NotebookEdit with real line ranges from the tool's own patch,
and a Bash write only when the command NAMES its target — so nothing
self-reports its own edits.

`file_change_add` exists for a change no tool call made:

```
mcp__plugin_gmcc_pen__file_change_add
  path: <repo-relative>   kind: edit|create|delete|rename
  prompt_uuid: <U>
```

Run from inside the repo — git context is auto-detected. Run completion is
prompt status `done` plus the clarification/architecture/exploration/review
rows and registered artifacts; there is no phase-history equivalent.
`arch_get` derives per-change implementation state from these records.

## KBite Registry

Kbites are inherited at create time down the chain
(project → instance → session → prompt) into the `*_active_kbite`
junction tables; after seeding, each level is independent. The db is the
sole registry. Read the active list as `kbite_codes` on `prompt_get` or
`SESSION_GET`, or list a scope:

```bash
gmcc_hook call KBITE_LIST --json '{"scope":"session","owner_uuid":"U"}'   # "all": true for every kbite row
gmcc_hook call KBITE_ADD  --json '{"scope":"session","owner_uuid":"U","code":"C"}'
```

Kbites are added only on explicit user request — see
`ref/kbite_awareness.md`. Digested kbite text is db-canonical: load it via
`kbite_search` / `kbite_file_get`, not from the filesystem.
