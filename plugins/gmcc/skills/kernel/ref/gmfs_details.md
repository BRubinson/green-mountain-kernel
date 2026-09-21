# GMFS Detailed Structure Reference

Read this file on-demand when performing gmfs operations.

Prompt/session/instance/project data AND all four bot reports live in the
daemon's SQLite db at `~/gmfs/gm.db`. The gmfs on disk is a **file tree
only** — prompt-scoped scratch files under `memory/`, plus the kbite
content store.

The **pen** (`mcp__plugin_gmcc_cde__*`, served by `gm_mcp`) is the agent's
ONLY channel. The kernel's CLI is the harness's client — the hooks call it,
an agent never does, and the PreToolUse hook denies it from Bash. A verb
with no pen tool is a missing door to report. See the `kernel` skill.

## Static Plugin Files (Installed to ~/.claude/plugins/gmcc/)
```
~/.claude/plugins/gmcc/
├── .claude-plugin/plugin.json     # Plugin manifest
├── skills/
│   ├── gmcc/SKILL.md              # Core rules (slim)
│   ├── gmcc/ref/                  # Reference files (read on-demand)
│   ├── gm_daemon/               # Daemon + pen invocation reference
│   ├── gmcc_kbite/                # KBite knowledge system
│   ├── gmcc_maw/                  # KBite web-fetch skill
│   ├── gmcc_boot/                 # Boot validation
│   └── gmcc_cleanup/              # Environment auditing
├── commands/gm_*.md               # All GM commands
├── agents/*.md                    # Native agent defs (gmcc:code-explorer, briefer, …) — identity + pen contract
├── prompts/gmcc_agent_*.md        # Crunch/maw agent prompts (the bot roles live in agents/)
├── scripts/gm_session_startup.sh         # SessionStart hook script; runs bin/gm_hook
├── bin/gm_mcp                            # The pen server, compiled with the client closure; .mcp.json execs it
├── bin/gm_hook                           # The shell client (context ensure/env, call passthrough)
├── bin/src/gm_{mcp,hook}.swift           # Their generated mains; built by gmk/scripts/build_plugin_binaries.sh
├── hooks/bin/gm_hook_<event>             # One compiled executable per hooked event (PreToolUse, PostToolUse, SubagentStart)
├── hooks/src/gm_hook_<event>.swift       # Its generated main; same builder
├── scripts/install_gm.sh          # Installs the kernel app + stages gm_kernel/gm_daemon into $GM_FS_ROOT/bin
├── scripts/gm_releases.sh         # The release-store contract (staging, activation, rollback)
└── hooks/hooks.json               # Hook configuration (SessionStart, SubagentStart, PreToolUse, PostToolUse)
```

**The plugin ships no Swift sources.** The packages live in `gmk/` in the
green-mountain-kernel repo and are built by `gmk/scripts/rebuild_local.sh`;
`gmk/scripts/publish_release.sh` tags and uploads them. Neither script is part
of the plugin payload, so installing the plugin does not distribute them.

## Runtime Layout (Per-User)
```
~/gmfs/                                                       # $GM_FS_ROOT — ONE root (NOT in git)
├── bin/
│   ├── gm_kernel, gm_daemon                                  # symlinks -> releases/active/gm_kernel (gm_mcp/gm_hook ship in the plugin)
│   ├── .gm_version                                           # active version ("50.0.1" or "50.0.1-BETA")
│   └── releases/
│       ├── active -> downloads/50.0.1
│       ├── downloads/{version}/                              # fetched from a daemon-v* release
│       └── local/{version}-BETA/                             # built by gmk/scripts/rebuild_local.sh
├── gm.db                                                     # SQLite — single source of truth for runtime data
├── daemon.sock · daemon.log · daemon.pid · backups/
├── README.md
├── _archive/cold_storage/                                    # universal archive bucket (structure-preserving)
├── projects/
│   └── {project_name}/                                       # project gmfs_relative_storage_path
│       └── instances/
│           └── {project_name}_{hash4}/                       # instance gmfs_relative_storage_path
│               └── sessions/
│                   └── {sanitized_branch}/                   # session's artifact home
│                       └── prompts/
│                           └── {id}_{name}/                  # one folder per prompt
│                               └── memory/                  # usually empty — every report
│                                                             # is a db row
└── kbites/                                                   # kbite_root
    ├── {kbite_name}/KBITE_PURPOSE.md                         # identity-level
    ├── digested/{kbite_name}/...                             # kbite_digested_root — raw-source archive (text is db-canonical)
    └── open/{kbite_name}/...                                 # kbite_open_root — in-progress maws
```

