---
description: Import a gmcc_kbite zip into this machine's kernel db
argument-hint: <zip_path> [overwrite]
allowed-tools: Read, Bash, Glob, AskUserQuestion, mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest, Skill
---

**Load the `gmcc` skill before anything else.** It carries the GMB identity and
the GM-CDE rules every step below assumes. Do not begin the work until it is in
context.

Import a `gmcc_kbite` zip into this machine's kernel db.

**Steps:**
    1. Pre-flight the zip path. A missing file stops the run.
    2. Unpack to a staging directory.
    3. Load the db rows.
    4. Restore the files.
    5. Report what was imported.

**Contract:**
    1. A kbite that already exists is a decision, not an error — put the overwrite to the Endotherm before taking it.
    2. Take `gm_hook call BACKUP --json '{}'` before loading rows.
