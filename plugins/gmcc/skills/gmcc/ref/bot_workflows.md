# Bot Workflow System Reference

**The single canonical lifecycle document.** Every tier command holds ONLY
its variant contract and points here. Where a tier doc and this file
disagree, this file wins. The LIFECYCLE ITSELF lives in the daemon:
`bot_next` derives the current phase from db evidence and serves that
phase's instructions. This file describes the machine, not the prose.

## The two write channels

Pen tools are `mcp__plugin_gmcc_pen__<name>`; this file names them bare.
Where a pen tool exists it is the write path — typed, threading
`expected_version`. Where none exists, the verb is reached the way every
daemon verb is reached:

```bash
gmcc_hook call <MESSAGE_TYPE> --json '{...}'
gmcc_hook call <MESSAGE_TYPE> --json-file <path>   # when the body outgrows an argv
```

Keys are the wire's snake_case, sent verbatim. `gmcc_hook verbs --json`
lists every MessageType the daemon serves and which of them carry a pen
tool.

## The machine

A bot run adds a **prompt row** to the current session and enters the
workflow machine in one call:

```
prompt_init  selector: "<seq | code | name | fragment>"
             create: true  name: "<name>"
             detail: "<the passed prompt, verbatim>"
             variant: bot | rpi | team
```

It resolves or creates the prompt, reports NEW vs RESUMED, and returns the
uuid bundle, `ckfs_relative_storage_path`, the derived phase with its
instruction text, the next phase's expected agents, the gate blockers, and
whether a briefing exists. Then:

```bash
mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory   # verbatim from the response
```

Resume is the SAME call and the SAME code path — phase is derived, never
stored. `prompt_init` with the selector alone resolves the existing prompt;
`bot_next` re-reads the phase at any time, and after every seal.

`bot_next` returns the current phase, its instruction text (compiled into
the binary, per variant), the phase's uuid bundle, and the gate blockers
for the next phase. It does not advance past unmet gates (the briefing
hard-stop, the exploration seal, clarification finalize, architecture
approval) — mechanically, not by prose. `prompt_set_status` is the only
door that moves a prompt; the machine names the exact call when a status
gate is met and never bypasses it.

Phase graphs (registry-governed — WorkflowSpec in the kit; new phases are
registry entries, never migrations):

| variant | phases |
|---------|--------|
| bot  | briefing → explore → clarify_open → clarify_user → architecture → plan_gate → implement → review → review_fix → done |
| rpi  | … same, plus care_package between clarify_user and architecture |
| team | … same as rpi, plus arch_options before architecture |
| task | NO workflow row (write-nothing contract) — /gm_task is not machine-driven |

## STAY TRUE (prompt content)

`backstory`/`goal`/`detail` are **pure human input**. The passed prompt goes
to `detail` verbatim; never split, infer, or author any of the triple — and
NOTHING writes prompt content past draft. The clarified intent lives on the
CARE PACKAGE.

## Phases (what the machine will tell you, in brief)

1. **briefing** — `init_briefing` opens the row (step `initial`), spawn
   `gmcc:doper` (haiku), gate on `wait_for_briefing`. Briefings are
   OPINION-FREE ref sets (dope dot-paths, kbite files, file changes) — no
   body, and all three ref classes are named even when a class is empty
   (`[]` is a real answer; omitting a class is not). The dead-doper policy:
   on timeout, one plain `briefing_get`; still building → re-open +
   re-spawn once; then proceed briefing-less with an explicit note.
2. **explore** — one summary per expected agent (bot/rpi: general; team: the
   four methodologies), each agent opening its OWN row with `bot_summary`,
   writing it with `explore_key_file_add` / `explore_finding_add`, and
   sealing THAT row with `explore_complete`. Findings stay UNRANKED here —
   calibration is cross-agent and belongs to one reader. When every expected
   row is complete: `prompt_set_status status: clarifying` (the primary's
   call; it locks content and creates the clarification summary), then the
   merged `gmcc:clarifier` pass.
