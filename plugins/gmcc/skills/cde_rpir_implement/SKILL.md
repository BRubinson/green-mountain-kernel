---
name: cde_rpir_implement
description: "The IMPLEMENT phase: the approved change landed, only in the files the plan names."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_prompt, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **IMPLEMENT** PHASE

The approved rows turned into code, each implementer holding only the slice its own change names.

**Calls:**
    1. Read the plan — `cde_rpir_architecture` op `get`. Persistence rows FIRST: they are the contract the general rows were written against.
    2. Land the change through the native read and edit surface, reaching for the shell only where it cannot. Take only the file_path slice your own change row names; another agent owns every other file.
    3. Prove it — run the build loop this repo documents and report its real output, QUOTED. A claim is not a result.
    4. Audit what the machine believes you touched — `cde_prompt` op `file_changes` — and the planned rows joined to it, `cde_rpir_architecture` op `get`, which also carries the unplanned set.

**Gate:**
    1. Only the files the change description names. A plan improved on the way past is a plan nobody approved.
    2. QUOTED OUTPUT IS THE PROOF. A summary of a build you ran is not the build you ran.
    3. No test suite is written or run unless the prompt asked for one.
    4. File-change capture is the PostToolUse hook's job, shell included, and there is nothing to self-report. A shell write is recorded only when the command NAMES its target; an interpreter heredoc, `make` or `./script.sh` records nothing, by design — so a write nothing named is a write nobody sees.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
