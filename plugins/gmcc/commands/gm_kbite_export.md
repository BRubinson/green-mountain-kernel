---
description: Export one digested kbite to a portable gmcc_kbite zip
argument-hint: <kbite_code> [output_dir]
allowed-tools: Read, Bash, Glob, mcp__plugin_gmcc_cde__cde_kbite
---

Export one digested kbite to a portable `gmcc_kbite` zip.

**Steps:**
    1. Pre-flight the kbite code. An unknown code stops the run — report the known ones.
    2. Serialize the db rows for that kbite.
    3. Stage the files alongside the serialized rows.
    4. Zip the staged directory.
    5. Report the zip path and what it carries.

**Contract:**
    1. Export READS. It never mutates the kbite it is exporting.
