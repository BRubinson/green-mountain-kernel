import Foundation

// LIVES IN THE BASE LAYER, not beside the Store.
//
// It was filed under Database/ and had to move down for the same reason
// StoreError did: `Protocol/VerbRegistry.swift` declares
// `case record(agentPhases: [WorkflowSpec.Phase]?)`, so the wire-verb registry
// — base layer — names this type. Leaving it in the persistence target is a
// base-depends-on-middle cycle the moment the modules separate.
//
// It also has a second, independent claim on this layer: gm_mcp reads it, and
// gm_mcp links the SDK alone and never touches persistence.
//
// Nothing here is persistence. No GRDB, no Store, no database access — it is
// declarative phase and instruction data that happens to describe a db-derived
// workflow.

/// The workflow phase registry: the per-variant ordered phase graph for the
/// daemon-held bot state machine, and the instruction text each phase hands
/// whoever asks for it.
///
/// Phase is DERIVED from db evidence at every BOT_NEXT — no stored cursor, so
/// resume is the only code path there is. Gates are evaluated by
/// BotWorkflowRepository against these codes, and a new phase or variant is an
/// entry here rather than a schema change.
///
/// PHASE IS NOT PROMPT STATUS, and m0028 made the distinction load-bearing
/// rather than merely true. The prompt row now carries three states —
/// draft / initiated / done — while this file still describes twelve phases.
/// That is not a mismatch: the phases are derived from evidence rather than read
/// off the prompt, which is what let the four middle states go without the
/// machine losing its place.
///
/// ONE EXCEPTION EXISTED and is worth naming rather than rounding off, because
/// "derivation never reads status" is the kind of claim that gets repeated until
/// someone relies on it: the `implement` ENTRY GATE also required the prompt to
/// be in `implementing`. m0028 dropped that condition rather than restating it
/// as `initiated` — with three states it would have been true whenever the phase
/// was reachable, which is not a gate. Architecture approval, which is what the
/// condition was a proxy for, remains the real one. The practical consequence
/// for the prose below is that the mid-workflow `set-status` calls are GONE:
/// the prompt is stamped initiated when its briefing opens, and the next status
/// move it makes is to done. Phase boundaries are crossed by opening and sealing
/// the phase's own rows, which is what they always actually meant.
///
/// Instruction prose is compiled into the binary and drift-guarded by
/// WorkflowSpecTests, which asserts more than presence: WHERE A PEN TOOL
/// EXISTS, THE PROSE MUST NAME THE PEN TOOL. This text is served verbatim
/// through rpir_next to the agents doing the work, so a block that names the
/// wrong write path is the wrong write path, everywhere, at once.
///
/// Verbs with no pen tool are written the way every other daemon verb is
/// reachable: `gm_hook call <MESSAGE_TYPE> --json '{...}'` (or `--json-file`
/// when the body is larger than an argv can carry). Keys are the wire's
/// snake_case, sent verbatim. `gm_hook verbs --json` lists every type the
/// daemon serves.
public enum WorkflowSpec {

    /// Phase codes, in canonical order of appearance across variants.
    public enum Phase: String, CaseIterable, Sendable {
        case briefing
        case explore
        case clarifyOpen = "clarify_open"
        case clarifyUser = "clarify_user"
        case carePackage = "care_package"
        case archOptions = "arch_options"
        case architecture
        case planGate = "plan_gate"
        case implement
        case review
        case reviewFix = "review_fix"
        case done
    }

