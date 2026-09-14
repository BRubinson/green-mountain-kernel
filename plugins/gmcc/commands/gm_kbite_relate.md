---
description: Define a relationship between two kbites for cross-referencing
argument-hint: <kbite_from> <kbite_to> <relationship>
allowed-tools: Read, Write, Bash, Glob, mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest, Skill
---

**Load the `gmcc` skill before anything else.** It carries the GMB identity and
the GM-CDE rules every step below assumes. Do not begin the work until it is in
context.

Define a relationship between two kbites for cross-referencing.

**Steps:**
    1. Resolve both kbites. A missing source or target stops the run.
    2. Determine the relationship type from the argument.
    3. Read the existing KBITE_RELATIONSHIPS.md for the source.
    4. Update the source's OUTGOING relationships.
    5. Update the target's INCOMING relationships.
    6. Update the Related KBites section of both KBITE_PURPOSE files.
    7. Report both sides.

**Contract:**
    1. A relationship is written on BOTH sides or neither. A half-written edge is worse than no edge.
