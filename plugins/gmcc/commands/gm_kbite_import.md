---
name: gm_kbite_import
description: "Import a gmcc_kbite zip into this machine's daemon db"
argument-hint: "<zip_path> [overwrite]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# /gm_kbite_import {zip_path} [overwrite]

Imports a `gmcc_kbite_{code}_{date}.zip` produced by `/gm_kbite_export` on
any gmcc machine: db rows land in one transaction (keywords remapped by text
into the shared vocabulary, placeholder paths rehydrated to this machine's
roots), the digested source tree is restored under the local
`kbite_digested_root`, and root docs land under `kbite_root`.

The import NEVER registers the kbite at any scope — registration is always
an explicit KBITE_ADD.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Verify the zip exists at `{zip_path}`.
2. Resolve the roots: `gmcc_hook paths --json` (ckfs_root, kbite_root,
   kbite_digested_root).
3. `gmcc_hook call BACKUP --json '{}'` — the documented pre-flight before any
   content-mutating import.

### If Zip Missing
```
[GMB] Error: no zip at {zip_path}
```
Exit without changes.

---

## Import

### Step 1: Unpack

```bash
STAGE=$(mktemp -d)
ditto -x -k "{zip_path}" "$STAGE"
# → $STAGE/gmcc_kbite_{code}/{db_export.json, root_docs/, digested/}
```

Read `db_export.json`'s `code` and `format_version` — gate on the format
version, not on any other version number.

### Step 2: Load the db rows

`rehydrate` is the mirror of the export's `anonymize`: it maps the archive's
placeholders onto THIS machine's roots.

```bash
gmcc_hook call KBITE_IMPORT --json '{
  "db_export_path": "'"$STAGE"'/gmcc_kbite_{code}/db_export.json",
  "on_collision": "skip",
  "rehydrate": [
    {"prefix": "{kbite_digested_root}", "placeholder": "{{KBITE_TREE}}"},
    {"prefix": "{kbite_root}",          "placeholder": "{{KBITE_IDENTITY}}"},
    {"prefix": "{ckfs_root}",           "placeholder": "{{GMCC_CKFS}}"},
    {"prefix": "'"$HOME"'",             "placeholder": "{{GMCC_HOME}}"}
  ]
}'
```

The default collision policy is **skip**: if the kbite code already exists
on this machine, nothing changes and the response comes back with
`skipped_existing: true`. When that happens, ask via AskUserQuestion whether
to overwrite (overwrite replaces the kbite's CONTENT under its existing uuid
— scope registrations survive). On approval (or when the `overwrite`
argument was passed up-front), re-run the same call with
`"on_collision": "overwrite"`, and move the previous digested tree to
`{ckfs_root}/_archive/cold_storage/` first — never delete it.

### Step 3: Restore the files

```bash
mkdir -p "{kbite_root}/{code}"
cp "$STAGE"/gmcc_kbite_{code}/root_docs/*.md "{kbite_root}/{code}/" 2>/dev/null || true

if [ -d "$STAGE/gmcc_kbite_{code}/digested" ]; then
  mkdir -p "{kbite_digested_root}/{code}"
  rsync -a "$STAGE/gmcc_kbite_{code}/digested/" "{kbite_digested_root}/{code}/"
fi
```

## Report

```
[GMB] KBite imported: {code}

{resource_count} resources, {file_count} files, {keyword_count} keywords
Digested sources: {restored path | archive carried none}

The kbite is NOT registered anywhere yet. To activate it here:
  gmcc_hook call KBITE_ADD --json '{"scope":"session","owner_uuid":"{U}","code":"{code}"}'
  (scope may be session, instance, project or prompt — owner_uuid is that
  scope's row)
```

If the import was skipped:
```
[GMB] KBite {code} already exists — import skipped (non-destructive default)

Re-run with overwrite to replace its content.
```
