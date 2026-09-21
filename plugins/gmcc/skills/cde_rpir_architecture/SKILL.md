---
name: cde_rpir_architecture
description: "The ARCHITECTURE phase: the plan, persistence changes first and general changes built over them."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **ARCHITECTURE** PHASE

The winner chosen and expanded into rows: persistence first, then the general changes built over it, then the narrative.

**Calls:**
    1. Read what is on the table — `cde_rpir_architecture` op `get`. Where no options were written, design from the clarified record instead; where one agent proposes, the primary is what persists the proposal.
    2. Where options exist, pick the winner — op `decide` (option_uuid, expected_version, rationale). One atomic write stamps it selected, rejects every sibling and records why; a decision whose reasoning is unwritten is re-litigated. Features of the unused options are offered to the Endotherm later, never folded in quietly.
    3. Expand ONLY the winner, persistence FIRST — op `write_persistence` (summary_uuid, class_name, file_path, reason_brief, change_kind add|modify|rename|delete, dope_ref = the entity code), then op `write_field` (persistence_change_uuid, field_name, data_type, change_reason, change_purpose; renamed_from and dope_property_ref on renames and deletes).
    4. Then the rest — op `write_general` (summary_uuid, file_path, reason_brief, change_depth pseudo|draft|actual, change_code). Write each row as the instruction its implementer will execute, and name the file_path that implementer owns.
    5. Write the narrative last — op `summarize` (summary_uuid, expected_version, body): the plan over the expanded rows.

**Gate:**
    1. Persistence leads. A change naming a field that persistence never declared is an instruction nobody can follow.
    2. One file, one change. The rows are one author's work — written once, in order, against a single summary_uuid.
    3. The choice is yours alone in every mission.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
