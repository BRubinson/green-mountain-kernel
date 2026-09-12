---
name: gm_kbite_relate
description: "Define a relationship between two kbites for cross-referencing"
argument-hint: "<kbite_from> <kbite_to> <relationship>"
disable-model-invocation: false
allowed-tools: Read, Write, Bash, Glob
---

# /gm_kbite_relate {kbite_from} {kbite_to} {relationship_description}

Creates or updates a relationship between two kbites, enabling cross-referencing during knowledge lookup.

---

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `{kbite_from}` | Yes | Source kbite name (the one being updated) |
| `{kbite_to}` | Yes | Target kbite name (the one being referenced) |
| `{relationship_description}` | Yes | Description of how they relate |

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
   kbite_digested_root)
2. Verify both kbites exist: known to the db (`gmcc_hook context ensure` for
   the session uuid, then
   `gmcc_hook call KBITE_LIST --json '{"scope":"session","owner_uuid":"{U}","all":true}'`)
   or present at `{kbite_root}/{name}/` (identity root)
3. Parse relationship description to determine type

### If Source KBite Missing
```
[GMB] Error: Source kbite not found: {kbite_from}

Available kbites:
- {codes from the KBITE_LIST response}
```
Exit without changes.

### If Target KBite Missing
```
[GMB] Error: Target kbite not found: {kbite_to}

Available kbites:
- {codes from the KBITE_LIST response}
```
Exit without changes.

---

## Relationship Types

Per the **gmcc_kbite** skill relationship types:

| Type | Meaning | Example |
|------|---------|---------|
| **depends_on** | Source requires knowledge from target | "claude_mcp depends_on claude_code_sdk" |
| **extends** | Source builds upon target with more detail | "claude_hooks extends claude_code_sdk" |
| **complements** | Related but distinct knowledge areas | "react_patterns complements typescript_best_practices" |
| **supersedes** | Source replaces outdated target | "claude_code_v2 supersedes claude_code_v1" |

---

## Execution Steps

### Step 1: Determine Relationship Type

Analyze the `{relationship_description}` to determine the relationship type:

**Keywords for type detection:**
- **depends_on**: "depends", "requires", "needs", "prerequisite", "based on"
- **extends**: "extends", "builds on", "adds to", "enhances", "expands"
- **complements**: "complements", "related to", "alongside", "pairs with", "works with"
- **supersedes**: "supersedes", "replaces", "updates", "newer version", "deprecates"

If unclear, use AskUserQuestion:
```
What type of relationship is this?
- depends_on: {kbite_from} requires {kbite_to}
- extends: {kbite_from} builds upon {kbite_to}
- complements: {kbite_from} and {kbite_to} are related but distinct
- supersedes: {kbite_from} replaces {kbite_to}
```

### Step 2: Read Existing KBITE_RELATIONSHIPS.md

Relationships live at the kbite root (identity-level, like KBITE_PURPOSE.md):
```
{kbite_root}/{kbite_from}/KBITE_RELATIONSHIPS.md
```

If it doesn't exist there but a legacy copy sits at
`{kbite_digested_root}/{kbite_from}/KBITE_RELATIONSHIPS.md`, move the legacy
copy to the root first. If neither exists, create from template per
**gmcc_kbite** skill.

### Step 3: Update Source KBite Outgoing Relationships

Add or update entry in "Outgoing Relationships" table:

```markdown
| Target KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {kbite_to} | {type} | {relationship_description} |
```

### Step 4: Update Target KBite Incoming Relationships

Read `{kbite_root}/{kbite_to}/KBITE_RELATIONSHIPS.md` (same legacy-move rule
as Step 2)

Add or update entry in "Incoming Relationships" table:

```markdown
| Source KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {kbite_from} | {type} | {relationship_description} |
```

### Step 5: Update KBITE_PURPOSE Related KBites

Optionally update the "Related KBites" table in both KBITE_PURPOSE.md files if it exists.

---

## KBITE_RELATIONSHIPS.md Format

Per the **gmcc_kbite** skill:

```markdown
# KBite Relationships: {kbite_name}

## Outgoing Relationships

| Target KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {target} | {depends_on|extends|complements|supersedes} | {description} |

## Incoming Relationships

| Source KBite | Relationship Type | Description |
|--------------|-------------------|-------------|
| {source} | {depends_on|extends|complements|supersedes} | {description} |
```

---

## Final Report

```
Relationship Created

**From**: {kbite_from}
**To**: {kbite_to}
**Type**: {relationship_type}
**Description**: {relationship_description}

## Updated Files

- {kbite_root}/{kbite_from}/KBITE_RELATIONSHIPS.md (outgoing)
- {kbite_root}/{kbite_to}/KBITE_RELATIONSHIPS.md (incoming)

## Relationship Graph (for {kbite_from})

```
{kbite_from}
  ├── depends_on → {list}
  ├── extends → {list}
  ├── complements → {list}
  └── supersedes → {list}
```
```

---

## Error Handling

**Source kbite not found:**
```
[GMB] Error: Source kbite not found: {kbite_from}

Run /gm_crunch_digest {kbite_from} to create the kbite first.
```

**Target kbite not found:**
```
[GMB] Error: Target kbite not found: {kbite_to}

Run /gm_crunch_digest {kbite_to} to create the kbite first.
```

**Self-reference:**
```
[GMB] Error: Cannot create relationship to self

Source and target kbites must be different.
```

**Duplicate relationship:**
```
[GMB] Warning: Relationship already exists

Updating existing relationship from:
  {old_type}: {old_description}
To:
  {new_type}: {new_description}

Continue?
```

**Write failure:**
```
[GMB] Error: Failed to update KBITE_RELATIONSHIPS.md

Check permissions on {kbite_root}/{kbite_name}/
```

---

## Examples

```bash
# Claude MCP depends on Claude Code SDK knowledge
/gm_kbite_relate claude_mcp claude_code_sdk "MCP requires understanding of Claude Code plugin architecture"

# Advanced hooks extends basic hooks
/gm_kbite_relate claude_hooks_advanced claude_hooks "Advanced patterns build on basic hook concepts"

# React and TypeScript complement each other
/gm_kbite_relate react_patterns typescript_best_practices "React patterns work alongside TypeScript best practices"

# New version supersedes old
/gm_kbite_relate claude_code_v2 claude_code_v1 "V2 replaces V1 with updated APIs"
```
