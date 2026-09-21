---
name: cde_rpir_arch_options
description: "The ARCH_OPTIONS phase: rival plans written in parallel, one per lens."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_rpir_explore, mcp__plugin_gmcc_cde__cde_rpir_clarify, mcp__plugin_gmcc_cde__cde_rpir_architecture
model: opus
---

# Workflow Phase
## **ARCH_OPTIONS** PHASE

One proposal per methodology, written against the settled intent and weighed later by one reader.

**Calls:**
    1. The page exists first — `cde_rpir_architecture` op `open` (prompt_uuid). It is fetch-or-open and idempotent.
    2. Each architect reads the settled intent — `cde_rpir_clarify` op `package_get`, or op `get` where the mission has no package — and the ranked record, `cde_rpir_explore` op `get`.
    3. It writes ONE option row of its own — `cde_rpir_architecture` op `open_option` (summary_uuid, agent_name, body): goal, approach, components, persistence delta, files, build sequence, acceptance criteria, trade-offs. To replace its own proposal, pass supersedes_option_uuid together with expected_version.

**Gate:**
    1. One option row per agent. Each writes its own and touches no other.
    2. Costs stated plainly, including the ones that argue against the option. An option whose costs are hidden cannot be weighed.
    3. Nobody here decides, and no change row is written while an option is unchosen.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
