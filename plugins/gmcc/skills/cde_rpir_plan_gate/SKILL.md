---
name: cde_rpir_plan_gate
description: "The PLAN_GATE phase: the Endotherm approves the plan before a stone is cut."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **PLAN_GATE** PHASE

The Endotherm's sign-off on the plan as written, and the one edge back to architecture when it is refused.

**Calls:**
    1. Put the plan on the table — `cde_rpir_architecture` op `propose` (summary_uuid, expected_version): drafting → proposed.
    2. Read the expanded plan back — op `get` — and show the Endotherm what was WRITTEN, ALWAYS including the full persistence delta table: positive and negative changes, dope refs shown. Then stop.
    3. Approved → op `approve` (summary_uuid, expected_version; terminal, and what unlocks implementation). Modify → op `revise` (summary_uuid, expected_version) and return to architecture; op `open_option`'s supersede form (supersedes_option_uuid + expected_version) replaces a proposal in place.

**Gate:**
    1. THE ENDOTHERM APPROVES BEFORE A STONE IS CUT. This gate is not yours to waive.
    2. Approval is for the plan as expanded, not the plan as described. Show what was written.
    3. The prompt's status does not move here. It was claimed as initiated when its briefing opened, and the next move it makes is to done.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
