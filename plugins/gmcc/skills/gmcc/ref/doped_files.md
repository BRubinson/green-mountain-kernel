# DOPED Files — the on-disk `.gmcc` reference

## When to read this

Read this **only when you are building or editing a repo's `.doped.json`
files directly** — authoring a tree from scratch, repairing a hand-edit, or
reviewing a diff of `.gmcc/`.

A normal bot run does **not** need this file. The bot tiers reach dope
search-first through the pen (`dope_search`, then targeted `dope_get` by
`code`) and never touch the files; that protocol lives in
`ref/bot_workflows.md` and is unaffected by anything here.

## The supported path

The db is the editing surface. The files are a **publication** of it.
Granular edits are one verb per level, reached through the passthrough:

```bash
gmcc_hook call DOPE_NODE_ADD --json \
  '{"level":"persistence|entity|property|enum|option",
    "parent_uuid":"P","fields":{...}}'

gmcc_hook call DOPE_NODE_UPDATE --json \
  '{"level":"entity","node_uuid":"N","expected_version":V,"fields":{...}}'

gmcc_hook call DOPE_WRITE_REPO --json '{"scope_uuid":"U"}'      # db -> files
```

Hand-editing is the exception, not the workflow. When it happens:

```bash
# parse + validate, never writes — one of scope_uuid or dir_path
gmcc_hook call DOPE_READ_REPO  --json '{"scope_uuid":"U"}'
gmcc_hook call DOPE_MERGE_PLAN --json '{"scope_uuid":"U"}'      # db vs files, read-only
gmcc_hook call DOPE_RESOLVE    --json \
  '{"scope_uuid":"U","take_ours":true,"dot_path":"<dot.path>"}'
```

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
      "primary_path": "plugins/gmcc/daemon",
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
