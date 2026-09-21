---
name: cde_rpir_briefing
description: "The BRIEFING phase: the prompt's opinion-free orientation page, sealed before anything else moves."
user-invocable: false
allowed-tools: mcp__plugin_gmcc_cde__cde_init, mcp__plugin_gmcc_cde__cde_dope, mcp__plugin_gmcc_cde__cde_kbite, mcp__plugin_gmcc_cde__cde_prompt, mcp__plugin_gmcc_cde__cde_rpir_briefing
model: opus
---

# Workflow Phase
## **BRIEFING** PHASE

The prompt's orientation page: an opinion-free ref set, written by a briefer and sealed before anything else moves.

**Calls:**
    1. Open the page — `cde_rpir_briefing` op `open` (prompt_uuid, step `initial`). It performs draft → initiated itself, once, and it is the only legal answer to the "initial briefing not ready" blocker. Loading a prompt never advances it, because a read that advances the prompt makes inspection destructive.
    2. The briefer orients itself — `cde_prompt` op `load`, `cde_rpir_briefing` op `load` — and searches: `cde_dope` op `search_session` and op `search_global`, `cde_kbite` op `search`, `cde_prompt` op `file_changes`.
    3. It writes the ref set — `cde_rpir_briefing` op `write` (briefing_uuid, expected_version, dope_refs, kbite_refs, file_change_refs). The daemon stamps staleness and the kbite briefs; the briefer supplies no opinion.
    4. It seals its own page — `cde_rpir_briefing` op `close` (same arguments) — and goes away.

**Gate:**
    1. Nothing leaves this phase until the briefing row reads ready. Whoever is blocked on it stays blocked until it does.
    2. ALL THREE ref classes are required of the briefer. An empty list is an answer — it says the briefer looked and found none; an omitted class is refused, because absent and never-looked-for are indistinguishable.
    3. Dope refs are dot-path CODES (domain.entity.property), never uuids.
    4. A briefer that never returns: take one plain `cde_rpir_briefing` op `load`; still building → open and re-spawn ONCE; then proceed briefing-less with an explicit note in the record.

**Always:**
    1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
    2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
    3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
    4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
