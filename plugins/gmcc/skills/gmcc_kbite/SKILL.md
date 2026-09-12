---
name: gmcc_kbite
description: GM-CDE Knowledge Bite System - Defines persistent knowledge (kbites) stored canonically in the daemon db, with pre-analyzed reference material queried through the pen's kbite_search / kbite_file_get and the KBITE_* wire verbs. Includes the crunchable maw workflow for ingesting new knowledge sources.
user-invocable: false
disable-model-invocation: true
# [FIX #3] Added disable-model-invocation to prevent auto-loading on every prompt.
# This skill is only needed during /gm_crunch_* operations, not general conversation.
# Saves ~2,800 tokens of context per message when not doing kbite work.
---

# GMCC KBite System

The KBite (Knowledge Bite) system provides persistent, indexed knowledge storage for GM-CDE. KBites are pre-analyzed reference materials that GMCC agents can efficiently query during development tasks.

---

## What is a KBite?

A **KBite** is a persisted body of analyzed knowledge that is:
- **Pre-tokenized**: Content has been analyzed and summarized for efficient consumption
- **Indexed**: Full-text searchable (FTS5, bm25-ranked) with snake_case keywords
- **Persistent**: Digested text lives in the daemon db (`~/gmcc/gmcc.db`), shared across all repositories
- **Referenced**: GMCC agents and contexts query it with the pen tools `kbite_search` and `kbite_file_get`, and with `gmcc_hook call KBITE_GET` for the per-kbite index

KBites transform raw reference materials (documentation, examples, APIs) into structured knowledge that GMB can leverage during development.

---

## Where KBite Data Lives

Digested knowledge is **db-canonical**: `KBITE_DIGEST` parses each chewed
analysis into resource / file / keyword rows (full text inlined for text-type
files) and then deletes the chewed `.md` files. The filesystem keeps only
identity, raw sources, and in-progress maws:

| Home | What lives there |
|------|------------------|
| Daemon db (`~/gmcc/gmcc.db`) | Resources, per-file summaries + full text, keywords, FTS5 search, kbite registries. Read with `kbite_search` / `kbite_file_get` / `KBITE_GET`. |
| `{kbite_root}/{name}/` (kbite root) | `KBITE_PURPOSE.md` (identity — defined once, above the lifecycle split) and `KBITE_RELATIONSHIPS.md` when relationships exist. |
| `{kbite_digested_root}/{name}/` | **Raw-source archive**: the `{axis1}/{axis2}/{resource}/` folders moved out of the maw at digest time. No indexes — `KBITE_GET` is the index. |
| `{kbite_open_root}/{name}/` | **In-progress maw**: raw sources being collected/chewed, plus `MAW_INDEX.md`. Deleted at digest time. |

### Path roots

The kbite roots are daemon config, read from `gmcc_hook paths --json` (they are
NOT env vars):

| paths key | Default value | Per-kbite usage |
|----------------|---------------|-----------------|
| `kbite_root` | `$GMCC_CKFS_ROOT/kbites` | `{kbite_root}/{name}/KBITE_PURPOSE.md` |
| `kbite_digested_root` | `$GMCC_CKFS_ROOT/kbites/digested` | `{kbite_digested_root}/{name}/...` (raw archive) |
| `kbite_open_root` | `$GMCC_CKFS_ROOT/kbites/open` | `{kbite_open_root}/{name}/...` (open maw) |

Every kbite row in the db:

```bash
gmcc_hook call KBITE_LIST --json '{"scope":"session","owner_uuid":"<SESSION_UUID>","all":true}'
```

> Some kbites on disk predate the db-canonical layout: they carry
> `KBITE_INDEX.md` and `*_chewed.md` files under `{kbite_digested_root}/{name}/`
> and have no db rows. The cleanup skill detects these and backfills them
> (archive the chewed files to cold storage, then `KBITE_DIGEST`).

---

## Two-Axis Classification System

Raw resources are classified along two axes (the folder layout inside maws
and the raw-source archive, and the `axis1`/`axis2` columns in the db):

### Axis 1: Source Authority

| Type | Description | Weight Modifier |
|------|-------------|-----------------|
| **primary** | Official authority on the content (official docs, first-party examples) | +20 relevance |
| **secondary** | Knowledgeable but non-official (community tutorials, third-party analysis) | +0 relevance |

### Axis 2: Content Type

| Type | Description | Example |
|------|-------------|---------|
| **documentation** | Official functionality and capability docs | SDK reference guides |
| **example_project** | Complete implementations or code samples | GitHub example repos |
| **api_reference** | Raw API/function/library references | TypeScript definitions |
| **blogs** | Less structured commentary and tutorials | Dev.to articles |
| **all_others** | Anything else | Forum posts, videos |

### Classification Path

Resources are stored at: `{axis1}/{axis2}/{resource_name}/`

