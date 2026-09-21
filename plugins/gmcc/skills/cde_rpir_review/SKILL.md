---
name: cde_rpir_review
description: "The REVIEW phase: what was built judged against what was asked."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_prompt, mcp__plugin_gmcc_cde__cde_rpir_clarify, mcp__plugin_gmcc_cde__cde_rpir_architecture, mcp__plugin_gmcc_cde__cde_rpir_review
model: opus
---

# Workflow Phase
## **REVIEW** PHASE

One shared complaints list measured against what was ASKED, calibrated once, and sealed with a verdict.

**Calls:**
    1. Open the page — `cde_rpir_review` op `open` (prompt_uuid). Opened explicitly, like every summary.
    2. Load the standard — `cde_prompt` op `load`, `cde_rpir_clarify` op `get` (and op `package_get` where there is a package), `cde_rpir_architecture` op `get`. What was asked is what you measure against.
    3. Scope to the real changes — `cde_prompt` op `file_changes` — and read the code around them, never the diff alone.
    4. Read the shared list — `cde_rpir_review` op `get` — then write — op `write` (summary_uuid, kind, title, body, agent_name), anchored to file and lines, each reviewer rating only its own findings.
    5. The primary runs the ONE cross-agent calibration pass — op `rank` (summary_uuid, ratings) — and seals — op `complete` (summary_uuid, expected_version, overview, verdict approved|approved_with_nits|changes_requested). It refuses while any finding is unranked.

**Gate:**
    1. Every reviewer shares ONE list. Do not restate what another lens already wrote.
    2. A claim with no failure case is an opinion. Name what breaks and the inputs that break it.
    3. Reviewers suggest a verdict; the recorded one is the primary's. No reviewer ranks its peers, and none of them resolves.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
