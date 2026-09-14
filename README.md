# Green Mountain Kernel

Green Mountain Coding Collection — a Claude Code plugin marketplace for **contextual
development**, rebuilt on native framework/model work. The `gmcc` plugin turns Claude Code
into the GM-CDE (Green Mountain Contextual Development Environment): a workflow system that
authors, clarifies, and implements prompts against a persistent per-repo/per-branch
knowledge store on the **GMFS** (the Green Mountain filesystem), backed by reusable
knowledge bites (**kbites**).

## Status — what is live and what is not

This repository currently holds **two stacks side by side, deliberately**:

| | where | state |
|---|---|---|
| the stack that runs today | published from the `gmcc-marketplace` repo | live, untouched, keeps working |
| the new stack | `gmk/` in this repo (six Swift packages + the GMVibes app) | built and tested in parallel, **not installed** |

Everything under `plugins/gmcc/` is **frozen on purpose** while the new stack is brought
up: those files still carry the previously shipped binary names, environment variables and
filesystem layout, and they must, because that is what the running install expects. The
legacy literals are documented by the stack that ships them, not repeated here.

**This README documents the new names** — `gm_daemon` / `gm_mcp` / `gm_hook`, the single
`~/gmfs` root, the `GM_*` environment variables. They become the installed reality at
**cutover**, a separate later event. If you install the published plugin today, expect its
own legacy paths rather than the ones below, and do not treat the difference as a bug.

## Installation

### Prerequisites