Example: `primary/documentation/claude_code_hooks/`

---

## Open Maw Structure (Temporary Processing)

The **open maw** is a temporary holding area for resources being processed
("crunched") into the db. It lives under `{kbite_open_root}/{kbite_name}/` —
there is at most one open maw per kbite, system-wide. The skeleton is created
by `gmcc_hook call KBITE_MAW_OPEN --json '{"kbite_name":"{name}","maw_path":"{kbite_open_root}/{name}"}'`
(idempotent, no db rows):

```
{kbite_open_root}/{kbite_name}/
├── MAW_INDEX.md                        # Index of crunchables in this maw
│
├── primary/
│   ├── documentation/
│   │   ├── {crunchable_name}/
│   │   │   └── {raw_source_files...}
│   │   └── {crunchable_name}_chewed.md     # Chewed file alongside source folder
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
│
└── secondary/
    ├── documentation/
    ├── example_project/
    ├── api_reference/
    ├── blogs/
    └── all_others/
```

### MAW_INDEX.md

Tracks crunchables during processing:

```markdown
# Maw Index: {kbite_name}

**Target KBite**: {kbite_name}
**Opened**: {ISO timestamp}
**Status**: {open | chewing | ready_to_digest}

## Crunchable Index

| Resource | Path | Status | Keywords | Relevance | Uniqueness | Unique Keywords | Expansion Weight |
|----------|------|--------|----------|-----------|------------|-----------------|------------------|
| {name} | {axis1/axis2/name} | {pending | chewing | chewed} | {kw1, kw2} | {0-100} | {0-100} | {kw1, kw2, kw3} | {0-100} |

### Status Values
- **pending**: Resource added, not yet analyzed
- **chewing**: Agent currently processing
- **chewed**: Analysis complete, ready for digest

### Weight Columns
- **Relevance**: 0-100 score of relevance to KBITE_PURPOSE
- **Uniqueness**: 0-100 score of how unique this resource is vs existing
- **Unique Keywords**: Top 3 keywords this resource adds that others don't have
- **Expansion Weight**: 0-100 score of new info this adds to existing keywords
```

---

## Chewed File Format

When a crunchable is "chewed" by `gmcc:agent:kbite_crunch_chew()`, it produces a `{resource_name}_chewed.md` file. This format is the **digest parser's input contract** — `KBITE_DIGEST` scans these sections into db rows, then deletes the file:

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
- `{kbite_open_root}/{kbite}/{axis1}/{axis2}/{resource}/{file}`

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

**Minimum 5 takeaways required per chewed file.**

---

## 4. Keywords

### Primary Keywords
{keyword1}, {keyword2}, {keyword3}
```

---

## KBITE_PURPOSE.md

Defines the purpose and scope of a kbite. Lives at `{kbite_root}/{kbite_name}/KBITE_PURPOSE.md` (above the digested/open lifecycle split — purpose is identity-level, not lifecycle-level). Created interactively at open-maw time; it stays a filesystem file, not a db row:

```markdown
# KBite Purpose: {kbite_name}

## Why This KBite Exists
{Clear statement of what knowledge this kbite captures}

## Scope
- **In Scope**: {what this kbite covers}
- **Out of Scope**: {what this kbite does NOT cover}

## Target Use Cases
1. {use case 1}
2. {use case 2}

## Related KBites
| KBite | Relationship |
|-------|--------------|
| {name} | {how they relate} |

## Success Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}
```

---

## KBITE_RELATIONSHIPS.md

Tracks relationships between kbites. Managed by `/gm_kbite_relate`; lives at the kbite root:

```markdown
# KBite Relationships: {kbite_name}

## Outgoing Relationships

| Target KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {target} | {depends_on | extends | complements | supersedes} | {description} |

## Incoming Relationships

