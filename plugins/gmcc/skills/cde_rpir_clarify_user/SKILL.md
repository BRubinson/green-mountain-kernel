---
name: cde_rpir_clarify_user
description: "The CLARIFY_USER phase: the one conversation with the Endotherm, and its recorded answers."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_clarify, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **CLARIFY_USER** PHASE

The one conversation with the Endotherm: the open questions asked, the answers recorded, the suite closed.

**Calls:**
    1. Put the open questions to the Endotherm in ONE batch, leading with your counsel, the options mirroring the recorded option rows.
    2. Record each answer — `cde_rpir_clarify` op `answer` (question_uuid, expected_version, answer_text, selected_option_uuids, skip).
    3. Follow-ups: at most two generative passes. Op `write_questions` stays legal while the summary is answering, so add them and ask them in the same conversation.
    4. When every question is answered or skipped: where the mission has no care package, seal the suite — op `finalize` (summary_uuid, expected_version, a pure gate) — and open the plan page, `cde_rpir_architecture` op `open` (prompt_uuid). Where a care package follows, that phase carries the finalize.

**Gate:**
    1. No agent ever speaks to the Endotherm. This phase is yours in every mission.
    2. The Endotherm's attention is the rarest fuel there is. A question earns it only when the answer changes what gets built; settle the rest yourself and record them as notes.
    3. `backstory`, `goal` and `detail` are pure human input, and nothing writes prompt content past draft. What was clarified goes into the record, never back onto the prompt row.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
