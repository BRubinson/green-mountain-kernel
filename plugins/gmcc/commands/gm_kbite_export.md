---
name: gm_kbite_export
description: "Export one digested kbite to a portable gmcc_kbite zip"
argument-hint: "<kbite_code> [output_dir]"
disable-model-invocation: false
allowed-tools: Read, Bash, Glob
---

# /gm_kbite_export {kbite_code} [output_dir]

Exports one kbite from this machine's daemon db + digested archive into a
single portable zip: `gmcc_kbite_{code}_{YYYYMMDD}.zip`. The daemon
serializes the db rows into a `db_export.json` with every machine root
scrubbed to a placeholder; you stage the root docs and the `.git`-stripped
digested sources beside it and zip the staging dir. Move the zip between
machines however you like (mail, drive, airdrop); the other side runs
`/gm_kbite_import`.

One kbite per zip. Kbite relationships are NOT resolved on the other side —
`KBITE_RELATIONSHIPS.md` travels as an inert document.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Resolve the roots: `gmcc_hook paths --json` (ckfs_root, kbite_root,
   kbite_digested_root).
2. Verify the kbite exists in the db:
   `gmcc_hook call KBITE_GET --json '{"code":"{kbite_code}"}'`

### If KBite Unknown
```
[GMB] Error: kbite {kbite_code} not found in the db

Every digested kbite on this machine:
  gmcc_hook call KBITE_LIST --json '{"scope":"session","owner_uuid":"{U}","all":true}'
```
Exit without changes.

---

## Export

### Step 1: Serialize the db rows

Stage a directory, then ask the daemon to write `db_export.json` into it.
The `anonymize` rules turn this machine's absolute roots into placeholders
so the zip is portable (the daemon applies longest-prefix-first, so
overlapping roots cannot half-replace each other):

```bash
STAGE=$(mktemp -d)/gmcc_kbite_{kbite_code}
mkdir -p "$STAGE"

gmcc_hook call KBITE_EXPORT --json '{
  "code": "{kbite_code}",
  "db_export_path": "'"$STAGE"'/db_export.json",
  "anonymize": [
    {"prefix": "{kbite_digested_root}", "placeholder": "{{KBITE_TREE}}"},
    {"prefix": "{kbite_root}",          "placeholder": "{{KBITE_IDENTITY}}"},
    {"prefix": "{ckfs_root}",           "placeholder": "{{GMCC_CKFS}}"},
    {"prefix": "'"$HOME"'",             "placeholder": "{{GMCC_HOME}}"}
  ]
}'
```

The response reports `resource_count`, `file_count`, `kbite_keyword_count`,
`file_keyword_count` and the `db_export_path` it wrote.

### Step 2: Stage the files

```bash
# identity docs (KBITE_PURPOSE.md, KBITE_RELATIONSHIPS.md if present)
mkdir -p "$STAGE/root_docs"
cp {kbite_root}/{kbite_code}/*.md "$STAGE/root_docs/" 2>/dev/null || true

# digested raw sources, .git stripped (absent is fine — db content still exports)
if [ -d "{kbite_digested_root}/{kbite_code}" ]; then
  mkdir -p "$STAGE/digested"
  rsync -a --exclude '.git' "{kbite_digested_root}/{kbite_code}/" "$STAGE/digested/"
fi
```

### Step 3: Zip

```bash
OUT={output_dir:-$PWD}
ditto -c -k --sequesterRsrc --keepParent "$STAGE" \
  "$OUT/gmcc_kbite_{kbite_code}_$(date -u +%Y%m%d).zip"
```

Large kbites take a while — check the staged size first and tell the user
before zipping, then let it run.

## Report

```
[GMB] KBite exported: {kbite_code}

Zip: {zip path}
Contents: {resource_count} resources, {file_count} files,
          {kbite_keyword_count + file_keyword_count} keyword attachments
Root docs: {included|none} — Digested sources: {included|none}

Import on the other machine with /gm_kbite_import {zip file}.
```
