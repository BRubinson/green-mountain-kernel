---
description: Open a maw for collecting kbite resources
argument-hint: <kbite_name>
allowed-tools: Read, Write, Bash, Glob, mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest, Skill
---

**Load the `gmcc` skill before anything else.** It carries the GMB identity and
the GM-CDE rules every step below assumes. Do not begin the work until it is in
context.

Open a maw for collecting kbite resources.

**Steps:**
    1. Check for an existing maw for this kbite. If one is open, report it and stop rather than clobbering it.
    2. Check for a parent KBITE_PURPOSE — a new kbite needs one, an existing kbite already has one.
    3. Create the maw skeleton: the maw root, its crunchables directory, and MAW_INDEX.
    4. For a NEW kbite, write KBITE_PURPOSE.md covering why it exists, its scope, target use cases, related kbites and success criteria.
    5. Report the maw path and what to drop into it.

**Contract:**
    1. One open maw per kbite. A second is a collision, not a convenience.
    2. Raw sources go in untouched — chewing happens in `/gm_crunch_chew`, not here.
