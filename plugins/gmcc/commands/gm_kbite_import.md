---
description: Import a gmcc_kbite zip into this machine's kernel db
argument-hint: <zip_path> [overwrite]
allowed-tools: Read, Bash, Glob, AskUserQuestion, mcp__plugin_gmcc_cde__cde_kbite
---

Import a `gmcc_kbite` zip into this machine's kernel db.

**Steps:**
    1. Pre-flight the zip path. A missing file stops the run.
    2. Unpack to a staging directory.
    3. Load the db rows.
    4. Restore the files.
    5. Report what was imported.

**Contract:**
    1. A kbite that already exists is a decision, not an error — put the overwrite to the Endotherm before taking it.
    2. There is no agent-side backup door. The confirmation in 1 is the safeguard; do not load rows without it.
