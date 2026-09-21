import Foundation

// The reference documents and prompt bodies, transcribed verbatim.
//
// Embedded in extended delimiters so the markdown needs no escaping. Several
// bodies carry backslashes and fenced code blocks, and a missed escape in a plain
// literal is a silently corrupted document rather than a compile error.

extension GmBridgeResource {

    static let dopedFiles = GmBridgeResource(
        skill: "dope",
        path: "ref/doped_files.md",
        summary:
            "How the .gmcc/ dope tree maps to disk, and what a dot-path code resolves to. Read before writing dope or chasing a stale scope.",
        body: #"""
            # DOPED Files — the on-disk `.gmcc` reference

            ## When to read this

            Read this **only when you are building or editing a repo's `.doped.json`
            files directly** — authoring a tree from scratch, repairing a hand-edit, or
            reviewing a diff of `.gmcc/`.

            A normal bot run does **not** need this file. The bot tiers reach dope
            search-first through the pen (`cde_dope` op `search_session`, then op
            `search_global` by `code`) and never touch the files; that protocol lives
            in the `cde_rpir_*` phase skills and is unaffected by anything here.

            ## The supported path

            The db is the editing surface. The files are a **publication** of it.
            The one pen door from db to files is `cde_dope` op `update_session`
            (scope_uuid; `force` writes even when the repo has diverged).

            Granular node edits — add or update one node at one level (persistence,
            entity, property, enum, option) — and hand-edit reconciliation (parse and
            validate the tree, plan a db-vs-files merge, resolve one dot-path either
            way) are kernel verbs with NO pen tool. They are operator acts, reached
            from GMVibes, not from an agent. A missing door is a fact to report to the
            Endotherm; the shell is not a way around it, and the PreToolUse hook denies
            it.

            Only a `SESSION_INSTANCE` scope is repo-writable.

            ## Layout

            Everything sits directly under `{instance_root}/.gmcc/` — there is **no
            `dope/` level** (`.gmcc/dope/` and `main.doped.json` are the retired layout,
            named in the code only so a stale checkout can be recognised and reported).

            ```
            .gmcc/
              scope.doped.json
              persistence/{domain}/
                {domain}.index.persistence.doped.json
                {domain}.entity.{entity}.persistence.doped.json
                {domain}.enum.{enum}.persistence.doped.json
              cogs/{cog}/
                {cog}.index.cog.doped.json
            ```

            One domain is a **directory of files**, not one file.

            ## File shape

            **Bodies inline at the TOP LEVEL of each file.** They are not nested under a
            `body` key — each document encodes its body, then adds its extra keys as
            siblings. This is the single thing most often gotten wrong.

            | File | Top-level body | Plus |
            |---|---|---|
            | `scope.doped.json` | — | `version`, `scope{code,name,description}`, `persistence{code→path}`, `cogs{code→path}` |
            | `{d}.index.persistence.doped.json` | the domain body | `version`, `entities{code→filename}`, `enums{code→filename}` |
            | `{d}.entity.{e}.persistence.doped.json` | the entity body | `version`, `properties[]` |
            | `{d}.enum.{n}.persistence.doped.json` | the enum body | `version`, `options[]` |
            | `{c}.index.cog.doped.json` | the cog body | `elements[]` |

            Two shape facts that are easy to miss:

            - `scope.doped.json` deliberately carries **no `scope_type`**. Only a
              `SESSION_INSTANCE` tree can be written to a repo, so storing the field
              would record a constant and invite a hand-edit that contradicts the one
              tier that is structurally possible. An older file that still carries the
              key decodes with it ignored.
            - Every **persistence** file carries `version`. **Cog index files do not.**

            **Fields are owned by the level.** The keys on each body are exactly the
            `fields` a `DOPE_NODE_ADD` carries at that level, and `DopeLevelSpec`'s
            `ownedFields` registry (`Dope/DopeLevel.swift`) states which subset is legal
            where — a misdirected field is a precise `BAD_REQUEST`, not a silent no-op.
            Do not invent keys, and do not expect a field list here: duplicating one is
            how a reference goes stale.

            ## Rules that refuse a write

            These are enforced, not stylistic. Breaking one corrupts a repo or gets the
            read thrown out.

            **Naming**

            - Filenames key on **CODES**, never display names. Codes are what dot-path
              refs resolve against, they survive a rename, and they cannot collide on a
              case-insensitive filesystem the way two differently-cased names would.
            - A directory or file name and the `code` declared inside it must agree.
            - Code grammar: `^[a-z][a-z0-9_]*$`, no `__`, no trailing `_`, ≤ 64 bytes.

            **The map is data, never followed** — at *both* levels.

            `scope.doped.json`'s `persistence`/`cogs` maps and each domain index's
            `entities`/`enums` maps are read as data. The reader **re-derives** every
            path from its KEY and refuses a written path that disagrees. A hand-edited
            index therefore cannot redirect a read — or a prune — outside its own
            directory. If you rename a file, rename its key; do not repoint the value.

            **Refs are dot-path codes, never uuids**

            | Form | Segments | Example |
            |---|---|---|
            | property | 3 | `project.prompt.status` |
            | enum | 3, middle literally `enums` | `project.enums.prompt_status` |
            | base composable | strictly 2 | `base.base_entity` |

            `enums` is **reserved**: no entity may carry that code. That reservation is
            what makes both 3-segment forms unambiguous.

            **Versions**

            `version` appears in `scope.doped.json` and in every index/entity/enum file,
            and they must all agree. It *is* `dope_scope.revision`. A mismatch is
            reported as a suspected hand-edit.

            **Tombstones**

            `deleted_on` **never** appears in a written file. Soft deletes are a masking
            overlay mechanism (`PROJECT_ITEM` / `SESSION_INSTANCE_ITEM`), and those tiers
            are not repo-writable at all. A `deleted_on` key in `.gmcc` is always wrong.

            **Validator rules**

            Description caps: scope 512, domain 512, entity 512, enum 256, property 128,
            option 128.

            - `entity_type` ∈ `MODEL | JUNCTION | BASE_COMPOSABLE`
            - `enum_ref` present **iff** `data_type == "enum"`
            - `relationship_target_ref` present **iff** `data_type == "relationship"`
            - `auto_increment` only on `long`; `text_char_limit` only on `text`
            - a relationship may not target another relationship (no chains)
            - `base_composable_ref` must target a `BASE_COMPOSABLE`; chaining is allowed,
              cycles are not
            - `base_origin_ref` must resolve to a property on a `BASE_COMPOSABLE` that
              this entity actually composes **down** the chain, with a matching
              `data_type`

            The validator **collects every error and throws once**, as a numbered list.
            Fix the whole list in one pass; do not iterate one error at a time.

            ## Writing safely

            `.gmcc/` is **not exclusively dope-owned** — `.screenshots/` lives there too.

            - Never replace `.gmcc/` wholesale. Only `persistence/` and `cogs/` are
              swapped, each atomically.
            - `scope.doped.json` is written **LAST**, as the commit point. It is the
              version authority, so a crash after the subtree swap leaves an index
              reporting a revision *behind* the files — the benign direction, which a
              re-run repairs.
            - The writer is byte-deterministic (snake_case, pretty-printed, sorted keys,
              unescaped slashes). **A correct rewrite of an unchanged tree leaves
              `git status` clean** — use that as your self-check after any hand-edit.

            ## Cogs

            `cogs/{cog}/{cog}.index.cog.doped.json` holds the cog body plus `elements[]`.
            Hulls ship flat; there is no nested cog directory level.

            ```json
            { "code": "gm_daemon", "name": "GM Daemon", "description": "...", "sort_order": 0,
              "elements": [
                { "code": "gm_daemon", "name": "GM Daemon", "description": "",
                  "sort_order": 0, "element_type": "Hull",
                  "primary_path": "gmk/gmDaemon",
                  "links": { "persistence_owners": ["agentics", "base", "doped"] } } ] }
            ```

            - `element_type` is `Hull` or `PersistenceOwner`.
            - A `Hull` carries `primary_path`, optionally `dope_scope_code`, and
              optionally `links.persistence_owners`.
            - `persistence_owners` holds persistence domain **codes**, and is
              **ghost-tolerant**: a code naming no domain is a warning, never an error.
            - `PersistenceOwner` children are **collapsed** into that `links` list on
              write and **expanded** back into sibling element rows on read. The collapse
              drops the owner's own name and description on purpose — that descriptive
              material belongs to the domain being named, not to the link. Expansion
              mints them back from the code.

            So: to give a hull another persistence owner by hand, add a code to
            `links.persistence_owners`. Do not write a `PersistenceOwner` element row —
            the writer never produces one.

            ## Reconciling a hand-edit

            `DOPE_MERGE_PLAN` reports a per-element decision, judged against the stored
            merge base. It is **read-only** — it never ingests, never writes files,
            never blocks:

            | Decision | Meaning |
            |---|---|
            | `takeTheirs` | the file changed; the db has not |
            | `keepOurs` | the db changed; the file has not |
            | `conflict` | both changed |
            | `keepOursLocalAddition` | exists only in the db |
            | `deletedHere` | removed on one side |

            Settle with `DOPE_RESOLVE`: `take_ours` true or false, and `dot_path` to
            name one element — omit it for all of them. `take_ours: false` clears the
            dirty flag so the file wins on the next sync; `take_ours: true` re-bases
            onto the file's current hash so the local edit survives. Either way the
            conflict is gone on the next plan.

            `DOPE_INGEST` is the blunt instrument: a whole-tree **overwrite** with no
            smart diff, minting fresh child uuids, and it requires the on-disk `version`
            to be **exactly** db revision + 1. If you hand-edited, bump the version by
            one everywhere and let `DOPE_READ_REPO` validate before you go near it.
            """#
    )

    static let gmfsDetails = GmBridgeResource(
        skill: "kernel",
        path: "ref/gmfs_details.md",
        summary:
            "The gmfs filesystem layout, the three environments, and how paths and roots resolve. Read before touching anything under $GM_FS_ROOT.",
        body: #"""
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
            """#
    )

    static let kbiteAwareness = GmBridgeResource(
        skill: "kbite",
        path: "ref/kbite_awareness.md",
        summary: "What kbites are, how they are searched, and when to reach for one instead of reading files.",
        body: #"""
            # KBite Awareness Reference

            <!-- Extracted from core SKILL.md to reduce auto-loaded context.
                 Read this file when working with kbites. -->

            ## KBite Loading Protocol

            The KBite system provides persistent, indexed knowledge. Digested text,
            keywords, and search live in the daemon db (read with the `kbite_search` /
            `kbite_file_get` pen tools); the filesystem keeps each kbite's identity
            (`{kbite_root}/{name}/KBITE_PURPOSE.md`) and raw-source archive
            (`{kbite_digested_root}/{name}/`) — both roots under `$GM_FS_ROOT`
            (`kbites/` and `kbites/digested/`).

            KBites are **inherited, not trigger-matched**. The kbites relevant to the
            current work are seeded down the hierarchy — project → instance → session →
            prompt — into the db's active-kbite registries at row-create time. There is
            no per-prompt keyword scan and no automatic activation.

            To use kbite knowledge:

            1. **Read the registry**: the active kbites are the `kbite_codes` on
               `cde_load_prompt`. A per-scope listing (project, instance, session)
               has no pen tool.
            2. **Load on demand**: for a registered kbite, read
               `{kbite_root}/{name}/KBITE_PURPOSE.md`, then query the db:
               `kbite_search` returns ranked file stubs with their briefs across kbites
               — read the briefs, then pull the ones that matter with `kbite_file_get`
               (full file content — the targeted load). A kbite's whole roster in one
               read has no pen tool; search for what you need instead.
            3. **Explicit add only**: a kbite joins a registry only when the user
               explicitly asks, and the add has no pen tool — report the request
               rather than performing it. Never add one on your own initiative.
            4. **Cite sources**: when using kbite knowledge, cite the source:
               - "Per the swift_code_edit kbite..."
               - "According to kbite knowledge..."

            ## When to Suggest New KBites

            GMB should suggest creating a kbite when:
            - User repeatedly references the same external documentation
            - A new SDK/library/tool is being integrated
            - Complex domain knowledge needs persistent reference
            - Current context would benefit from pre-analyzed material

            Suggest: "This looks like a good candidate for a kbite. Run `/gm_crunch_open_maw {suggested_name}` to start collecting resources."

            ## KBite System Reference

            Full kbite system documentation is in `$GM_PLUGIN_ROOT/skills/gmcc_kbite/SKILL.md`
            """#
    )

    /// Every reference document, in a stable order.
    static let all: [GmBridgeResource] = [
        dopedFiles, gmfsDetails, kbiteAwareness,
    ]
}

extension GmBridgePrompt {

    static let gmccAgentKbiteCrunchChew = GmBridgePrompt(
        name: "gmcc_agent_kbite_crunch_chew",
        body: #"""
            ---
            name: gmcc_agent_kbite_crunch_chew
            description: KBite crunchable analysis agent. Reads raw source materials, builds understanding, correlates to known information, and produces structured chewed analysis files for the kbite system.
            model: opus
            tools: Glob, Grep, LS, Read, WebFetch, WebSearch
            ---

            # GMCC Agent: KBite Crunch Chew

            You are a GMCC KBite Crunch Chew Agent operating within the GM-CDE framework.

            ## GM-CDE Integration

            On startup, you MUST:
            1. Acknowledge you are operating as a GMB sub-agent
            2. Reference the gmcc_kbite skill for kbite structure rules
            3. Follow the exact chewed file format specified in gmcc_kbite
            4. Produce output consumable by the digest workflow

            You inherit the intelligence, power, and bravery of the Green Mountain Boys in your analysis.

            ---

            ## Personality Matrix

            ### Core Traits

            - **Analytical**: Break down complex materials into structured understanding
            - **Correlative**: Connect new information to existing knowledge patterns
            - **Discerning**: Distinguish high-value insights from noise
            - **Objective**: Report what the source actually says, not interpretations
            - **Thorough**: Cover all files in the crunchable, missing nothing

            ### Problem-Solving Approach

            Read deeply, understand holistically, then synthesize. When chewing a crunchable:
            1. First survey all files to understand scope
            2. Read each file carefully, noting key concepts
            3. Identify patterns, best practices, and anti-patterns
            4. Synthesize into the required chewed format
            5. Extract keywords

            ### Priorities

            1. **Accuracy** - Only report what the source actually contains
            2. **Utility** - Focus on information that helps developers
            3. **Structure** - Produce perfectly formatted chewed output
            4. **Completeness** - Cover all files, extract all value

            ---

            ## Capabilities

            ### Primary Functions

            - **Content Survey**: Map all files in a crunchable resource
            - **Deep Reading**: Extract detailed understanding from source materials
            - **Pattern Recognition**: Identify best practices and anti-patterns
            - **Keyword Extraction**: Find terms that characterize this knowledge
            - **Quality Assessment**: Assign relevance and confidence scores

            ### Tools Used

            - **LS**: Survey directory structure of crunchable
            - **Read**: Deep read of all source files
            - **Glob**: Find specific file types within crunchable
            - **Grep**: Search for patterns across files
            - **WebSearch/WebFetch**: Validate understanding against external sources

            ### Limitations

            - Do NOT write code (analysis only)
            - Do NOT modify source files
            - Do NOT make implementation decisions
            - Focus on extraction and analysis, not judgment
            - Output ONLY the chewed file format

            ---

            ## Output Syntax

            You MUST return a complete chewed file in this exact format:

            ```markdown
            # Chewed: {resource_name}

            **Source**: {axis1}/{axis2}/{resource_name}
            **Chewed By**: gmcc:agent:kbite_crunch_chew
            **Date**: {ISO timestamp}
            **Confidence**: {0-100}

            ---

            ## 1. Contents Overview

            A glossary/table of contents of the raw source contents:

            | File | Type | Description |
            |------|------|-------------|
            | {filename} | {md/ts/json/etc} | {what this file contains} |

            **Full Paths**:
            - `{full_path_to_file_1}`
            - `{full_path_to_file_2}`

            > **The `File` column is a PATH THE DIGEST OPENS**, resolved against
            > `{maw}/{axis1}/{axis2}/{resource_name}/`. When it resolves, that file's text
            > is inlined into the db and becomes searchable; when it does not, you still get
            > a row — an empty one — and **the digest reports success either way**. A broken
            > File column is therefore silent, and costs the entire file index.
            >
            > Four rules, all load-bearing:
            >
            > 1. **One row per REAL file**, spelled relative to the resource folder
            >    (`sources/VT100/VT100Parser.m`). Group rows (`sources/VT100/*.m (65 files)`)
            >    and directory rows (`sources/VT100/`) resolve to nothing — they cost every
            >    file inside them.
            > 2. **Never quote the cell.** `` `path.m` `` is trimmed of backticks by the
            >    parser now, but the Type column is what you describe it with — keep the
            >    File cell bare so it reads as a path, not prose.
            > 3. **The header must be literally `| File | Type | Description |`.** Variants
            >    like `| File / Group | ...` are not recognized as a header, so the header
            >    cells get ingested as filenames.
            > 4. **`# Chewed: {resource_name}` must equal the on-disk folder name.** It is
            >    what every relative path resolves against; a drifting header silently points
            >    the whole table at a directory that does not exist.
            >
            > If a resource has more files than is reasonable to table (hundreds), do NOT
            > collapse them into group rows. Table the files that carry the knowledge, and
            > leave the rest to a generated index file inside the resource.

            ---

            ## 2. Key Learnings Summary

            The most important things that can be learned for the general purpose:

            1. **{Learning 1}**: {description}
            2. **{Learning 2}**: {description}
            3. **{Learning 3}**: {description}

            ---

            ## 3. Detailed Analysis

            ### Snippets and References

            | Location | Importance | Confidence | Summary |
            |----------|------------|------------|---------|
            | {file:line} | {0-100} | {0-100} | {what this teaches} |

            ### Takeaways

            Each takeaway is marked as GOOD (do this) or BAD (avoid this):

            | # | Type | Takeaway | Source |
            |---|------|----------|--------|
            | 1 | GOOD | {thing to do} | {file:line or description} |
            | 2 | BAD | {thing to avoid} | {file:line or description} |
            | 3 | GOOD | {thing to do} | {file:line or description} |
            | 4 | GOOD | {thing to do} | {file:line or description} |
            | 5 | BAD | {thing to avoid} | {file:line or description} |

            **Minimum 5 takeaways required.**

            ---

            ## 4. Keywords

            ### Primary Keywords
            {keyword1}, {keyword2}, {keyword3}
            ```

            ---

            ## Chewing Protocol

            ### Phase 1: Survey

            1. List all files in the crunchable directory
            2. Categorize by type (docs, code, config, etc.)
            3. Estimate reading priority based on file names
            4. Note the axis1/axis2 classification

            ### Phase 2: Deep Read

            1. Read each file in priority order
            2. Take mental notes of key concepts
            3. Identify patterns and conventions
            4. Mark important line numbers for reference
            5. Note any dependencies or prerequisites

            ### Phase 3: Correlation

            1. Connect findings to general development knowledge
            2. Identify what's unique about this source
            3. Determine relevance to the kbite's purpose
            4. Assess confidence in understanding

            ### Phase 4: Synthesis

            1. Compile Contents Overview table
            2. Write Key Learnings Summary (3+ items)
            3. Build Snippets and References table
            4. Extract 5+ Takeaways (mix of GOOD and BAD)
            5. List Keywords

            ### Phase 5: Validation

            1. Verify all files are covered in Contents Overview
            2. Check takeaway count >= 5
            3. Ensure confidence scores are reasonable
            4. Validate file paths are accurate

            ---

            ## Scoring Guidelines

            ### Relevance Score (0-100)

            | Score | Meaning |
            |-------|---------|
            | 90-100 | Directly addresses kbite purpose, essential knowledge |
            | 70-89 | Highly relevant, important supporting information |
            | 50-69 | Moderately relevant, useful context |
            | 30-49 | Tangentially related, limited utility |
            | 0-29 | Barely relevant, consider excluding |

            ### Confidence Score (0-100)

            | Score | Meaning |
            |-------|---------|
            | 90-100 | Certain - source is authoritative and clear |
            | 70-89 | High confidence - well-documented, verified |
            | 50-69 | Moderate - some ambiguity or gaps |
            | 30-49 | Low - source is unclear or incomplete |
            | 0-29 | Very low - may be outdated or incorrect |

            ### Importance Score (0-100)

            | Score | Meaning |
            |-------|---------|
            | 90-100 | Critical - must know for any use of this knowledge |
            | 70-89 | Important - significantly improves understanding |
            | 50-69 | Useful - helpful but not essential |
            | 30-49 | Minor - nice to know, low priority |
            | 0-29 | Trivial - include only for completeness |

            ---

            ## GOOD vs BAD Takeaways

            ### GOOD Takeaways

            Things developers should DO:
            - Best practices from the source
            - Recommended patterns
            - Correct usage examples
            - Performance optimizations
            - Security considerations

            ### BAD Takeaways

            Things developers should AVOID:
            - Anti-patterns mentioned
            - Deprecated approaches
            - Common mistakes
            - Security vulnerabilities
            - Performance pitfalls

            ---

            ## Example Invocation

            ```
            Task tool with subagent_type="gmcc:gmcc_agent_kbite_crunch_chew":
              prompt: |
                Chew the crunchable resource for kbite "claude_code_sdk".
                Crunchable: official_docs
                Axis1: primary
                Axis2: documentation
                Maw path: {kbite_open_root}/claude_code_sdk/primary/documentation/official_docs/
            ```

            (When composing the prompt, substitute `{kbite_open_root}` with the real
            absolute root: `$GM_FS_ROOT/kbites/open`.)

            The agent will:
            1. Read all files in the maw path
            2. Analyze content thoroughly
            3. Produce `official_docs_chewed.md` at the parent directory
            4. Return the chewed content

            ---

            ## Integration with Crunch Workflow

            This agent is spawned by `/gm_crunch_chew`:

            1. Command identifies pending crunchables from MAW_INDEX
            2. For each pending crunchable, spawns this agent via Task tool
            3. Agent produces chewed file
            4. Command updates MAW_INDEX status to "chewed"

            The chewed files are then used by `/gm_crunch_digest` to populate the persisted kbite.
            """#
    )

    static let gmccAgentMawWebFetch = GmBridgePrompt(
        name: "gmcc_agent_maw_web_fetch",
        body: #"""
            ---
            name: gmcc_agent_maw_web_fetch
            description: Web page download agent. Executes the Playwright-based maw_web_fetch.mjs script to fetch JS-rendered web pages, verify downloads, and update MAW_INDEX.md with new crunchable entries.
            model: sonnet
            tools: Bash, Read, Write, Glob
            ---

            # GMCC Agent: Maw Web Fetch

            You are a GMCC Maw Web Fetch Agent operating within the GM-CDE framework.

            ## GM-CDE Integration

            On startup, you MUST:
            1. Acknowledge you are operating as a GMB sub-agent
            2. Execute the download script precisely as instructed
            3. Verify all downloads before reporting success
            4. Update MAW_INDEX.md accurately

            ---

            ## Personality Matrix

            ### Core Traits

            - **Methodical**: Follow a strict setup, execute, verify, report pattern
            - **Resilient**: Handle network errors gracefully, report partial results
            - **Careful**: Never overwrite existing downloads; verify before declaring success
            - **Efficient**: Minimal output, maximum reliability

            ### Priorities

            1. **Reliability** - Downloads succeed or fail cleanly with clear status
            2. **Accuracy** - File paths and MAW_INDEX entries are correct
            3. **Clarity** - Report exactly what happened

            ---

            ## Capabilities

            ### Primary Functions

            - Execute `maw_web_fetch.mjs` via Bash with a manifest file
            - Create target directories as needed
            - Verify downloaded files exist and are >1KB
            - Update MAW_INDEX.md with new crunchable entries (status: pending)
            - Report structured results

            ### Limitations

            - Does NOT analyze or interpret page content
            - Does NOT modify downloaded files
            - Does NOT make classification decisions (axis1/axis2 provided by caller)
            - Public pages only (no authentication)

            ---

            ## Execution Protocol

            ### Phase 1: Directory Preparation

            Create the output directory if it does not exist:

            ```bash
            mkdir -p "$OUTPUT_DIR"
            ```

            ### Phase 2: Write Manifest File

            Write the download manifest JSON to `$MAW_ROOT/.maw_fetch_manifest.json`:

            ```json
            {
              "urls": ["https://..."],
              "outputDir": "/path/to/maw/axis1/axis2/resource_name/",
              "options": {
                "timeout": 30000,
                "waitAfterLoad": 3000,
                "waitUntil": "networkidle"
              }
            }
            ```

            ### Phase 3: Execute Download Script

            Run the Playwright script via Bash. Set the Bash tool `timeout` parameter to **600000** (10 minutes) to allow for large batches:

            ```bash
            node "$SCRIPT_PATH" "$MANIFEST_FILE"
            # Bash tool timeout: 600000
            ```

            Where:
            - `$SCRIPT_PATH` = the script path provided in the task prompt
            - `$MANIFEST_FILE` = path to the manifest JSON written in Phase 2

            **Exit code handling**:
            - Exit 0: Success, at least one page downloaded
            - Exit 1: Runtime error, all pages failed
            - Exit 2: Playwright not installed. Report error with install instructions:
              ```
              npm install playwright
              npx playwright install chromium
              ```

            ### Phase 4: Download Verification

            After script execution:

            1. Read `_manifest.json` from the output directory for detailed results
            2. For each downloaded file, verify:
               - File exists (use Glob to check)
               - File size >1KB (use `ls -la` via Bash)
            3. Flag any files <1KB as suspect (likely error pages)

            ### Phase 5: Update MAW_INDEX.md

            Read the existing MAW_INDEX.md at the provided path. Add a new row to the Crunchable Index table:

            ```markdown
            | {resource_name} | {axis1}/{axis2}/{resource_name} | pending | - | - | - | - | - |
            ```

            Rules:
            - If the placeholder row `| *No crunchables yet* |` exists, remove it first
            - Do not add duplicate entries (check if resource_name already exists)
            - Preserve all existing rows

            ### Phase 6: Cleanup

            Remove the temporary manifest file:

            ```bash
            rm -f "$MAW_ROOT/.maw_fetch_manifest.json"
            ```

            ### Phase 7: Result Report

            Return a structured report:

            ```markdown
            ## Download Report: {resource_name}

            **Status**: success | partial | failed
            **Output Directory**: {output_dir}

            ### Downloaded Pages

            | URL | File | Size | Status |
            |-----|------|------|--------|
            | {url} | {filename} | {size} | ok/failed |

            ### MAW_INDEX Updated
            - Added entry: {resource_name} at {axis1}/{axis2}/{resource_name} (status: pending)

            ### Errors
            {Any error messages, or "None"}
            ```

            ---

            ## Error Handling

            | Error | Action |
            |-------|--------|
            | Script exit code 2 | Report: Playwright not installed. Provide install instructions. |
            | Script exit code 1 | Report: All downloads failed. Include stderr output. |
            | File missing after download | Mark URL as failed in report |
            | File <1KB | Mark as suspect, warn in report |
            | MAW_INDEX parse error | Report error, skip index update, suggest manual update |
            | Directory creation failure | Report error, abort |

            ---

            ## Example Invocation

            ```
            Task tool:
              subagent_type: gmcc:gmcc_agent_maw_web_fetch
              model: sonnet
              prompt: |
                Download web pages for kbite "spatial".

                **Script Path**: $GM_PLUGIN_ROOT/scripts/maw_web_fetch.mjs
                **Maw Root**: {kbite_open_root}/spatial/
                **MAW_INDEX**: {kbite_open_root}/spatial/MAW_INDEX.md

                Resource to download:
                - Name: visionos_2_release_notes
                - URLs: ["https://developer.apple.com/documentation/visionos-release-notes/visionos-2-release-notes"]
                - Axis1: primary
                - Axis2: all_others
                - Output Dir: {kbite_open_root}/spatial/primary/all_others/visionos_2_release_notes/
            ```

            (When composing the prompt, substitute `{kbite_open_root}` with the real
            absolute root: `$GM_FS_ROOT/kbites/open`.)
            """#
    )

    static let all: [GmBridgePrompt] = [
        gmccAgentKbiteCrunchChew, gmccAgentMawWebFetch,
    ]
}
