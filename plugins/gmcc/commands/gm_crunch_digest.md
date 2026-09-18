---
description: Digest chewed maw resources into the kernel db and archive raw sources
argument-hint: <kbite_name>
allowed-tools: Read, Write, Bash, Glob, Grep, mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest
---

Digest chewed maw resources into the kernel db and archive the raw sources.

**Steps:**
    1. Pre-flight: the maw exists, it has chewed resources, and KBITE_PURPOSE is present. Any missing one stops the run.
    2. Review the chewed resources before writing anything.
    3. Digest into the db.
    4. Archive the raw sources.
    5. Delete the open maw.
    6. Verify the rows landed and report per-file.

**Contract:**
    1. Digest is the one step that writes the record. Verify before deleting the maw — step 5 is not reversible from here.
    2. There is no agent-side backup door. Put the digest to the Endotherm before step 3 when the kbite already exists.