Each row carries its own `gmfs_relative_storage_path`; every root above
resolves under `$GM_FS_ROOT`. The db stores **pointers + captions** to the
`memory/*.md` files (`prompt_artifact` rows) — never their bodies. The
daemon never writes files; bot workflows create the folders and write the
markdown. Registering a file as an artifact has no pen tool — see "Prompt
Folder Layout" below.

## Identity Resolution (How a path becomes a session)

Identity is derived daemon-side by the SessionStart hook
(`GitContext`/`ContextBuilder` in Swift). Given a git repository:

| Concept | Source | Derived value |
|---------|--------|---------------|
| `project_name` | `basename $(git rev-parse --show-toplevel)` | e.g. `green-mountain-kernel` |
| `instance_code` | `{project_name}_{4-char hash of abs path}` | e.g. `green-mountain-kernel_a3f2` |
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

On every SessionStart, the harness runs `gm_session_startup.sh`, which
hands the work to the kernel's own client. THE HARNESS CALLS IT; AN AGENT
NEVER DOES. What it does:

1. Confirms the git repo and locates the plugin root and the kernel under
   the one runtime root. It computes nothing the daemon computes.
2. Ensures context (best-effort): idempotently upserts the project →
   instance → session rows in the db (reusing existing uuids, seeding
   kbite inheritance at create time), pins the claude session binding
   every later hook write resolves through, creates the session's
   artifact home (`{gmfs_relative_storage_path}/prompts/` under
   `$GM_FS_ROOT` — the physical home for prompt `memory/` folders), and
   runs the dope boot sync. If the daemon is unavailable it warns and
   continues.
3. Prints the pen sheet into the session's context.
4. Emits the session env into `$CLAUDE_ENV_FILE`: `GM_BOOTED`,
   `GM_PLUGIN_ROOT`, `GM_FS_ROOT`, `PATH`. Per-level path vars do not
   exist — roots resolve under `$GM_FS_ROOT` and per-row locations from
   `gmfs_relative_storage_path`.

This means **commands can always assume the env + session dir exist**;
db rows exist whenever the daemon was reachable at SessionStart. If they
do not, restart the session: the hook is idempotent and re-running it is
the harness's move, not an agent's.

## Db-Backed Data Model

Rows follow the BaseEntity wrap (`id` serial PK, `uuid` v4 join key,
`version` optimistic-concurrency token, `created_at`/`updated_at`).
Hierarchy: `project → instance → session → prompt`, plus
`prompt_artifact` (file pointers), `session_file`/`file_change`/
`file_change_range` (edit tracking), `kbite` + `*_active_kbite`
junctions (registry), `daemon_event` (append-only audit log).

Key reads, all pen tools:

```
cde_prompt op load          full content + artifacts + kbite codes + change summary
cde_prompt op file_changes  recorded edits for a prompt (or a session, or one path)
cde_session op search       projects, instances and sessions by name or id
cde_rpir_search             full text over past explorations, clarifications, plans, reviews
```

A session-wide prompt listing, an artifact listing and a cross-report
search have no pen tool. That is a missing door to report, not a cue to
shell to the kernel — the PreToolUse hook denies it.

### Optimistic concurrency (`expected_version`)

Every mutation (`cde_session` op `update`, `cde_prompt` op `set_status`,
every pen write) carries `expected_version` — the row
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
prompt row. Registering a file written under `memory/` as an artifact has
no pen tool: name the file and its one-sentence caption in your report so
the Endotherm can register it. (Registration upserts on
`(prompt_uuid, file_path)`, so a last-run-wins overwrite of the file is
fine.)