3. **clarify_open** — the merged clarifier pass, one reader and one
   sequence, all pen: `explore_get` the whole record, ONE atomic prompt-wide
   `explore_rank`, then `bot_summary` with agent_type `synthesis` (the
   clarifier OPENS that row itself) and `explore_complete` to seal it — that
   seal is the prompt-level one, it refuses while anything is unranked, and
   it is what moves the machine into this phase. The same pass authors the
   suite: `clarify_question_add` (ordered options) and `clarify_note_add`
   (weight 0-999, 0 = critical). The primary seals the suite when the pass
   returns:

   ```bash
   gmcc_hook call CLARIFY_SEAL --json \
     '{"summary_uuid":"<clarification>","expected_version":V}'
   ```

   In the bot variant the primary runs the pass itself.
4. **clarify_user** — the primary asks (AskUserQuestion mirroring the option
   rows) and records each answer:

   ```bash
   gmcc_hook call CLARIFY_ANSWER --json \
     '{"question_uuid":"Q","expected_version":V,"answer_text":"...",
       "selected_option_uuids":["<option>"],"skip":false}'
   ```

   At most 2 generative follow-up passes — `clarify_question_add` stays
   legal while the summary is answering, so add the follow-ups and ask them
   in the same conversation.
5. **care_package** (rpi/team) — open it with
   `gmcc_hook call CARE_PACKAGE_OPEN --json '{"summary_uuid":"<clarification>"}'`,
   curate refs with `care_ref_add` (`kind` dope|kbite|exploration —
   exploration entries are COPIES of ranked findings, never re-explored),
   then `care_package_complete` with `clarified_intent` = backstory + goal +
   detail, clarified. The intent lives ONLY here. Then
   `gmcc_hook call CLARIFY_FINALIZE --json '{"summary_uuid":"<clarification>","expected_version":V}'`
   (a pure gate) and `prompt_set_status status: architecting`.
6. **arch_options** (team) — one architect per methodology. Each loads the
   clarified intent with `care_package_get` and writes its OWN proposal with
   `arch_option_add` (one row per `agent_name`). Once any option exists,
   change rows wait until `arch_decide` selects one — rejecting the
   siblings and recording the rationale in the same atomic write. Choosing
   among options is cross-agent judgement and belongs to one reader.
7. **architecture** — ONLY the selected option (or the solo design) expands
   into rows, persistence FIRST:

   ```bash
   gmcc_hook call ARCH_PERSIST_ADD --json \
     '{"summary_uuid":"S","class_name":"...","file_path":"...",
       "reason_brief":"...","change_kind":"add|modify|rename|delete",
       "dope_ref":"<entity code>"}'
   ```

   then `ARCH_FIELD_ADD` (`change_kind`, `renamed_from`,
   `dope_property_ref` for renames and deletes), then `ARCH_GENERAL_ADD`,
   then `ARCH_SUMMARIZE`. Write each general row as the instruction its
   implementer will execute, naming the `file_path` that implementer owns.
8. **plan_gate** — `gmcc_hook call ARCH_PROPOSE --json
   '{"summary_uuid":"S","expected_version":V}'`, then user sign-off ALWAYS
   showing the full persistence delta table (positive AND negative changes,
   dope refs shown). Approve → `ARCH_APPROVE` + `prompt_set_status status:
   implementing` (it claims the activation). Modify → `ARCH_REVISE` and back
   to architecture.
9. **implement** — persistence changes first. Capture is the PostToolUse
   hook and nothing else: Edit/Write/NotebookEdit record exactly, with real
   line ranges from the tool's own patch. A Bash write records only when the
   command NAMES its target (redirections, `tee`, `sed -i`, `cp`/`mv`/`rm`/
   `touch`) and carries `origin=command` to mark it an inference; an
   interpreter heredoc, `make` or `./script.sh` records NOTHING, by design —
   there is no tree-diff behind it, so a write nothing named is a write
   nobody sees. Nothing self-reports its own edits. Team: the primary
   hand-authors the implementation workflow, guided by `bot_next` — script
   code is pure orchestration and never writes; the agents inside it hold
   the pen. `arch_get` audits progress (planned rows joined to what has
   actually been touched, plus the unplanned set).
