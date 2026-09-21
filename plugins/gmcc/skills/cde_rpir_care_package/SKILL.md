---
name: cde_rpir_care_package
description: "The CARE_PACKAGE phase: the clarified intent curated into the package architecture reads."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_clarify, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **CARE_PACKAGE** PHASE

The clarified intent and the refs that carry it forward: what every downstream agent reads instead of re-deriving the decision.

**Calls:**
    1. Open the package — `cde_rpir_clarify` op `package_open` (summary_uuid = the CLARIFICATION summary, never the prompt).
    2. Curate the refs onto it — op `package_write` (package_uuid, kind dope|kbite|exploration), ONE ref per call: dope dot-path codes, kbite files, and COPIES of the ranked exploration findings that mattered, written with more intent. Never re-explore to fill it.
    3. Settle the intent and seal — op `package_close` (package_uuid, expected_version, clarified_intent = backstory + goal + detail as clarified). The intent lives on the close and nowhere else; the seal is the primary's.
    4. Read the sealed package back with op `package_get`. Then the pure gate and the next page — op `finalize` (summary_uuid, expected_version), then `cde_rpir_architecture` op `open` (prompt_uuid).

**Gate:**
    1. THE CLARIFIED INTENT LIVES ONLY HERE. It is never written back to the prompt row.
    2. Say what was ruled out and why. An intent that records only the winner cannot be checked against later.
    3. The package is curated from what is already in the record. A ref added by going and looking again is exploration done in the wrong phase.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