## Prompt Lifecycle

Statuses are lowercase and there are THREE: `draft → initiated → done`,
plus `done → draft` to re-open a finished prompt for editing;
`INVALID_TRANSITION` otherwise. Content edits are draft-only
(`CONTENT_LOCKED` after) — which is also what makes the reverse edge useful.

Status says only whether a prompt is unstarted, running, or finished. WHERE
it is in the workflow is derived from db evidence at every `bot_next`.
Gates: entering `clarifying` creates the clarification summary;
`clarifying → architecting` requires it complete; `architecting →
implementing` requires the architecture approved. There is no bypass — an
absent backing row fails the gate.

1. **draft** — `/gm_bot*` runs `prompt_init` with `create: true`, `name`,
   `detail` and `variant`. STAY TRUE: `detail` = the entire passed prompt
   verbatim; `goal` = "" (human/clarify input only); `backstory` inherited
   from the session row. Never split, infer, or author these fields. Then
   `mkdir -p prompts/{seq}_{name}/memory/` from the returned
   `gmfs_relative_storage_path`.
2. **initiated** — the prompt leaves draft when its briefing opens
   (`BRIEFING_OPEN` stamps it, daemon-side and idempotently); loading a prompt
   never moves it. Everything from briefing through review happens in this one
   state, and each phase opens its OWN summary rather than getting one as a side
   effect of a status change: `CLARIFY_OPEN`, `ARCH_OPEN`, `REVIEW_OPEN`.
   The clarifier writes `clarify_question_add` (+ option rows) and
   `clarify_note_add`; the primary seals with `CLARIFY_SEAL`; the user answers
   via `CLARIFY_ANSWER` (`selected_option_uuids` / `answer_text` / `skip`);
   optional care package; `CLARIFY_FINALIZE` is a PURE GATE — nothing ever
   writes prompt content past draft (STAY TRUE). Then architecture rows
   (persistence first) → `ARCH_PROPOSE`/`ARCH_APPROVE` → implement (the
   PostToolUse hook captures every edit) → optional review, threading
   `expected_version` through each step.
3. **done** — `prompt_set_status status: done` releases the activation claim and
   closes the workflow row. `done → draft` is legal and is how a finished prompt
   is re-opened for editing; a second run gets its own summaries.

**Where a prompt is in its workflow is NOT its status.** Phase is derived from
db evidence at every `bot_next` — twelve phases against three states — so ask
the machine rather than reading `prompt.status`.

Resume across sessions is `prompt_init` with the prompt's selector, then
`bot_next`: status, content and artifact pointers all come back from the
db.

## File Change Tracking

File changes capture themselves. The PostToolUse hook records every
Edit/Write/NotebookEdit with real line ranges from the tool's own patch,
and a Bash write only when the command NAMES its target — so nothing
self-reports its own edits.

File-change capture is OWNED BY THE PostToolUse HOOK, whose matcher covers
Edit, Write, NotebookEdit AND Bash — shell-made edits are captured too. There
is deliberately no pen door for FILE_CHANGE_ADD, and agents never invoke the
capture write themselves under any spelling: a hand-typed capture row is a
forgery of the machine's own record.

Run completion is
prompt status `done` plus the clarification/architecture/exploration/review
rows and registered artifacts; there is no phase-history equivalent.
`arch_get` derives per-change implementation state from these records.

## KBite Registry

Kbites are inherited at create time down the chain
(project → instance → session → prompt) into the `*_active_kbite`
junction tables; after seeding, each level is independent. The db is the
sole registry. Read the active list as `kbite_codes` on `cde_load_prompt`.
Listing a scope's registry and adding a kbite to one have no pen tool;
both are operator acts.

Kbites are added only on explicit user request, and then by reporting the
request rather than performing it — see
`ref/kbite_awareness.md`. Digested kbite text is db-canonical: load it via
`kbite_search` / `kbite_file_get`, not from the filesystem.