10. **review** — `prompt_set_status status: reviewing`, then
    `gmcc_hook call REVIEW_OPEN --json '{"prompt_uuid":"<prompt>"}'`.
    Reviewers scope themselves with `arch_get` and `file_change_list`, read
    the record with `review_get`, and write findings with
    `review_finding_add`, each rating its own. The primary then runs the one
    cross-agent calibration pass (`review_rank`) and seals with
    `gmcc_hook call REVIEW_COMPLETE --json-file <path>` — payload
    `summary_uuid`, `expected_version`, `overview`, `verdict`
    (approved|approved_with_nits|changes_requested). It refuses unranked
    findings, and an overview is routinely larger than an argv can carry,
    which is why the payload goes through a file.
11. **review_fix** — clarify fix intent with the user, then every finding
    under rating 100 gets
    `gmcc_hook call REVIEW_RESOLVE --json '{"finding_uuid":"F","expected_version":V,"status":"fixed|accepted|wont_fix"}'`
    (legal after complete by design — the fix loop runs post-seal).
12. **done** — `prompt_set_status status: done` (releases the activation
    claim, closes the workflow row). Completion is db rows only — no
    phase-history files.

## Who writes what

Spawned agents write their own rows through the **pen tools**
(`mcp__plugin_gmcc_pen__*` — the plugin's `pen` server): that is the typed,
version-threaded channel, and it is what their tool list gives them. An
agent's Bash is for reading the repo.

Four calls carry the machine forward and belong to one reader — the
primary: `review_rank`, `arch_decide`, `prompt_set_status`,
`care_package_complete`. The reason is methodology, not permission.
Ranking is cross-agent calibration: a rating has to mean the same thing
whichever persona wrote the finding, which only one reader can guarantee.
The choice among architecture options is the same judgement. The seals and
the status advance are where one reader takes responsibility for the whole
record. Alongside them the primary keeps the clarify conversation and
finalize, arch propose/approve, review complete and resolve, and the
phase-opening calls (`BRIEFING_OPEN` via `init_briefing`, `REVIEW_OPEN`,
`CARE_PACKAGE_OPEN`).

Everything else is the agents'. `gmcc:clarifier` owns the exploration rank
AND the synthesis seal — it opens the synthesis row itself, and synthesis
can be sealed once everything is ranked. `gmcc:code-architect` writes
OPTION rows in team flows; its solo proposals stay chat-ephemeral.

**finding_rating (0-999)**: 0 = critical, 999 = tombstone; read threshold
100. Re-runs supersede by re-ranking, never deletion. Notes reuse the same
polarity as `weight`.

## Invariants

- Thread `expected_version` on every mutation; on VERSION_CONFLICT re-get
  and retry. `SUMMARY_ABSENT` = open it; never a file fallback.
- Everything is db rows — never read or write ckfs yamls; never mirror a
  report to a file.
- Reads are windowed by default. `explore_get` / `review_get` return full
  rows for ratings under 100 and stubs beyond it (unranked findings are
  always full); `arch_get` takes `include_options` / `option_uuid` /
  `change_uuid` / `full` / `limit` / `cursor`. Widen deliberately, not by
  habit.
- Zero-uuid resolution (bot verbs, `briefing_get`, auto-attribution) walks:
  caller's own claim → session's single claim → task row. Teammates are
  separate claude processes — their spawn prompts carry the explicit
  `prompt_uuid` forms; every bot verb keeps that escape hatch.
- `agent_id` / `agent_name` are self-reported on every agentic write —
  ClientKey cannot distinguish sibling subagents.
- Dope is search-first (`dope_search` + targeted `dope_get` by `code`);
  full-tree dumps are FORBIDDEN. An architecture proposing persistence is
  proposing dope changes. Kbites are inherited, never auto-detected.

## Error recovery

Daemon unreachable: `bash $GMCC_PLUGIN_ROOT/scripts/build_daemon.sh`, then
`gmcc_hook context ensure`, then retry. `$GMCC_BOOTED` unset: restart
Claude Code. Anything stranded mid-phase: `prompt_init` with the prompt's
selector, then `bot_next` — resume is the first-run code path by
construction.