- macOS (Apple Silicon or Intel) and [Claude Code](https://claude.ai/code) CLI installed
- `jq` (for the `/gm_init` permission grant) and `uuidgen` — both standard on macOS

No Swift toolchain is required. The binaries are downloaded prebuilt (universal, SHA-256
verified) by the installer script. Xcode is only needed if you intend to work on the
sources.

### Add the marketplace

1. Open Claude Code
2. Run `/plugins`
3. Select **Add Marketplace**
4. Enter: `brubinson/green-mountain-kernel`
5. Confirm

### Install the plugin

1. Run `/plugins`
2. Select **Install Plugin**
3. Choose `gmcc`

| Plugin | Version | Description |
|--------|---------|-------------|
| gmcc | 50.0.1 | GM-CDE plugin for contextual development |

## Setup (Quickstart)

GMCC needs a one-time, machine-level initialization. After that, every repository is
provisioned automatically.

### 1. Initialize the system (once per machine)

```
/gm_init
```

This creates the GMFS root at `~/gmfs/` with its `projects/` tree and an empty registry. It
also adds a permission grant to `~/.claude/settings.json` so the plugin can read and write
under `~/gmfs/` without per-file prompts.

**No shell profile is written.** GMCC never edits `~/.zshrc`; the environment reaches a
session through the `SessionStart` env block, and any remediation is printed for you to run,
never applied behind your back. The permission grant takes effect on the next Claude Code
restart.

### 2. Open Claude Code inside a git repository

The `SessionStart` hook detects the repo and branch and **auto-provisions** the project /
instance / session directories for you — no manual per-repo or per-branch command is needed:

```
~/gmfs/projects/{project}/instances/{checkout}/sessions/{branch}/
```

If `$GM_BOOTED` ever looks wrong, run the `gmcc:gmcc_boot` skill for diagnostics.

### 3. Run a workflow

```
/gm_bot <short-name> <what you want to do>
```

…or `/gm_task <request>` for a read-only, context-loaded one-off. See **Workflows** below.

To **run an already-drafted prompt** (e.g. one authored in the GMVibes editor), pass its
numeric id with no description: `/gm_bot {id}` (or `/gm_bot_rpi {id}` / `/gm_bot_team {id}`).
The bot picks up the draft and runs it from its current status. Passing a *name* instead
always starts a brand-new draft.

## Workflows

GMCC offers four entry points. All but `/gm_task` author a prompt into the current
session (a draft → clarifying → architecting → implementing → reviewing → done pipeline); `/gm_task` skips the ceremony.

| Command | Execution model | Best for | Requires |
|---------|-----------------|----------|----------|
| `/gm_bot` | Lightweight — all phases in primary context, no subagents | Quick, well-scoped changes | — |
| `/gm_bot_rpi` | Research/Plan/Implement — spawns explore, architecture & review subagents | Medium tasks needing exploration + review | — |
| `/gm_bot_team` | Agent teams — 4 teammates per phase, each on a different methodology | Large or high-stakes tasks | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` |
| `/gm_task` | Context-loaded but **read-only** — no prompt rows or clarifications | Applying GMCC context to a one-off without the prompt pipeline | — |

`/gm_task` is "read-only" with respect to the GMFS only — it still edits your repository
files. It writes nothing under `~/gmfs/` unless you explicitly ask for a retroactive
write-back later in the conversation.

## Capabilities

### KBite pipeline

| Command | Purpose |
|---------|---------|
| `/gm_crunch_open_maw <name>` | Open a *maw* (temporary processing dir) to collect resources |
| `/gm_maw_fetch <url…>` | Download web pages into a maw via headless Playwright |
| `/gm_crunch_chew <name>` | Analyze & summarize the maw's resources into chewed files |
| `/gm_crunch_digest <name>` | Move chewed resources into the persistent kbite |
| `/gm_kbite_relate <a> <b> "<reason>"` | Cross-reference two kbites |
| `/gm_kbite_export [name…]` | Zip selected kbites (root + digested) to a portable archive on the Desktop |
| `/gm_kbite_import <zip>` | Import a kbite archive into this machine's store (asks per name-collision) |

### Maintenance & system

| Command | Purpose |
|---------|---------|
| `/gm_init` | One-time machine-level system init (see Setup) |
| `/gmcc_session_cleanup` | Audit and repair the current session's stored structure |
| `/gmcc_cleanup_system` | Machine-level audit and repair across the whole store |
| `/gmcc_environment_cleanup` | Remove retired environment leftovers (including any legacy shell-profile block) |

Daemon status, build/self-heal and health diagnostics have their own command and skill in
the plugin's `gmcc:` namespace; run `/plugins` to list them. They are named for the stack
they drive, which is why this file points at the namespace instead of spelling the name.

## KBite system

KBites are persistent knowledge directories that store pre-analyzed reference material
(documentation, examples, APIs) for efficient lookup during development.

### Building a kbite

1. **Open a maw** (temporary processing directory):
   ```
   /gm_crunch_open_maw claude_code_sdk
   ```
2. **Add resources** — manually drop files into the maw, or fetch them:
   ```
   /gm_maw_fetch https://docs.claude.com/…
   ```
3. **Chew** — analyze and summarize:
   ```
   /gm_crunch_chew claude_code_sdk
   ```
4. **Digest** — promote into the persistent kbite:
   ```
   /gm_crunch_digest claude_code_sdk
   ```

Relate knowledge domains to each other:

```
/gm_kbite_relate claude_mcp claude_code_sdk "MCP builds on Claude Code plugin architecture"
```

### How kbites are loaded (v11+)

KBites are **inherited, not trigger-matched.** Each level of the store
(project → instance → session → prompt) carries a `kbite:` registry, and a prompt
inherits the kbites declared up its chain. A kbite is added to a context only on
**explicit request** (e.g. "add the `swift_ui` kbite") — there is no trigger-word
auto-activation (that paradigm was retired in v11; the old `KBITE_TRIGGERS.md` /
`KBITE_TRIGGER_MAP.md` files no longer exist).

KBites are stored under `~/gmfs/kbites/`:

```
kbites/
├── {name}/KBITE_PURPOSE.md      # identity / what this kbite is for
├── digested/{name}/…            # persisted indexes + chewed analysis
└── open/{name}/…                # in-progress maws
```

## Architecture (at a glance)

- **Swift packages** — `gmk/` holds six: `gmDaemonSdk` (wire protocol, client and the
  shared domain layer, plus the `gm_hook` client binary), `gmDaemon` (persistence and the
  `gm_daemon` server), `gmUxComponentLibrary` (shared SwiftUI components),
  `gmAgententicsSdk` (agent-tool protocols; the `gm_mcp` pen server moved into
  `gmDaemonSdk` at v30) and
  `gmVibes` (the macOS app). One Xcode project, `gmk/gmk.xcodeproj`, spans them, and
  `gmk/gmk.xcworkspace` opens that project together with every package as an editable
  workspace member.
- **Skills** — the core `gmcc` skill defines GM-CDE behavior; supporting skills
  (`gmcc_kbite`, `gmcc_maw`, `gmcc_cleanup`, …) carry
  `disable-model-invocation` so they load only during the relevant workflow, keeping
  per-message context lean. `gmcc_boot` runs on `SessionStart`.
- **Hook** — `SessionStart` runs the plugin's startup script, which provisions the store and
  exports the session environment (`GM_BOOTED`, `GM_PLUGIN_ROOT`, `GM_FS_ROOT`, `PATH`).
- **Write containment** — nothing is written outside `$GM_FS_ROOT` or the working repo
  unless you ask. That is enforced by a path check in the SDK, not just documented.
- **Contributor docs** — see `CLAUDE.md` for the build/test loop, the release procedure, and
  the two-stack rules above in full.

## Uninstalling

To remove the marketplace:

1. Run `/plugins`
2. Select **Manage Marketplaces**
3. Remove `green-mountain-kernel`

Your data under `~/gmfs/` is left untouched; delete it manually if you want a clean slate.

## License

MIT License — see [LICENSE](LICENSE) for details.