    /// The ordered phase graph per variant. `task` is deliberately absent —
    /// its write-nothing contract means no workflow row exists to walk.
    public static func phases(for variant: BotVariant) -> [Phase] {
        switch variant {
        case .bot:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser,
                    .architecture, .planGate, .implement, .review, .reviewFix, .done]
        case .rpi:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                    .architecture, .planGate, .implement, .review, .reviewFix, .done]
        case .team:
            return [.briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                    .archOptions, .architecture, .planGate, .implement, .review,
                    .reviewFix, .done]
        }
    }

    /// The exploration agent set each variant must complete before leaving
    /// the explore phase (the synthesis row is gated separately — its
    /// complete IS the prompt-level seal).
    public static func expectedExplorationAgents(for variant: BotVariant) -> [ExplorationAgentType] {
        switch variant {
        case .bot, .rpi:
            return [.general]
        case .team:
            return [.aggressive, .conservative, .pragmatic, .alternative]
        }
    }

    /// Compiled-in instruction text per (variant, phase). Less is more: each
    /// block is what its reader needs NOW — the call, the gate, and nothing
    /// else. Never leave a pair empty, and never name an invocation the pen
    /// already covers.
    ///
    /// THOSE TWO RULES ARE NOW CONVENTIONS AND NOTHING ENFORCES THEM.
    /// `WorkflowSpecTests` used to fail the build on both; it was deleted with
    /// the rest of the repository contract tier in the test rebuild. Check by
    /// hand when adding a phase — an empty block ships a phase whose reader is
    /// told nothing, and it will not fail anything on the way out.
    ///
    /// This function has a SECOND consumer now: `gmAgententicsSdk` reads it live
    /// when assembling a session's per-phase instructions, so its text reaches a
    /// model directly rather than only a harness.
    public static func instructions(variant: BotVariant, phase: Phase) -> String {
        switch phase {
        case .briefing:
            return """
            mcp__plugin_gmcc_cde__rpir_open_briefing opens the briefing row (step: initial). \
            Spawn the haiku briefer: it orients itself with \
            mcp__plugin_gmcc_cde__cde_load_prompt and writes the ref set \
            with mcp__plugin_gmcc_cde__rpir_write_brief. Then gate on \
            mcp__plugin_gmcc_cde__rpir_await_briefing. The machine refuses to leave this \
            phase until the briefing row is ready.
            """
        case .explore:
            let agents = expectedExplorationAgents(for: variant)
                .map(\.rawValue).joined(separator: ", ")
            let spawnNote: String
            let clarifierNote: String
            switch variant {
            case .bot:
                spawnNote = "Explore IN CONTEXT (no subagents): open your general summary and write the finding rows yourself."
                clarifierNote = "run the merged clarifier pass yourself in context"
            case .rpi:
                spawnNote = "Spawn ONE general-persona explorer subagent (it adopts all methodology goals at once)."
                clarifierNote = "spawn ONE gmcc:clarifier"
            case .team:
                spawnNote = "One explorer per methodology, as teammates or a dynamic workflow — script code never writes; the agents hold the pen."
                clarifierNote = "spawn ONE gmcc:clarifier"
            }
            return """
            \(spawnNote) Every explorer works through the pen: \
            mcp__plugin_gmcc_cde__rpir_open_exploration opens its own row (agent_type: \(agents)), \
            mcp__plugin_gmcc_cde__rpir_write_exploration_key_files and \
            mcp__plugin_gmcc_cde__rpir_write_explorations write it, and \
            mcp__plugin_gmcc_cde__rpir_complete_exploration seals THAT row. Leave the findings \
            unranked here — calibration is cross-agent and belongs to one reader.
            When every expected row is complete, \(clarifierNote) for the merged pass — \
            rank, seal the synthesis row, then author the question and note suite. Sealing \
            synthesis is what moves the machine into clarify_open. Open the clarification \
            summary yourself with gm_hook call CLARIFY_OPEN --json \
            '{"prompt_uuid":"<prompt>"}' — it is no longer created for you by a \
            status move.
            """
        case .clarifyOpen:
            return """
            The merged clarifier pass — one reader, one sequence, all pen:
            1. mcp__plugin_gmcc_cde__rpir_get_exploration — every summary and finding. The default \
            window is ratings under 100; unranked findings always come back as full rows.
            2. mcp__plugin_gmcc_cde__rpir_rank_explorations — ONE atomic prompt-wide batch \
            (0 = critical … 999 = tombstone). The ratings are cross-agent: a rating means \
            the same thing whichever persona wrote the finding.
            3. mcp__plugin_gmcc_cde__rpir_open_exploration with agent_type synthesis — the clarifier \
            OPENS the synthesis row itself; nothing else has opened one for it. Then \
            mcp__plugin_gmcc_cde__rpir_complete_exploration seals it with the cross-agent \
            synthesis. That seal is the prompt-level one and it refuses while any finding \
            is unranked.
            4. mcp__plugin_gmcc_cde__rpir_write_clarification_questions (with ordered options) and \
            mcp__plugin_gmcc_cde__rpir_write_clarification_notes (weight 0-999, 0 = critical), written \
            from the ranked record rather than from a re-read of the repo.
            When the pass returns, the primary seals the suite: \
            gm_hook call CLARIFY_SEAL --json \
            '{"summary_uuid":"<clarification>","expected_version":V}'.
            """
        case .clarifyUser:
            var text = """
            Ask the user each open question (AskUserQuestion; options mirror the option \
            rows), record each answer with gm_hook call CLARIFY_ANSWER --json \
            '{"question_uuid":"Q","expected_version":V,"answer_text":"...", \
            "selected_option_uuids":["<option>"],"skip":false}'. At most 2 generative \
            follow-up passes: question-add stays legal while the summary is answering, so \
            add the follow-ups and ask them in the same conversation.
            """
            if variant == .bot {
                text += """
                 When every question is answered or skipped: gm_hook call \
                CLARIFY_FINALIZE --json \
                '{"summary_uuid":"<clarification>","expected_version":V}' (pure gate), \
                then open the architecture summary with gm_hook call ARCH_OPEN --json \
                '{"prompt_uuid":"<prompt>"}'.
                """
            }
            return text
        case .carePackage:
            return """
            Open the package: gm_hook call CARE_PACKAGE_OPEN --json \
            '{"summary_uuid":"<clarification summary>"}'. Then curate through the pen: \
            mcp__plugin_gmcc_cde__rpir_write_care_package with kind dope|kbite|exploration \
            (exploration entries are COPIES of ranked findings written with more intent — \
            never re-explore). Finish with mcp__plugin_gmcc_cde__rpir_close_care_package, \
            clarified_intent being backstory+goal+detail as clarified. The intent \
            lives ONLY here — it is never written back to the prompt row. Then \
            gm_hook call CLARIFY_FINALIZE --json \
            '{"summary_uuid":"<clarification>","expected_version":V}' (pure gate) and \
            gm_hook call ARCH_OPEN --json '{"prompt_uuid":"<prompt>"}'.
            """
        case .archOptions:
            return """
            Spawn one architect per methodology. Each loads the clarified intent with \
            mcp__plugin_gmcc_cde__rpir_get_care_package — not raw exploration — and writes its \
            OWN proposal with mcp__plugin_gmcc_cde__rpir_open_architecture_option (one row per \
            agent_name). Wait for every option before deciding.
            """
        case .architecture:
            if variant == .team {
                return """
                Read the options (mcp__plugin_gmcc_cde__rpir_get_architecture) and pick the winner with \
                mcp__plugin_gmcc_cde__rpir_decide_architecture (option_uuid, expected_version, \
                rationale — it stamps selected, rejects siblings, records why; offer \
                unused-option features to the user later). Then expand ONLY the selected \
                option into rows, persistence FIRST: gm_hook call ARCH_PERSIST_ADD \
                --json '{"summary_uuid":"S","class_name":"...","file_path":"...", \
                "reason_brief":"...","change_kind":"add|modify|rename|delete", \
                "dope_ref":"<entity code>"}', then ARCH_FIELD_ADD (change_kind, \
                renamed_from, dope_property_ref: <property code>), then ARCH_GENERAL_ADD, \
                then ARCH_SUMMARIZE. Write each general row as the instruction its \
                implementer will execute, and name the file_path that implementer owns.
                """
            }
            return """
            Design in context (bot) or via your single subagent (rpi) from the clarified \
            record — in rpi the subagent PROPOSES and returns its proposal in its final \
            message; the primary is what persists it. Every row is written db-natively, \
            persistence FIRST: gm_hook call ARCH_PERSIST_ADD --json \
            '{"summary_uuid":"S","class_name":"...","file_path":"...", \
            "reason_brief":"...","change_kind":"add|modify|rename|delete", \
            "dope_ref":"<entity code>"}', then ARCH_FIELD_ADD (dope_property_ref for \
            renames and deletes), then ARCH_GENERAL_ADD — each row the instruction its \
            implementer will execute, naming the file_path that implementer owns — then \
            ARCH_SUMMARIZE. The architecture rows are one author's work: they are written \
            once, in order, against a single summary_uuid.
            """
        case .planGate:
            return """
            gm_hook call ARCH_PROPOSE --json '{"summary_uuid":"S","expected_version":V}', \
            then present the plan for user sign-off — ALWAYS include the full persistence \
            delta table (positive AND negative changes, dope refs shown). Approve → \
            gm_hook call ARCH_APPROVE --json '{"summary_uuid":"S","expected_version":V}'. \
            The prompt's status does not move here: it was claimed as initiated when its \
            briefing opened, and the next move it makes is to done. Modify → gm_hook call \
            ARCH_REVISE --json \
            '{"summary_uuid":"S","expected_version":V}' and return to architecture.
            """
        case .implement:
            switch variant {
            case .bot:
                return """
                Implement in context, PERSISTENCE CHANGES FIRST — the persistence rows are \
                the contract the general rows are written against. Then prove it: run the \
                build loop this repo documents and report its real output, quoted; a \
                claim is not a result. Do NOT write or run test suites unless the prompt \
                asked for them. Your file writes are captured for you — there is nothing \
                to self-report. mcp__plugin_gmcc_cde__rpir_get_architecture audits progress: planned \
                rows joined to what has actually been touched, plus the unplanned set.
                """
            case .rpi:
                return """
                Implement with up to 2 implementation subagents, PERSISTENCE CHANGES \
                FIRST. Give each agent only the file_path slice the plan assigned it, and \
                say plainly that another agent owns every other file. Each proves its work \
                by running the repo's documented build loop and reporting the real output; \
                none of them writes or runs tests unless the prompt asked. Capture is \
                automatic — no self-reporting. mcp__plugin_gmcc_cde__rpir_get_architecture audits \
                progress.
                """
            case .team:
                return """
                Author the implementation workflow yourself, guided by this state: \
                PERSISTENCE CHANGES FIRST, then services and verbs, then frontend. Script \
                code is pure orchestration — every write happens inside an agent holding \
                the pen. Each agent takes only its assigned file_path slice and must not \
                touch another's. Each proves its work with the repo's documented build \
                loop and reports the real output; tests are not written or run unless the \
                prompt asked. Capture is automatic — no self-reporting. \
                mcp__plugin_gmcc_cde__rpir_get_architecture audits progress.
                """
            }
        case .review:
            let spawn: String
            switch variant {
            case .bot: spawn = "Review in context against the plan and the recorded changes."
            case .rpi: spawn = "Spawn ONE general-persona reviewer subagent."
            case .team: spawn = "Run the review workflow — one reviewer per methodology."
            }
            return """
            Open the summary: gm_hook call REVIEW_OPEN --json '{"prompt_uuid":"<prompt>"}'. \
            \(spawn) Reviewers scope themselves with mcp__plugin_gmcc_cde__rpir_get_architecture and \
            mcp__plugin_gmcc_cde__cde_search_file_changes, read the record so far with \
            mcp__plugin_gmcc_cde__rpir_get_review, and write their findings with \
            mcp__plugin_gmcc_cde__rpir_write_reviews, each rating its own. The primary \
            then runs the one cross-agent calibration pass \
            (mcp__plugin_gmcc_cde__rpir_rank_reviews) and seals with gm_hook call \
            REVIEW_COMPLETE, whose payload is summary_uuid, expected_version, overview and \
            verdict (approved|approved_with_nits|changes_requested). It refuses unranked \
            findings. Write the payload to a file and pass --json-file: an overview is \
            routinely larger than an argv can carry.
            """
        case .reviewFix:
            return """
            Clarify fix intent with the user (fix all / fix critical / proceed), then run \
            the fix loop: every finding under rating 100 gets gm_hook call \
            REVIEW_RESOLVE --json '{"finding_uuid":"F","expected_version":V, \
            "status":"fixed|accepted|wont_fix"}' (legal after complete by design — the fix \
            loop runs post-seal). The fixes are implementation and carry implementation's \
            proof: the documented build loop, run and reported. Team: the fixes themselves \
            may run as a workflow.
            """
        case .done:
            return """
            mcp__plugin_gmcc_cde__cde_set_status status: done (it releases the \
            activation claim and closes the workflow row). Present the completion summary \
            — the db rows are the record, and there are no phase-history files.
            """
        }
    }
}
