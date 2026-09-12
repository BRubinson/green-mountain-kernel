---
name: gmcc_cleanup
description: GM-CDE ckfs/db auditor. Checks daemon/db health, db-vs-disk drift (memory/ artifacts vs prompt_artifact rows), leftover pre-daemon yaml runtime files, archive hygiene, and kbite provenance. Interactively resolves each finding. Host wiring (binary reachability, stray ~/.zshrc blocks, settings.json grants) is /gmcc_cleanup_system's job.
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
---

# GMCC Cleanup Skill

Audits the GMCC environment — the daemon db (`~/gmcc/gmcc.db`, read over the
socket), the artifact tree (`$GMCC_CKFS_ROOT`), and the persistent host
config — and interactively resolves each finding.

Runtime data and all four bot reports live in the db; the ckfs holds only
prompt-scoped files and kbite content. This skill's job is keeping the two
in sync and the host wiring healthy.

---

## When to Use

- Periodically, to keep db + disk in sync
- After manual ckfs edits (renamed dirs, deleted files)
- When daemon calls error unexpectedly or artifact pointers dangle
- After a plugin upgrade (stale `GMCC_PLUGIN_ROOT`, stale daemon binaries)

---

## Audit Categories

| Category | Detection | Default suggestion |
|----------|-----------|--------------------|
| Daemon unhealthy | `gmcc_hook ping` / `gmcc_hook status` fails | Run `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then `gmcc_hook context ensure` |
| Pre-daemon yaml runtime files | Any `session_data.gmcc.yaml`, `project_index.gmcc.yaml`, `project_data.gmcc.yaml`, `instance_data.gmcc.yaml`, `gmcc_session_file_index.yaml`, or prompt yaml triad (`*_data.gmcc.yaml` / `*_initial.yaml` / `*_clarified.yaml`) under `$GMCC_CKFS_ROOT/projects` (outside `_archive/`) | Archive to `_archive/cold_storage/` (default) — nothing reads these; the db is the runtime. Or skip |
| Orphan memory artifact | `prompts/{seq}_{name}/memory/*.md` on disk with no matching `prompt_artifact` row (`ARTIFACT_LIST {"prompt_uuid":"U"}`) | Register via `ARTIFACT_ADD` with a caption `note` (default), or skip |
| Dangling artifact pointer | `prompt_artifact` row whose `file_path` no longer exists on disk | Flag for user — restore the file from `_archive/` if it was moved, or accept the dangling pointer (rows are history; there is no delete verb for them) |
| Orphan prompt folder | `prompts/{seq}_{name}/` on disk with no matching prompt row (`PROMPT_LIST`) | If it has a yaml triad → archive (above). If memory/-only → flag for user (may belong to another instance/branch) |
| Missing artifact home | Prompt row exists but `prompts/{seq}_{name}/memory/` doesn't | `mkdir -p` it (default) |
| Archive hygiene | Files under `$GMCC_CKFS_ROOT/_archive/` outside `cold_storage/` | Move into `_archive/cold_storage/` preserving relative structure (default), or skip — cold_storage is the single universal bucket |
| Unexpected cruft | Top-level `$GMCC_CKFS_ROOT` entries other than `README.md`, `projects/`, `kbites/`, `_archive/`; non-`prompts/` clutter in session dirs | Archive to `_archive/cold_storage/` (default) or keep |
| Stale chewed provenance path | Inside `kbites/digested/{name}/.../*_chewed.md`, a `**Source**:` or `**Location**:` line points at an absolute path that no longer exists | Rewrite the line to strip the dead absolute prefix and prepend `(retired maw source) `, preserving the relative slug (default), or leave unchanged |
| Host config drift | Delegated — `/gmcc_cleanup_system` (binary reachability, stray `~/.zshrc` gmcc block, settings.json grants, env-vs-db root agreement) | Point the user at `/gmcc_cleanup_system` |
| Undigested kbite content | `{kbite_digested_root}/{name}/` (kbite_digested_root from `gmcc_hook paths --json`) contains `*_chewed.md` files but `KBITE_GET {"code":"{name}"}` shows no resources | Backfill (default): copy the chewed files (+ `KBITE_INDEX.md` / `KBITE_RELATIONSHIPS.md` if present) to `_archive/cold_storage/kbites/digested/{name}/`, then `gmcc_hook call KBITE_DIGEST --json '{"code":"{name}","kbite_open_path":"{kbite_digested_root}/{name}"}'`, verify counts via `KBITE_GET`, delete the stale `KBITE_INDEX.md` — Or skip |
| KBite drift: db row without content | A `KBITE_LIST {"all":true}` row whose code has neither `{kbite_root}/{name}/` nor `{kbite_digested_root}/{name}/` on disk | Report only — digested text legitimately lives db-only; a missing KBITE_PURPOSE.md/raw archive may still be intentional. Flag for user, never auto-delete db rows |
| KBite drift: content without registry reach | A kbite content dir whose code has db resources but appears in no registry (`KBITE_LIST` at scope project, instance and session all miss it) | Report only — informational; kbites are registered on explicit request (`KBITE_ADD`) |

---

## Walk Strategy

The walk is bounded — never recurses into git repos, kbite resource trees, or `_archive/` (except the archive-hygiene surface check). Order:

1. **Daemon health**: `gmcc_hook ping`, `gmcc_hook status`, then
   `gmcc_hook context ensure` to resolve this repo/branch to its uuids.
2. **Top-level of `$GMCC_CKFS_ROOT`** — anything other than `README.md`, `projects/`, `kbites/`, `_archive/` is a finding.
3. **`projects/` tree** — walk `projects/{p}/instances/{i}/sessions/{s}/`:
   - any pre-daemon runtime yaml (see table) → ONE aggregate archive finding (listing all hits), not one per file;
   - session dirs should contain only `prompts/`.
4. **Per-session db cross-check** (for sessions resolvable to db rows): `PROMPT_LIST {"session_uuid":"U"}` vs on-disk `prompts/{seq}_{name}/` folders; `ARTIFACT_LIST {"prompt_uuid":"U"}` vs `memory/*.md` files, in both directions.
5. **`_archive/`** — surface-level only: entries outside `cold_storage/`.
6. **Kbite provenance** — stale `**Source**:` lines in `*_chewed.md` under `kbites/digested/`.
7. **Host config** — NOT this skill's surface: mention `/gmcc_cleanup_system` in the report when anything hinted at host drift.

---

## Interaction Pattern

For each finding, use AskUserQuestion with up to 4 options. The first option is always the recommended default. Standard option set:

| Option | What it does |
|--------|--------------|
| **Archive** (default for cruft) | `mv` the path into `~/gmcc_ckfs/_archive/cold_storage/{relative_path}` (structure-preserving). |
| **Register/repair** (default for db-vs-disk drift) | The matching write call (`ARTIFACT_ADD`, `gmcc_hook context ensure`) or `mkdir -p`. |
| **Skip** | Leave the finding in place. Always available. |

Bulk actions (e.g. "archive all cruft") are offered after the first 3 similar findings, with an extra confirmation.

---

## Output Format

After the walk, before any prompts:

```
[GMB] GMCC Environment Audit

Daemon: {reachable pid N, schema vX | UNREACHABLE}
Scanned: $GMCC_CKFS_ROOT
Total findings: {n}
- Daemon/db health: {n}
- Pre-daemon yaml runtime files: {n}
- Orphan memory artifacts (unregistered): {n}
- Dangling artifact pointers: {n}
- Archive hygiene: {n}
- Cruft: {n}
- Stale chewed provenance: {n}
(host config drift is /gmcc_cleanup_system's audit — suggest it when relevant)

Beginning interactive resolution. You can abort at any time — completed actions are NOT rolled back.
```

After resolution, print a resolved/skipped tally. The audit trail lives in
the daemon event log (`gmcc_hook call EVENT_LIST --json '{"limit":50}'`) for
db writes; filesystem actions are reported in chat only.

---

## Safety Guardrails

- **Never auto-fix** — every action requires user confirmation via AskUserQuestion.
- **Never delete** — the destructive option is Archive (reversible, structure-preserving under `_archive/cold_storage/`). `rm` is never offered.
- **Never write the db directly** — every db repair goes over the socket, through a pen tool or `gmcc_hook call`.
- **Never touch the live current-session paths**: if the walk encounters the current session's artifact home (`$GMCC_CKFS_ROOT/{ckfs_relative_storage_path}` from `SESSION_GET`) or its parents, those are excluded from findings even if they look unusual (they belong to the running session).
- **Bulk actions** require an extra confirmation prompt.
