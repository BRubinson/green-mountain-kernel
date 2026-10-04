// The per-phase workflow template: the calls each phase is made of, and how each mission staffs it.

import Foundation

let GM_CDE_WORKFLOW_TEMPLATE_HEADER = """
    # Workflow Phase
    """

// The rules every phase body assumes of its reader, appended to each template.
let GM_CDE_WORKFLOW_TEMPLATE_FOOTER = """
    **Always:**
        1. Every cde call is ONE tool plus an `op`. The tool's own description lists the ops it serves; a tool you cannot see is a missing GRANT to report, never a cue to shell to the wire.
        2. Thread `expected_version` on every mutation. On VERSION_CONFLICT re-run the matching read, take its version, and retry — that is a normal outcome of concurrent work, not an error to report.
        3. SUMMARY_ABSENT means the page was never opened. Open it. It is never a reason to fall back to a file.
        4. The record is db rows. Nothing is mirrored to a report file, and the db is append-only — a wrong row is corrected by writing again, never by deletion.
    """

let GM_CDE_STAFF_PRIMARCH = """
    **Staffing:** YOURS. This phase is never handed to an agent.
    """

let GM_CDE_STAFF_IN_CONTEXT = """
    **Staffing:** YOURS. Wear this phase's directive and do the work in your own context. Spawning here is reaching for the wrong mission.
    """

let GM_CDE_STAFF_ONE_MULTI_DIRECTIVE = """
    **Staffing:** ONE agent, wearing every directive this phase touches and this phase's step set alone. Gate on its seal before you move.
    """

let GM_CDE_STAFF_ONE_SINGLE_DIRECTIVE = """
    **Staffing:** ONE agent, wearing exactly this phase's directive and nothing else. Gate on its seal before you move.
    """

let GM_CDE_STAFF_ONE_PER_LENS = """
    **Staffing:** FAN-OUT. One agent per lens, each wearing this phase's directive, each assigned its slant rather than choosing one. Spawn the whole set at once and gate on all of it — a half-complete fan-out is a calibration over a sample.
    """

let GM_CDE_STAFF_ONE_PER_SLICE = """
    **Staffing:** One agent per change description, each touching only the files its own slice names.
    """

let GM_CDE_STAFF_IN_MIND = """
    **Staffing:** NOBODY. Walk this phase in thought. No row is opened, written or sealed here.
    """

let GM_CDE_PHASE_BRIEFING_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_EXPLORE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_CLARIFY_OPEN_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **CLARIFY_OPEN** PHASE

    The merged clarifier pass: one reader, one sequence — rank the whole record, seal the synthesis, then author the question and note suite.

    **Calls:**
        1. Read every lens at once — `cde_rpir_explore` op `get`. The default window is ratings under 100; unranked findings always come back whole, because they are the work queue.
        2. Rank the whole prompt in ONE atomic batch — op `rank` (ratings). 0 is critical, under 100 must be read, 999 is a tombstone. One bad pair rejects the batch.
        3. Open and seal the synthesis — op `open` (agent_type `synthesis`), then op `complete` (summary_uuid, expected_version, overview). Nothing opened that row for you. It refuses while anything is unranked, and that refusal is the machine checking the work; sealing it is what moves the machine into this phase.
        4. Open the suite's page — `cde_rpir_clarify` op `open` (prompt_uuid) — then write it from the ranked record rather than a re-read of the repo: op `write_questions` (summary_uuid, question with its ordered options — two to four real alternatives apiece, sharpest first, never yes/no) and op `write_notes` (summary_uuid, body, weight 0-999, 0 = critical).
        5. The primary seals the suite — op `seal` (summary_uuid, expected_version): building → answering. Answers are writable only after that seal.

    **Gate:**
        1. A rating means the same thing whichever lens wrote the finding. A partial pass is not a calibration.
        2. Nothing is deleted. A wrong finding is tombstoned at 999 and stays in the record.
        3. A question earns the Endotherm's attention only when the answer changes what gets built. Everything else is a note.

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_CLARIFY_USER_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_CARE_PACKAGE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_ARCH_OPTIONS_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_ARCHITECTURE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_PLAN_GATE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **PLAN_GATE** PHASE

    The Endotherm's sign-off on the plan as written, and the one edge back to architecture when it is refused.

    **Calls:**
        1. Put the plan on the table — `cde_rpir_architecture` op `propose` (summary_uuid, expected_version): drafting → proposed.
        2. Read the expanded plan back — op `get` — and show the Endotherm what was WRITTEN, ALWAYS including the full persistence delta table: positive and negative changes, dope refs shown. Then stop.
        3. Approved → op `approve` (summary_uuid, expected_version; terminal, and what unlocks implementation). Modify → op `revise` (summary_uuid, expected_version) and return to architecture; op `open_option`'s supersede form (supersedes_option_uuid + expected_version) replaces a proposal in place.

    **Gate:**
        1. THE ENDOTHERM APPROVES BEFORE A STONE IS CUT. This gate is not yours to waive.
        2. Approval is for the plan as expanded, not the plan as described. Show what was written.
        3. The prompt's status does not move here. It was claimed as initiated when its briefing opened, and the next move it makes is to done.

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_IMPLEMENT_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_REVIEW_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_REVIEW_FIX_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
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

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """

let GM_CDE_PHASE_DONE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **DONE** PHASE

    The prompt closed, the activation claim released, and the Endotherm told what IS.

    **Calls:**
        1. Close the prompt — `cde_prompt` op `set_status` (prompt_uuid, expected_version, status `done`). It is the only door that moves a prompt, it creates no summaries, and it closes the workflow row.
        2. Report to the Endotherm what IS: what landed, what was withheld, what was skipped.

    **Gate:**
        1. A gilded report is heresy, and it is you who wears it when the Endotherm finds out.
        2. `done` releases the activation claim. Re-opening a finished prompt is a deliberate move back to draft, never a side effect.
        3. Completion is db rows. There are no phase-history files, and nothing is mirrored to disk.

    \(GM_CDE_WORKFLOW_TEMPLATE_FOOTER)
    """
