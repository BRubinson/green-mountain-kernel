# GMCC Marketplace

Green Mountain Compiler Collection — a Claude Code plugin marketplace for **contextual
development**. The `gmcc` plugin turns Claude Code into the GM-CDE (Green
Mountain Contextual Development Environment): a workflow system that authors, clarifies,
and implements prompts against a persistent per-repo/per-branch knowledge store (the
**ckfs**), backed by reusable knowledge bites (**kbites**).

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- `jq` (for the `/gm_init` permission grant) and `uuidgen` — both standard on macOS

### Add the marketplace

1. Open Claude Code
2. Run `/plugins`
3. Select **Add Marketplace**
4. Enter: `brubinson/gmcc-marketplace`
5. Confirm

### Install the plugin

1. Run `/plugins`
2. Select **Install Plugin**
3. Choose `gmcc`

| Plugin | Version | Description |
|--------|---------|-------------|
| gmcc | 14.0.0 | GM-CDE plugin for contextual development |

## Setup (Quickstart)

GMCC needs a one-time, machine-level initialization. After that, every repository is
provisioned automatically.

### 1. Initialize the system (once per machine)

```
/gm_init
```

This creates `~/gmcc_ckfs/` (the Context Knowledge File System) with the `projects/`
root and an empty registry. It also:

- writes a `# >>> gmcc env >>>` block to `~/.zshrc` exporting the stable `GMCC_*` paths, and
- adds a CKFS permission grant to `~/.claude/settings.json` so the plugin can read/write
  under `~/gmcc_ckfs/` without per-file prompts.

Run `source ~/.zshrc` (or open a new terminal) afterward. The permission grant takes
effect on the next Claude Code restart.

### 2. Open Claude Code inside a git repository

The `SessionStart` hook (`scripts/gmcc_session_startup.sh`) detects the repo and branch and
**auto-provisions** the project / instance / session directories for you — no manual
per-repo or per-branch command is needed:

```
~/gmcc_ckfs/projects/{project}/instances/{checkout}/sessions/{branch}/
```

If `$GMCC_BOOTED` ever looks wrong, run `/gmcc_boot` for diagnostics.

### 3. Run a workflow

```
/gm_bot <short-name> <what you want to do>
```

…or `/gm_task <request>` for a read-only, context-loaded one-off. See **Workflows** below.

To **run an already-drafted prompt** (e.g. one authored in the GMVibes editor), pass its
numeric id with no description: `/gm_bot {id}` (or `/gm_bot_rpi {id}` / `/gm_bot_team {id}`).
The bot picks up the draft and runs it from its current status. Passing a *name* instead
always starts a brand-new draft.

> Migrating from an older layout? Run `/gm_cleanup` to audit and repair your ckfs.

## Workflows

GMCC offers four entry points. All but `/gm_task` author a prompt into the current
session (a draft → clarifying → architecting → implementing → reviewing → done pipeline); `/gm_task` skips the ceremony.

| Command | Execution model | Best for | Requires |
|---------|-----------------|----------|----------|
| `/gm_bot` | Lightweight — all phases in primary context, no subagents | Quick, well-scoped changes | — |
| `/gm_bot_rpi` | Research/Plan/Implement — spawns explore, architecture & review subagents | Medium tasks needing exploration + review | — |
| `/gm_bot_team` | Agent teams — 4 teammates per phase, each on a different methodology | Large or high-stakes tasks | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` |
| `/gm_task` | Context-loaded but **read-only** — no prompt rows or clarifications | Applying GMCC context to a one-off without the prompt pipeline | — |

`/gm_task` is "read-only" with respect to the ckfs only — it still edits your repository
files. It writes nothing under `~/gmcc_ckfs/` unless you explicitly ask for a retroactive
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
| `/gm_kbite_import <zip>` | Import a kbite archive into the current ckfs (asks per name-collision) |

### Maintenance & system

| Command | Purpose |
|---------|---------|
| `/gm_init` | One-time machine-level system init (see Setup) |
| `/gm_cleanup` | Audit the ckfs for non-compliant structure and interactively repair each finding |
| `/gm_bot_v4_migrate_kbite` | One-shot migration of legacy v4 kbites to the current layout |

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

KBites are **inherited, not trigger-matched.** Each level of the ckfs
(project → instance → session → prompt) carries a `kbite:` registry, and a prompt
inherits the kbites declared up its chain. A kbite is added to a context only on
**explicit request** (e.g. "add the `swift_ui` kbite") — there is no trigger-word
auto-activation (that paradigm was retired in v11; the old `KBITE_TRIGGERS.md` /
`KBITE_TRIGGER_MAP.md` files no longer exist).

KBites are stored under `~/gmcc_ckfs/kbites/`:

```
kbites/
├── {name}/KBITE_PURPOSE.md      # identity / what this kbite is for
├── digested/{name}/…            # persisted indexes + chewed analysis
└── open/{name}/…                # in-progress maws
```

## Architecture (at a glance)

- **Skills** — the core `gmcc` skill defines GM-CDE behavior; supporting skills
  (`gmcc_agent`, `gmcc_kbite`, `gmcc_maw`, `gmcc_cleanup`) carry
  `disable-model-invocation` so they load only during the relevant workflow, keeping
  per-message context lean. `gmcc_boot` runs on `SessionStart`.
- **Hook** — `SessionStart` → `scripts/gmcc_session_startup.sh` provisions the ckfs and exports
  the `GMCC_*` environment variables.
- **Output styles** — four GMCC personas (aggressive / alternative / conservative /
  pragmatic) you can switch between.

See `plugins/gmcc/MIGRATION.md` for version-to-version migration notes.

## Uninstalling

To remove the marketplace:

1. Run `/plugins`
2. Select **Manage Marketplaces**
3. Remove `gmcc-marketplace`

Your ckfs data under `~/gmcc_ckfs/` is left untouched; delete it manually if you want a
clean slate.

## License

MIT License — see [LICENSE](LICENSE) for details.
