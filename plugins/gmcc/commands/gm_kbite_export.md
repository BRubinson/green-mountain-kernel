---
description: Export one digested kbite to a portable gmcc_kbite zip
argument-hint: <kbite_code> [output_dir]
allowed-tools: Read, Bash, Glob, mcp__plugin_gmcc_cde__kbite_search, mcp__plugin_gmcc_cde__kbite_open_maw, mcp__plugin_gmcc_cde__kbite_digest, Skill
---

**Load the `gmcc` skill before anything else.** It carries the GMB identity and
the GM-CDE rules every step below assumes. Do not begin the work until it is in
context.

Export one digested kbite to a portable `gmcc_kbite` zip.

**Steps:**
    1. Pre-flight the kbite code. An unknown code stops the run — report the known ones.
    2. Serialize the db rows for that kbite.
    3. Stage the files alongside the serialized rows.
    4. Zip the staged directory.
    5. Report the zip path and what it carries.

**Contract:**
    1. Export READS. It never mutates the kbite it is exporting.
