// The per-phase workflow template: the calls each phase is made of, and how each mission staffs it.

import Foundation

let GM_CDE_WORKFLOW_TEMPLATE_HEADER = """
    # Workflow Phase
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

    **Calls:**
        1. Open the page — `rpir_open_briefing(promptUuid, step)`. It performs draft → initiated itself, once. Loading a prompt never does, because a read that advances the prompt makes inspection destructive.
        2. The Briefer orients itself — `rpir_load_exploration_brief`, `cde_load_prompt` — searches with `dope_search_session`, `dope_search_global` and `kbite_search`, and writes all three ref lists with `rpir_write_brief`.
        3. It closes its own page — `rpir_close_brief(briefingUuid, expectedVersion)`.

    **Gate:**
        1. Nothing leaves this phase until the briefing row reads ready. Whoever is blocked on it stays blocked until it does.
        2. An empty ref list is an answer — it says the Briefer looked and found none. An omitted one is a hole nobody can see.
    """

let GM_CDE_PHASE_EXPLORE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **EXPLORE** PHASE

    **Calls:**
        1. Each explorer opens its OWN row — `rpir_open_exploration(promptUuid, agentType)`. Nothing opens one for it.
        2. It writes as it goes — `rpir_write_explorations(exploreUuid, agentName, findings)`. Key files are findings too, kind `key_file`.
        3. It seals its own row and no other — `rpir_complete_exploration(exploreUuid, expectedVersion, overview)`.

    **Gate:**
        1. LEAVE THE FINDINGS UNRANKED HERE. Calibration is cross-agent and belongs to one reader in the next phase.
        2. Every expected summary must be sealed before the phase can close. The synthesis row is not one of them — it is opened later.
    """

let GM_CDE_PHASE_CLARIFY_OPEN_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **CLARIFY_OPEN** PHASE

    **Calls:**
        1. Read every lens at once — `rpir_get_exploration(promptUuid)`. The default window is ratings under 100; unranked findings always come back whole, because they are the work queue.
        2. Rank the whole prompt in ONE atomic batch — `rpir_rank_explorations(promptUuid, ratings)`. 0 is critical, under 100 must be read, 999 is a tombstone. One bad pair rejects the batch.
        3. Open and seal the synthesis — `rpir_open_exploration(promptUuid, "synthesis")`, then `rpir_complete_exploration`. It refuses while anything is unranked, and that refusal is the machine checking the work.
        4. Open the suite's page — `rpir_open_clarification(promptUuid)` — then write it: `rpir_write_clarification_questions` (two to four real alternatives apiece, sharpest first, never yes/no) and `rpir_write_clarification_notes` (weight 0-999).

    **Gate:**
        1. A rating means the same thing whichever lens wrote the finding. A partial pass is not a calibration.
        2. Nothing is deleted. A wrong finding is tombstoned at 999 and stays in the record.
    """

let GM_CDE_PHASE_CLARIFY_USER_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **CLARIFY_USER** PHASE

    **Calls:**
        1. Put the open questions to the Endotherm in ONE batch, leading with your counsel.
        2. Record each answer — `rpir_answer_clarification_question(questionUuid, expectedVersion, ...)`.
        3. Seal the suite — `rpir_finalize_clarification(summaryUuid, expectedVersion)`.

    **Gate:**
        1. No agent ever speaks to the Endotherm. This phase is yours in every mission.
        2. The Endotherm's attention is the rarest fuel there is. A question earns it only when the answer changes what gets built; settle the rest yourself and record them as notes.
    """

let GM_CDE_PHASE_CARE_PACKAGE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **CARE_PACKAGE** PHASE

    **Calls:**
        1. Open the package — `rpir_open_care_package(clarifyUuid)`. The selector is the CLARIFICATION summary, never the prompt.
        2. Curate the refs onto it — `rpir_write_care_package(packageUuid, kind, ...)`, one ref per call: dope codes, kbite files, and COPIES of the exploration that mattered. Never re-explore to fill it.
        3. Settle the intent and seal — `rpir_close_care_package(packageUuid, expectedVersion, clarifiedIntent)`. The intent lives on the close and nowhere else; the seal is the Primarch's.

    **Gate:**
        1. THE CLARIFIED INTENT LIVES ONLY HERE. It is what every downstream agent reads instead of re-deriving the decision from raw exploration.
        2. Say what was ruled out and why. An intent that records only the winner cannot be checked against later.
    """

