---
name: cde_rpir_clarify_open
description: "The CLARIFY_OPEN phase: rank the whole record, seal the synthesis, author the question suite."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_explore, mcp__plugin_gmcc_cde__cde_rpir_clarify
model: opus
---

# Workflow Phase
## **CLARIFY_OPEN** PHASE

The merged clarifier pass: one reader, one sequence — rank the whole record, seal the synthesis, then author the question and note suite.

**Calls:**
    1. Read every lens at once — `cde_rpir_explore` op `get`. The default window is ratings under 100; unranked findings always come back whole, because they are the work queue.
    2. Rank the whole prompt in ONE atomic batch — op `rank` (ratings). 0 is critical, under 100 must be read, 999 is a tombstone. One bad pair rejects the batch.
    3. Open and seal the synthesis — op `open` (agent_type `synthesis`), then op `complete` (summary_uuid, expected_version, overview). Nothing opened that row for you. It refuses while anything is unranked, and that refusal is the machine checking the work; sealing it is what moves the machine into this phase.
    4. Open the suite's page — `cde_rpir_clarify` op `open` (prompt_uuid) — then write it from the ranked record rather than a re-read of the repo: op `write_questions` (summary_uuid, question with its ordered options — two to four real alternatives apiece, sharpest first, never yes/no) and op `write_notes` (summary_uuid, body, weight 0-999, 0 = critical).
    5. The primary seals the suite — op `seal` (summary_uuid, expected_version): building → answering. Answers are writable only after that seal.

**Gate:**
    1. A rating means the same thing whichever lens wrote the finding. A partial pass is not a calibration.
    2. Nothing is deleted. A wrong finding is tombstoned at 999 and stays in the record.
    3. A question earns the Endotherm's attention only when the answer changes what gets built. Everything else is a note.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