| Source KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {source} | {depends_on | extends | complements | supersedes} | {description} |
```

### Relationship Types

| Type | Meaning |
|------|---------|
| **depends_on** | This kbite requires knowledge from target |
| **extends** | This kbite builds upon target with more detail |
| **complements** | Related but distinct knowledge areas |
| **supersedes** | This kbite replaces outdated target |

---

## Crunchable Workflow

### 1. Open Maw (`/gm_crunch_open_maw {kbite_name}`)

Creates the maw skeleton at `{kbite_open_root}/{kbite_name}/` via
`KBITE_MAW_OPEN` (two-axis tree + MAW_INDEX.md, no db rows) and, for a new
kbite, interactively creates `KBITE_PURPOSE.md` at the kbite root.

### 2. Add Crunchables (Manual or `/gm_maw_fetch`)

User places raw source files in appropriate `{axis1}/{axis2}/{resource_name}/` directories.

### 3. Chew (`/gm_crunch_chew {kbite_name}`)

Processes each crunchable:
1. Indexes untracked crunchables in MAW_INDEX
2. Spawns `gmcc:agent:kbite_crunch_chew()` for each pending crunchable
3. Generates `{resource_name}_chewed.md` files
4. Updates MAW_INDEX with status

### 4. Digest (`/gm_crunch_digest {kbite_name}`)

Imports the maw's knowledge into the db and archives raw sources:
1. ```bash
   gmcc_hook call KBITE_DIGEST --json '{"code":"{name}","kbite_open_path":"{kbite_open_root}/{name}"}'
   ```
   The daemon parses every `*_chewed.md` under that path into resource / file /
   keyword rows (full text inlined), commits, then deletes the chewed files.
   Re-digesting a resource replaces its rows.
2. Client-side: raw source folders are moved from
   `{kbite_open_root}/{kbite_name}/` to `{kbite_digested_root}/{kbite_name}/`
   (same `{axis1}/{axis2}/` layout) and the open maw is deleted.
3. Verify with `gmcc_hook call KBITE_GET --json '{"code":"{name}"}'`.

---

## GMB Behavioral Rules for KBites

### KBite Awareness (CRITICAL)

KBites are **inherited, not trigger-matched**. The kbites relevant to the
current work are seeded down the hierarchy — project → instance → session →
prompt — into the db's active-kbite registries at row-create time. When
operating in GM-CDE mode, GMB MUST:

1. **Read the Registry**: the active kbites are the `kbite_codes` on the
   prompt (pen tool `prompt_get`) or on the session (`gmcc_hook call
   SESSION_GET --json '{"session_uuid":"<U>"}'`). Registry listing is
   `KBITE_LIST` — scoped (`{"scope":"session","owner_uuid":"<U>"}`, resolved
   through the inheritance chain at read time) or whole-db (`"all":true`).
   There is no per-prompt keyword scan.
2. **Load Registered KBites from the db**: read the purpose at the kbite
   root (`{kbite_root}/{name}/KBITE_PURPOSE.md`), then `KBITE_GET` for the
   index (resources + file stubs + keywords), the pen tool `kbite_search`
   for bm25-ranked stubs, and `kbite_file_get` for one file's full content.
3. **Reference in Responses**: when using kbite knowledge, cite the source
   (e.g., "Per the swift_code_edit kbite...").
4. **Explicit Add Only**: add a kbite to a registry only when the user
   explicitly asks for it (`KBITE_ADD`). Never add one on your own
   initiative.

### KBite Load Protocol

```
1. Read the active kbite codes (prompt_get, or SESSION_GET for the session)
2. For each registered kbite:
   a. Read {kbite_root}/{name}/KBITE_PURPOSE.md (root, filesystem)
   b. KBITE_GET {"code":"{name}"}                # overview: resources, stubs, keywords
   c. kbite_search "<topic>"                     # rank what matters for the task
   d. kbite_file_get <file_uuid>                 # pull full content, top files only
3. Proceed with task using loaded knowledge
```

### When to Create New KBites

GMB should suggest creating a kbite when:
- User repeatedly references the same external documentation
- A new SDK/library/tool is being integrated
- Complex domain knowledge needs persistent reference
- Current context would benefit from pre-analyzed material

---

## Command Reference

| Command | Purpose |
|---------|---------|
| `/gm_crunch_open_maw {kbite_name}` | Create maw skeleton (KBITE_MAW_OPEN) + KBITE_PURPOSE for new kbites |
| `/gm_maw_fetch {kbite_name}` | Download web pages into the open maw |
| `/gm_crunch_chew {kbite_name}` | Process crunchables and generate chewed analysis |
| `/gm_crunch_digest {kbite_name}` | Import chewed knowledge into the db, archive raw sources, delete the maw |
| `/gm_kbite_relate {from} {to} {description}` | Define relationship between kbites |
| `/gm_kbite_export {kbite_code} [output_dir]` | Export one kbite to a portable gmcc_kbite zip |
| `/gm_kbite_import {zip_path} [overwrite]` | Import a gmcc_kbite zip (db + sources; never registers) |

Direct queries — the pen tools `kbite_search` (query, optional limit) and
`kbite_file_get` (file_uuid), plus the wire verbs:

```bash
gmcc_hook call KBITE_GET  --json '{"code":"<CODE>"}'
gmcc_hook call KBITE_LIST --json '{"scope":"session","owner_uuid":"<U>","all":true}'
gmcc_hook call KBITE_ADD  --json '{"scope":"session","owner_uuid":"<U>","code":"<CODE>"}'
gmcc_hook call KBITE_KEYWORD_TAG --json '{"level":"kbite","target_uuid":"<U>","keywords":["k1","k2"],"detach":false}'
```

Scopes are `project | instance | session | prompt`; keyword-tag levels are
`kbite | file`. Lifecycle (`KBITE_EXPORT` / `KBITE_IMPORT` / `KBITE_DELETE`) is
below. `gmcc_hook verbs --json` lists every MessageType the daemon serves; the
doors themselves are described in
`$GMCC_PLUGIN_ROOT/skills/gmcc_daemon/SKILL.md`.

---

## Export / Import Archive Format

One kbite per zip, single format (no payload-scope variants):

```
gmcc_kbite_{code}_{YYYYMMDD}.zip
  MANIFEST.yaml      format_version, code, exported_at, wire_version,
                     counts, has_root / has_digested
  db_export.json     the db rows: kbite code, resources (name/summary/
                     type/trust), files (name/summary/nullable content),
                     ALL keywords by text (kbite- and file-level)
  root/              KBITE_PURPOSE.md, KBITE_RELATIONSHIPS.md (inert —
                     relationships are never resolved on import)
  digested/          the raw-source archive, .git stripped
