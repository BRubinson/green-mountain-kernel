---
name: gm_crunch_open_maw
description: "Open a maw for collecting kbite resources"
argument-hint: "<kbite_name>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob
---

# /gm_crunch_open_maw {kbite_name}

Opens a "maw" (processing directory) under the kbite for collecting crunchable resources that will be digested into the daemon db.

---

## Pre-Flight Checks

**Boot Validation**: If `$GMCC_BOOTED` is not set, output:
```
[GMB] ERROR: GMCC not booted

GMCC environment variables are not set. Run /gmcc_boot for diagnostics.
To fix: Restart Claude Code from within a git repository.
```
Exit without proceeding.

1. Resolve the kbite roots from `gmcc_hook paths --json` (kbite_root,
   kbite_open_root, kbite_digested_root)
2. Parse `{kbite_name}` argument

---

## Directory Structure Reference

Per the **gmcc_kbite** skill, the open maw structure is:

```
{kbite_open_root}/{kbite_name}/
├── MAW_INDEX.md
├── primary/
│   ├── documentation/
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
└── secondary/
    ├── documentation/
    ├── example_project/
    ├── api_reference/
    ├── blogs/
    └── all_others/
```

---

## Execution Steps

### Step 1: Check for Existing Maw

```bash
if [ -d "{kbite_open_root}/{kbite_name}" ]; then
    echo "Maw already exists for {kbite_name}"
fi
```

If maw exists, ask user:
- **Continue**: Use existing maw (report current status; the maw-open call
  below is idempotent — it only fills in missing dirs/index)
- **Reset**: Delete the maw directory first, then recreate

### Step 2: Check for Parent KBite Purpose

Check if the target kbite already has a purpose file at `{kbite_root}/{kbite_name}/KBITE_PURPOSE.md`:

```bash
if [ ! -f "{kbite_root}/{kbite_name}/KBITE_PURPOSE.md" ]; then
    # New kbite — need to create KBITE_PURPOSE
fi
```

### Step 3: Create the Maw Skeleton

One call — the daemon creates the two-axis directory tree and `MAW_INDEX.md`
(per the **gmcc_kbite** skill format) at `{kbite_open_root}/{kbite_name}/`.
No db rows are written; maws are filesystem-only until digest:

```bash
gmcc_hook call KBITE_MAW_OPEN --json '{"kbite_name":"{kbite_name}","maw_path":"{kbite_open_root}/{kbite_name}"}'
```

The response reports `created_dirs` and `created_index` — both empty/false
when the maw already existed (idempotent).

### Step 4: Create KBITE_PURPOSE.md (If New KBite)

If the target kbite doesn't yet have a purpose file at `{kbite_root}/{kbite_name}/KBITE_PURPOSE.md`, create it at the kbite root (above the digested/open lifecycle split):

```bash
mkdir -p "{kbite_root}/{kbite_name}"
```

Per the **gmcc_kbite** skill KBITE_PURPOSE format, use AskUserQuestion to gather:
- Why this kbite exists
- What's in scope / out of scope
- Target use cases

Then create `{kbite_root}/{kbite_name}/KBITE_PURPOSE.md`:

```markdown
# KBite Purpose: {kbite_name}

## Why This KBite Exists
{User-provided purpose}

## Scope
- **In Scope**: {User-provided scope}
- **Out of Scope**: {User-provided exclusions}

## Target Use Cases
1. {Use case 1}
2. {Use case 2}

## Related KBites
| KBite | Relationship |
|-------|--------------|
| *None yet* | - |

## Success Criteria
- [ ] Contains primary documentation sources
- [ ] Chewed analysis covers all key concepts
- [ ] `gmcc_hook call KBITE_GET --json '{"code":"{kbite_name}"}'` accurately reflects the digested resources
```

---

## Final Report

```
Maw Opened: {kbite_name}

**Location**: {kbite_open_root}/{kbite_name}/
**KBite Root** (purpose): {kbite_root}/{kbite_name}/
**Raw-Source Archive** (populated on first digest): {kbite_digested_root}/{kbite_name}/

## Directory Structure Created

```
{kbite_name}/open/
├── MAW_INDEX.md
├── primary/
│   ├── documentation/
│   ├── example_project/
│   ├── api_reference/
│   ├── blogs/
│   └── all_others/
└── secondary/
    └── (same structure)
```

{If KBITE_PURPOSE created: "Created {kbite_root}/{kbite_name}/KBITE_PURPOSE.md for new kbite"}

## Next Steps

1. **Add crunchables**: Place raw source files in appropriate directories
   - Official docs → `primary/documentation/{name}/`
   - Example repos → `primary/example_project/{name}/` or `secondary/example_project/{name}/`
   - API references → `primary/api_reference/{name}/`
   - Blog posts → `secondary/blogs/{name}/`

2. **Chew**: Run `/gm_crunch_chew {kbite_name}` to analyze crunchables

3. **Digest**: Run `/gm_crunch_digest {kbite_name}` to finalize the kbite
```

---

## Error Handling

**Invalid kbite name:**
```
[GMB] Error: Invalid kbite name

Kbite names must be lowercase with underscores only (e.g., "claude_code_sdk").
```

**Write permission denied:**
```
[GMB] Error: Cannot create maw directory

Check permissions on {kbite_open_root}/{kbite_name}
```