let GM_CDE_PHASE_ARCH_OPTIONS_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **ARCH_OPTIONS** PHASE

    **Calls:**
        1. Each architect reads the settled intent — `rpir_get_clarification(promptUuid)` — and the ranked record, `rpir_get_exploration(promptUuid)`.
        2. It writes ONE option row of its own — `rpir_open_architecture_option(archUuid, agentName, agentId, body)`: goal, approach, components, persistence delta, files, build sequence, acceptance criteria, trade-offs.

    **Gate:**
        1. One option row per agent. Each writes its own and touches no other.
        2. Costs stated plainly, including the ones that argue against the option. An option whose costs are hidden cannot be weighed.
        3. Nobody here decides.
    """

let GM_CDE_PHASE_ARCHITECTURE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **ARCHITECTURE** PHASE

    **Calls:**
        1. Read what is on the table — `rpir_get_architecture(promptUuid)`.
        2. Pick the winner — `rpir_decide_architecture(optionUuid, expectedVersion, rationale)`. The rationale is not optional: a decision whose reasoning is unwritten is re-litigated.
        3. Expand ONLY the winner — `rpir_write_architecture_persistence_changes` FIRST, then `rpir_write_architecture_general_changes` built over it.

    **Gate:**
        1. Persistence leads. A change naming a field that persistence never declared is an instruction nobody can follow.
        2. One file, one change.
        3. The choice is yours alone in every mission.
    """

let GM_CDE_PHASE_PLAN_GATE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **PLAN_GATE** PHASE

    **Calls:**
        1. Put the expanded plan to the Endotherm and stop.
        2. Read the machine before you move — `rpir_next`. It returns the derived phase and what blocks the next move.

    **Gate:**
        1. THE ENDOTHERM APPROVES BEFORE A STONE IS CUT. This gate is not yours to waive.
        2. Approval is for the plan as expanded, not the plan as described. Show what was written.
    """

let GM_CDE_PHASE_IMPLEMENT_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **IMPLEMENT** PHASE

    **Calls:**
        1. Read the plan — `rpir_get_architecture(promptUuid)`. Persistence leads; the rest is built over it.
        2. Land the change through the native read and edit surface, reaching for the shell only where it cannot.
        3. Check what the machine believes you touched — `cde_search_file_changes(promptUuid)`.

    **Gate:**
        1. Only the files the change description names. A plan improved on the way past is a plan nobody approved.
        2. QUOTED OUTPUT IS THE PROOF. A summary of a build you ran is not the build you ran.
        3. File-change capture is the hook's job, shell included — the PostToolUse hook records every write. Never write capture rows yourself.
    """

let GM_CDE_PHASE_REVIEW_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **REVIEW** PHASE

    **Calls:**
        1. Load the standard — `cde_load_prompt`, `rpir_get_clarification(promptUuid)`, `rpir_get_architecture(promptUuid)`. What was ASKED is what you measure against.
        2. Scope to the real changes — `cde_search_file_changes(promptUuid)` — and read the code around them, never the diff alone.
        3. Read the shared list — `rpir_get_review(promptUuid)` — then write — `rpir_write_reviews(reviewUuid, agentName, findings)`, anchored to file and lines.

    **Gate:**
        1. Every reviewer shares ONE list. Do not restate what another lens already wrote.
        2. A claim with no failure case is an opinion. Name what breaks and the inputs that break it.
        3. Reviewers suggest a verdict; the recorded one is yours.
    """

let GM_CDE_PHASE_REVIEW_FIX_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **REVIEW_FIX** PHASE

    **Calls:**
        1. Calibrate across every reviewer in one pass — `rpir_rank_reviews(summaryUuid, ratings)`.
        2. Rule on what is settled — `rpir_resolve_review_finding`.
        3. Send the real fixes back through the implement shape, then close the review — `rpir_complete_review`.

    **Gate:**
        1. One reader ranks across reviewers. No reviewer ranks its peers, and none of them resolves.
        2. A finding you did not act on is not tidied away. It is ruled on, in the record.
    """

let GM_CDE_PHASE_DONE_TEMPLATE = """
    \(GM_CDE_WORKFLOW_TEMPLATE_HEADER)
    ## **DONE** PHASE

    **Calls:**
        1. Close the prompt — `cde_set_status(promptUuid, expectedVersion, "done")`. The machine holds the claim until you release it.
        2. Report to the Endotherm what IS: what landed, what was withheld, what was skipped.

    **Gate:**
        1. A gilded report is heresy, and it is you who wears it when the Endotherm finds out.
        2. `done` releases the activation claim. Re-opening a finished prompt is a deliberate move back to draft, never a side effect.
    """
