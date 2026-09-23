---
name: cde_rpir_done
description: "The DONE phase: the prompt closed and the activation claim released."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_prompt
model: claude-opus-5-5[1m]
---

# Workflow Phase
## **DONE** PHASE

The prompt closed, the activation claim released, and the Endotherm told what IS.

**Calls:**
    1. Close the prompt — `cde_prompt` op `set_status` (prompt_uuid, expected_version, status `done`). It is the only door that moves a prompt, it creates no summaries, and it closes the workflow row.
    2. Report to the Endotherm what IS: what landed, what was withheld, what was skipped.

**Gate:**
    1. A gilded report is heresy, and it is you who wears it when the Endotherm finds out.
    2. `done` releases the activation claim. Re-opening a finished prompt is a deliberate move back to draft, never a side effect.
    3. Completion is db rows. There are no phase-history files, and nothing is mirrored to disk.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