```

Rules the format guarantees:

1. **No machine paths travel.** Export replaces `{kbite_open_root}/{code}`,
   `{kbite_digested_root}/{code}`, and `$HOME` with placeholders
   (`{{KBITE_TREE}}`, `{{GMCC_HOME}}`) across every text surface;
   import rehydrates them to the importing machine's roots. This is a
   correctness requirement, not cosmetics — stale absolute paths would
   silently break future re-digests.
2. **No uuids travel as identity.** The kbite's identity is its `code`;
   resource/file uuids are re-minted on import (referrers are
   ghost-tolerant by design) and keywords remap by TEXT into the importing
   machine's shared vocabulary.
3. **Collision policy**: `skip` (default, non-destructive) or `overwrite`
   (replaces content under the EXISTING kbite uuid, so scope registrations
   survive; the previous digested tree moves to `_archive/cold_storage/`).
4. **Import never registers.** Activate explicitly with `KBITE_ADD`.
5. **Delete is db-first and content-destructive**: `KBITE_DELETE` cascades
   resources, files, junctions, and registrations in one statement (FTS stays
   consistent; orphaned keywords are garbage-collected; event history
   survives). ALWAYS take a backup — `gmcc_hook call BACKUP --json '{}'`, or
   `KBITE_EXPORT`, which doubles as a restorable snapshot — before deleting:
   the digested knowledge is otherwise unrecoverable. The digested tree on
   disk is a separate, client-side step: MOVE it to `_archive/cold_storage/`
   — nothing is ever `rm`'d.

The three lifecycle calls:

```bash
gmcc_hook call KBITE_EXPORT --json '{"code":"<CODE>","db_export_path":"<DIR>/db_export.json",
  "anonymize":[{"prefix":"<ABS_PREFIX>","placeholder":"{{KBITE_TREE}}"}]}'
gmcc_hook call KBITE_IMPORT --json '{"db_export_path":"<DIR>/db_export.json","on_collision":"skip",
  "rehydrate":[{"prefix":"{{KBITE_TREE}}","placeholder":"<ABS_PREFIX>"}]}'
gmcc_hook call KBITE_DELETE --json '{"code":"<CODE>"}'
```

---

## Agent Reference

| Agent | Purpose |
|-------|---------|
| `gmcc:agent:kbite_crunch_chew()` | Analyze crunchable and produce chewed file |

---

## Integration with GMCC

The kbite system integrates with core GMCC:

1. **Paths**: Uses the daemon's configured kbite roots — `kbite_root`, `kbite_digested_root`, `kbite_open_root` from `gmcc_hook paths --json` — for path resolution (resolved client-side; the daemon receives absolute paths)
2. **System-Level Storage**: Kbites are independent of FAM/branch — one db + one kbites tree per machine
3. **Agent System**: Uses GMCC agent framework for chewing
4. **Registry System**: Active kbites live in the daemon db's `{project,instance,session,prompt}_active_kbite` registries (read with `KBITE_LIST`; explicit add via `KBITE_ADD`)

---

## Syntax Reference

### KBite Invocation

```
gmcc:agent:kbite_crunch_chew(
  kbite: "{kbite_name}",
  crunchable: "{resource_name}",
  axis1: "primary" | "secondary",
  axis2: "documentation" | "example_project" | "api_reference" | "blogs" | "all_others"
)
```

---

## Best Practices

1. **One Topic Per KBite**: Keep kbites focused on a single SDK/tool/domain
2. **Primary First**: Prioritize official documentation over secondary sources
3. **Quality Over Quantity**: Better to have 5 excellent chewed resources than 20 shallow ones
4. **Search Before Browsing**: Start knowledge lookup with `kbite_search`, then targeted `kbite_file_get` — don't bulk-load whole kbites
5. **Cross-Reference**: Use KBITE_RELATIONSHIPS to connect related knowledge
6. **Cite Sources**: Always reference kbite knowledge with attribution
