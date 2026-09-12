import Foundation

/// The workflow phase registry: the per-variant ordered phase graph for the
/// daemon-held bot state machine, and the instruction text each phase hands
/// whoever asks for it.
///
/// Phase is DERIVED from db evidence at every BOT_NEXT — no stored cursor, so
/// resume is the only code path there is. Gates are evaluated by
/// BotWorkflowRepository against these codes, and a new phase or variant is an
/// entry here rather than a schema change.
///
/// Instruction prose is compiled into the binary and drift-guarded by
/// WorkflowSpecTests, which asserts more than presence: WHERE A PEN TOOL
/// EXISTS, THE PROSE MUST NAME THE PEN TOOL. This text is served verbatim
/// through bot_next to the agents doing the work, so a block that names the
/// wrong write path is the wrong write path, everywhere, at once.
///
/// Verbs with no pen tool are written the way every other daemon verb is
/// reachable: `gmcc_hook call <MESSAGE_TYPE> --json '{...}'` (or `--json-file`
/// when the body is larger than an argv can carry). Keys are the wire's
/// snake_case, sent verbatim. `gmcc_hook verbs --json` lists every type the
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
    /// else. WorkflowSpecTests fails the build on an empty pair, and on a
    /// block that names an invocation the pen already covers.
    public static func instructions(variant: BotVariant, phase: Phase) -> String {
        switch phase {
        case .briefing:
            return """
            mcp__plugin_gmcc_pen__init_briefing opens the briefing row (step: initial). \
            Spawn the haiku doper: it orients itself with \
            mcp__plugin_gmcc_pen__bot_current_prompt and writes the ref set \
            with mcp__plugin_gmcc_pen__briefing_complete. Then gate on \
            mcp__plugin_gmcc_pen__wait_for_briefing. The machine refuses to leave this \
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
            mcp__plugin_gmcc_pen__bot_summary opens its own row (agent_type: \(agents)), \
            mcp__plugin_gmcc_pen__explore_key_file_add and \
            mcp__plugin_gmcc_pen__explore_finding_add write it, and \
            mcp__plugin_gmcc_pen__explore_complete seals THAT row. Leave the findings \
            unranked here — calibration is cross-agent and belongs to one reader.
            When every expected row is complete: mcp__plugin_gmcc_pen__prompt_set_status status: clarifying \
            (the primary's call; it creates the clarification summary), then \
            \(clarifierNote) for the merged pass — rank, seal the synthesis row, then \
            author the question and note suite. Sealing synthesis is what moves the \
            machine into clarify_open.
            """
        case .clarifyOpen:
            return """
            The merged clarifier pass — one reader, one sequence, all pen:
            1. mcp__plugin_gmcc_pen__explore_get — every summary and finding. The default \
            window is ratings under 100; unranked findings always come back as full rows.
            2. mcp__plugin_gmcc_pen__explore_rank — ONE atomic prompt-wide batch \
            (0 = critical … 999 = tombstone). The ratings are cross-agent: a rating means \
            the same thing whichever persona wrote the finding.
            3. mcp__plugin_gmcc_pen__bot_summary with agent_type synthesis — the clarifier \
            OPENS the synthesis row itself; nothing else has opened one for it. Then \
            mcp__plugin_gmcc_pen__explore_complete seals it with the cross-agent \
            synthesis. That seal is the prompt-level one and it refuses while any finding \
            is unranked.
            4. mcp__plugin_gmcc_pen__clarify_question_add (with ordered options) and \
            mcp__plugin_gmcc_pen__clarify_note_add (weight 0-999, 0 = critical), written \
            from the ranked record rather than from a re-read of the repo.
            When the pass returns, the primary seals the suite: \
            gmcc_hook call CLARIFY_SEAL --json \
            '{"summary_uuid":"<clarification>","expected_version":V}'.
            """
        case .clarifyUser:
            var text = """
            Ask the user each open question (AskUserQuestion; options mirror the option \
            rows), record each answer with gmcc_hook call CLARIFY_ANSWER --json \
            '{"question_uuid":"Q","expected_version":V,"answer_text":"...", \
            "selected_option_uuids":["<option>"],"skip":false}'. At most 2 generative \
            follow-up passes: question-add stays legal while the summary is answering, so \
            add the follow-ups and ask them in the same conversation.
            """
            if variant == .bot {
                text += """
                 When every question is answered or skipped: gmcc_hook call \
                CLARIFY_FINALIZE --json \
                '{"summary_uuid":"<clarification>","expected_version":V}' (pure gate), \
                then mcp__plugin_gmcc_pen__prompt_set_status status: architecting.
                """
            }
            return text
        case .carePackage:
            return """
            Open the package: gmcc_hook call CARE_PACKAGE_OPEN --json \
            '{"summary_uuid":"<clarification summary>"}'. Then curate through the pen: \
            mcp__plugin_gmcc_pen__care_ref_add with kind dope|kbite|exploration \
            (exploration entries are COPIES of ranked findings written with more intent — \
            never re-explore). Finish with mcp__plugin_gmcc_pen__care_package_complete, \
            clarified_intent being backstory+goal+detail as clarified. The intent \
            lives ONLY here — it is never written back to the prompt row. Then \
            gmcc_hook call CLARIFY_FINALIZE --json \
            '{"summary_uuid":"<clarification>","expected_version":V}' (pure gate) and \
            mcp__plugin_gmcc_pen__prompt_set_status status: architecting.
            """
        case .archOptions:
            return """
            Spawn one architect per methodology. Each loads the clarified intent with \
            mcp__plugin_gmcc_pen__care_package_get — not raw exploration — and writes its \
            OWN proposal with mcp__plugin_gmcc_pen__arch_option_add (one row per \
            agent_name). Wait for every option before deciding.
            """
        case .architecture:
            if variant == .team {
                return """
                Read the options (mcp__plugin_gmcc_pen__arch_get) and pick the winner with \
                mcp__plugin_gmcc_pen__arch_decide (option_uuid, expected_version, \
                rationale — it stamps selected, rejects siblings, records why; offer \
                unused-option features to the user later). Then expand ONLY the selected \
                option into rows, persistence FIRST: gmcc_hook call ARCH_PERSIST_ADD \
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
            persistence FIRST: gmcc_hook call ARCH_PERSIST_ADD --json \
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
            gmcc_hook call ARCH_PROPOSE --json '{"summary_uuid":"S","expected_version":V}', \
            then present the plan for user sign-off — ALWAYS include the full persistence \
            delta table (positive AND negative changes, dope refs shown). Approve → \
            gmcc_hook call ARCH_APPROVE --json '{"summary_uuid":"S","expected_version":V}' \
            + mcp__plugin_gmcc_pen__prompt_set_status status: implementing (it claims the \
            activation). Modify → gmcc_hook call ARCH_REVISE --json \
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
                to self-report. mcp__plugin_gmcc_pen__arch_get audits progress: planned \
                rows joined to what has actually been touched, plus the unplanned set.
                """
            case .rpi:
                return """
                Implement with up to 2 implementation subagents, PERSISTENCE CHANGES \
                FIRST. Give each agent only the file_path slice the plan assigned it, and \
                say plainly that another agent owns every other file. Each proves its work \
                by running the repo's documented build loop and reporting the real output; \
                none of them writes or runs tests unless the prompt asked. Capture is \
                automatic — no self-reporting. mcp__plugin_gmcc_pen__arch_get audits \
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
                mcp__plugin_gmcc_pen__arch_get audits progress.
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
            mcp__plugin_gmcc_pen__prompt_set_status status: reviewing, then open the \
            summary: gmcc_hook call REVIEW_OPEN --json '{"prompt_uuid":"<prompt>"}'. \
            \(spawn) Reviewers scope themselves with mcp__plugin_gmcc_pen__arch_get and \
            mcp__plugin_gmcc_pen__file_change_list, read the record so far with \
            mcp__plugin_gmcc_pen__review_get, and write their findings with \
            mcp__plugin_gmcc_pen__review_finding_add, each rating its own. The primary \
            then runs the one cross-agent calibration pass \
            (mcp__plugin_gmcc_pen__review_rank) and seals with gmcc_hook call \
            REVIEW_COMPLETE, whose payload is summary_uuid, expected_version, overview and \
            verdict (approved|approved_with_nits|changes_requested). It refuses unranked \
            findings. Write the payload to a file and pass --json-file: an overview is \
            routinely larger than an argv can carry.
            """
        case .reviewFix:
            return """
            Clarify fix intent with the user (fix all / fix critical / proceed), then run \
            the fix loop: every finding under rating 100 gets gmcc_hook call \
            REVIEW_RESOLVE --json '{"finding_uuid":"F","expected_version":V, \
            "status":"fixed|accepted|wont_fix"}' (legal after complete by design — the fix \
            loop runs post-seal). The fixes are implementation and carry implementation's \
            proof: the documented build loop, run and reported. Team: the fixes themselves \
            may run as a workflow.
            """
        case .done:
            return """
            mcp__plugin_gmcc_pen__prompt_set_status status: done (it releases the \
            activation claim and closes the workflow row). Present the completion summary \
            — the db rows are the record, and there are no phase-history files.
            """
        }
    }
}
