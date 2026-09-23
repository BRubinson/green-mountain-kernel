---
name: cde_rpir_review_fix
description: "The REVIEW_FIX phase: the settled findings resolved and the rest ruled on."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_review
model: claude-opus-5-5[1m]
---

# Workflow Phase
## **REVIEW_FIX** PHASE

The fix loop, which runs after the seal: every finding worth reading is ruled on, and the real fixes are implementation.

**Calls:**
    1. Settle the fix intent with the Endotherm — fix all, fix critical, or proceed as is.
    2. Rule on each finding under rating 100 — `cde_rpir_review` op `resolve` (finding_uuid, expected_version, status fixed|accepted|wont_fix). Legal after the seal by design: this loop runs post-complete.
    3. Send the real fixes back through the implement shape — the slice the plan names, the native edit surface, the documented build loop, its output quoted.
    4. Where the calibration or the seal has not happened yet, `cde_rpir_review` op `rank` and then op `complete` close the review.

**Gate:**
    1. One reader ranks across reviewers. No reviewer ranks its peers, and none of them resolves.
    2. A finding you did not act on is not tidied away. It is ruled on, in the record; `open` is not an accepted resolution, because it is the initial state.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
