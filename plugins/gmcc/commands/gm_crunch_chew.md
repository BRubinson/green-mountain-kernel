---
description: Process crunchable resources in a maw to generate chewed analysis files
argument-hint: <kbite_name>
allowed-tools: Read, Write, Bash, Glob, Grep, Task
---

Process crunchable resources in a maw into chewed analysis files.

**Steps:**
    1. Index untracked crunchables — walk the maw for directories that qualify and add what MAW_INDEX does not already carry.
    2. Identify which are pending.
    3. Mark them in-progress in MAW_INDEX before spawning anything.
    4. Spawn one chew agent per pending crunchable. Each reads its own source and nothing else.
    5. Write the chewed files as each agent returns.
    6. Update MAW_INDEX per completion, not in one batch at the end.
    7. Final index pass, then report what was chewed and what remains.

**Contract:**
    1. Record as you go. A crash between step 4 and step 7 must leave MAW_INDEX honest about what finished.
    2. Chewing never edits the raw source. It writes alongside it.
