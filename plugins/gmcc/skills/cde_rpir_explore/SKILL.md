---
name: cde_rpir_explore
description: "The EXPLORE phase: one finding list per explorer, written as the codebase is read."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_explore, mcp__plugin_gmcc_cde__cde_rpir_clarify
model: claude-opus-5-5[1m]
---

# Workflow Phase
## **EXPLORE** PHASE

One finding list per explorer: what is true of this codebase, written down as it is found.

**Calls:**
    1. Each explorer opens its OWN row — `cde_rpir_explore` op `open` (agent_type: `general` where one lens explores, one per methodology where the mission fans out). Nothing opens one for it.
    2. It writes as it goes — op `write` (summary_uuid, kind, title, body, agent_name), ONE finding per call, self-rated 0 = critical … 999 = ignore. Key files are findings too, kind `key_file`.
    3. It seals its own row and no other — op `complete` (summary_uuid, expected_version, overview).
    4. THE PRIMARY'S CALL, never an explorer's: when every expected row is sealed, the primary opens the clarification page — `cde_rpir_clarify` op `open` (prompt_uuid). No status move happens here: the prompt has been initiated since its briefing opened, and no summary is created as a side effect.

**Gate:**
    1. LEAVE THE CROSS-AGENT RANKING ALONE HERE. An explorer rates only its own findings; calibration is one reader's job in the next phase.
    2. Every expected summary must be sealed before the phase can close. The synthesis row is not one of them — the clarifier opens it later.
    3. `agent_name` and `agent_id` are self-reported on every write. The client key cannot tell sibling agents apart, so a write that does not name its author is a finding nobody can attribute.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
