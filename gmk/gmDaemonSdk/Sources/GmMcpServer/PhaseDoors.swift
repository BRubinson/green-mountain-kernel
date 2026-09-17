import Foundation
import GmDaemonSdk

/// The fifteen phase verbs the pen did not serve, added at v30.
///
/// WHY THESE FIFTEEN, AND WHY NOW. Every one is a verb the daemon has always
/// served and the pen has never exposed, so an agent needing one had to drop to
/// `gm_hook call <VERB> --json '{...}'`. That is not a hypothetical: running the
/// team workflow that produced this change required exactly that for
/// `CLARIFY_OPEN`, `CLARIFY_SEAL`, `CLARIFY_FINALIZE`, `CARE_PACKAGE_OPEN`,
/// `ARCH_OPEN`, `ARCH_PERSIST_ADD`, `ARCH_GENERAL_ADD`, `ARCH_PROPOSE` and
/// `ARCH_APPROVE` — nine of the fifteen, in one prompt. The pen's own
/// instruction text tells agents "where a pen tool exists, it is the write
/// path"; these are the places that sentence had a hole in it.
///
/// THE GAP WAS INVISIBLE UNTIL THE GATE BECAME BIDIRECTIONAL. A roster check
/// that only asks "does every served tool have a VerbSpec?" passes a pen that
/// serves nothing at all. Asking the reverse — "does every declared pen tool
/// get served?" — is what turned these fifteen from folklore into a build
/// failure. See `GmPenTools.rosterProblems()`.
///
/// SHAPES ARE READ OFF THE REQUEST STRUCTS, NOT INVENTED. Each `params` list
/// mirrors its `*Request` field for field, including which are required, so the
/// published schema and the decoder cannot disagree.
func makePhaseDoorTools() -> [Tool] {
    [
        // ── Clarification ────────────────────────────────────────────────
        Tool(
            name: "rpir_open_clarification",
            description: "Open the prompt's clarification summary. No status move — the prompt is already initiated; summaries are opened explicitly since the lifecycle collapsed to three states.",
            params: [
                ("prompt_uuid", "string", "The prompt to open a clarification summary for", true),
            ],
            run: { args, client in
                try client.clarifyOpen(ClarifyOpenRequest(
                    promptUuid: try args.string("prompt_uuid")))
            }),
        Tool(
            name: "rpir_answer_clarification_question",
            description: "Record the user's answer to ONE clarification question. `skip` marks a question deliberately not asked — the append-only record keeps it either way.",
            params: [
                ("question_uuid", "string", "The question being answered", true),
                ("expected_version", "number", "That question's version", true),
                ("answer_text", "string", "The answer, in full — including WHY, since a bare option pick loses the reasoning", false),
                ("selected_option_uuids", "array", "Option rows the user chose", false),
                ("skip", "boolean", "true = deliberately not asked (malformed row, superseded, or moot)", false),
            ],
            run: { args, client in
                try client.clarifyAnswer(ClarifyAnswerRequest(
                    questionUuid: try args.string("question_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    answerText: args.optString("answer_text"),
                    selectedOptionUuids: args.optStrings("selected_option_uuids"),
                    skip: args.optBool("skip") ?? false))
            }),
        Tool(
            name: "rpir_seal_clarification",
            description: "Seal the question suite building → answering. Answers are writable only after this seal; rpir_finalize_clarification is the LATER move (answering → complete). The primary's call, like every seal.",
            params: [
                ("summary_uuid", "string", "The clarification summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
            ],
            run: { args, client in
                try client.clarifySeal(ClarifySealRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version")))
            }),
        Tool(
            name: "rpir_finalize_clarification",
            description: "answering → complete. Every question is answered or skipped; the care package carries the decided intent forward.",
            params: [
                ("summary_uuid", "string", "The clarification summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
            ],
            run: { args, client in
                try client.clarifyFinalize(ClarifyFinalizeRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version")))
            }),
        Tool(
            name: "rpir_open_care_package",
            description: "Open the care package on a clarification summary. Note the selector is the CLARIFICATION SUMMARY uuid, not the prompt uuid — the package hangs off the summary that produced it.",
            params: [
                ("summary_uuid", "string", "The clarification summary uuid", true),
            ],
            run: { args, client in
                try client.carePackageOpen(CarePackageOpenRequest(
                    summaryUuid: try args.string("summary_uuid")))
            }),

        Tool(
            name: "rpir_close_brief",
            description: "Seal the briefing — the briefer's page is done and the agent can go away. Same verb as rpir_write_brief: BRIEFING_COMPLETE both writes the ref set and moves building → ready.",
            params: [
                ("briefing_uuid", "string", "The briefing to complete", true),
                ("expected_version", "number", "The briefing version this write is based on", true),
                ("dope_refs", "array", "Dope dot-path CODES. Pass [] if you searched and found none — omitting is refused", true),
                ("kbite_refs", "array", "Kbite file uuids. Pass [] if you searched and found none", true),
                ("file_change_refs", "array", "file_change uuids. Pass [] if there are none", true),
                ("agent_id", "string", "Self-reported agent id", false),
            ],
            run: { args, client in
                // TWO NAMES, ONE VERB, and that is the bridge's call rather than
                // an accident here: `rpir_write_brief` reads as filling the page
                // and `rpir_close_brief` as finishing with it, while
                // BRIEFING_COMPLETE does both in one write. Serving both means a
                // generated `allowed-tools` grant resolves whichever the author
                // reached for. If one of them ever stops being used, delete the
                // NAME — do not split the verb to justify it.
                try client.briefingComplete(BriefingCompleteRequest(
                    briefingUuid: try args.string("briefing_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    dopeRefs: args.optStrings("dope_refs") ?? [],
                    kbiteRefs: args.optStrings("kbite_refs") ?? [],
                    fileChangeRefs: args.optStrings("file_change_refs") ?? [],
                    agentId: args.optString("agent_id")))
            }),

        // ── Review ───────────────────────────────────────────────────────
        Tool(
            name: "rpir_open_review",
            description: "Open the prompt's review summary. Like the other summaries, opened explicitly rather than as a side effect of a status move.",
            params: [
                ("prompt_uuid", "string", "The prompt to open a review summary for", true),
            ],
            run: { args, client in
                try client.reviewOpen(ReviewOpenRequest(
                    promptUuid: try args.string("prompt_uuid")))
            }),
        Tool(
            name: "rpir_resolve_review_finding",
            description: "Resolve ONE review finding during the fix loop. `open` is deliberately not accepted — it is the initial state, not a resolution, so resolving TO it would be a move backwards through an append-only record.",
            params: [
                ("finding_uuid", "string", "The finding being resolved", true),
                ("expected_version", "number", "That finding's version", true),
                ("status", "string", "fixed|accepted|wont_fix", true),
            ],
            run: { args, client in
                let raw = try args.string("status")
                guard let status = ReviewFindingStatus(rawValue: raw), status != .open else {
                    throw ToolError(message: "status must be fixed, accepted or wont_fix — '\(raw)' is not a resolution")
                }
                return try client.reviewResolve(ReviewResolveRequest(
                    findingUuid: try args.string("finding_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    status: status))
            }),
        Tool(
            name: "rpir_complete_review",
            description: "Seal the review with its overview and verdict.",
            params: [
                ("summary_uuid", "string", "The review summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
                ("overview", "string", "The merged review narrative", true),
                ("verdict", "string", "approved|approved_with_nits|changes_requested", true),
            ],
            run: { args, client in
                let raw = try args.string("verdict")
                guard let verdict = ReviewVerdict(rawValue: raw) else {
                    throw ToolError(message: "verdict must be approved, approved_with_nits or changes_requested — got '\(raw)'")
                }
                return try client.reviewComplete(ReviewCompleteRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    overview: try args.string("overview"),
                    verdict: verdict))
            }),

        // ── Architecture ─────────────────────────────────────────────────
        Tool(
            name: "rpir_open_architecture",
            description: "Open the prompt's architecture summary page — fetch-or-open, idempotent. Opened explicitly like every summary; nothing opens it as a side effect.",
            params: [
                ("prompt_uuid", "string", "The prompt to open an architecture summary for", true),
            ],
            run: { args, client in
                try client.archOpen(ArchOpenRequest(
                    promptUuid: try args.string("prompt_uuid")))
            }),
        Tool(
            name: "rpir_write_architecture_persistence_changes",
            description: "Record ONE persistence-tier change. Persistence rows come before general rows because a schema or wire delta is what the plan gate is signed off against.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("class_name", "string", "The type or table being changed", true),
                ("file_path", "string", "Repo-relative path", true),
                ("reason_brief", "string", "Why this change, and what it costs", true),
                ("change_kind", "string", "add|modify|remove (default modify)", false),
                ("dope_ref", "string", "Dope dot-path CODE, never a uuid", false),
            ],
            run: { args, client in
                try client.archPersistAdd(ArchPersistAddRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    className: try args.string("class_name"),
                    filePath: try args.string("file_path"),
                    reasonBrief: try args.string("reason_brief"),
                    changeKind: args.optString("change_kind"),
                    dopeRef: args.optString("dope_ref")))
            }),
        Tool(
            name: "rpir_write_architecture_general_changes",
            description: "Record ONE general (non-persistence) change. change_depth is pseudo|draft|actual — draft is a planned change not yet written.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("file_path", "string", "Repo-relative path", true),
                ("reason_brief", "string", "Why this change", true),
                ("change_depth", "string", "pseudo|draft|actual", true),
                ("change_code", "string", "The change itself — the implementation spec for this step", true),
                ("class_name", "string", "The type being changed, when there is one", false),
            ],
            run: { args, client in
                let raw = try args.string("change_depth")
                guard let depth = ChangeDepth(rawValue: raw) else {
                    throw ToolError(message: "change_depth must be pseudo, draft or actual — got '\(raw)'")
                }
                return try client.archGeneralAdd(ArchGeneralAddRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    filePath: try args.string("file_path"),
                    className: args.optString("class_name"),
                    reasonBrief: try args.string("reason_brief"),
                    changeDepth: depth,
                    changeCode: try args.string("change_code")))
            }),
        Tool(
            name: "rpir_write_architecture_field_changes",
            description: "Record ONE field-level change under a persistence change row (m0025 grain: add|modify|rename|delete per field).",
            params: [
                ("persistence_change_uuid", "string", "The parent persistence change row", true),
                ("field_name", "string", "The field being changed", true),
                ("data_type", "string", "The field's data type", true),
                ("change_reason", "string", "Why this field changes", true),
                ("change_purpose", "string", "What the change is for", true),
                ("nullable", "boolean", "Whether the field is nullable", true),
                ("is_foreign_key", "boolean", "Whether the field is a foreign key", false),
                ("fk_target", "string", "The FK target when is_foreign_key", false),
                ("is_indexed", "boolean", "Whether the field is indexed", false),
                ("change_kind", "string", "add|modify|rename|delete (default add)", false),
                ("renamed_from", "string", "Old field name when change_kind is rename", false),
                ("dope_property_ref", "string", "domain.entity.property dot-path CODE, ghost-legal", false),
            ],
            run: { args, client in
                try client.archFieldAdd(ArchFieldAddRequest(
                    persistenceChangeUuid: try args.string("persistence_change_uuid"),
                    fieldName: try args.string("field_name"),
                    dataType: try args.string("data_type"),
                    changeReason: try args.string("change_reason"),
                    changePurpose: try args.string("change_purpose"),
                    nullable: args.optBool("nullable") ?? false,
                    isForeignKey: args.optBool("is_foreign_key") ?? false,
                    fkTarget: args.optString("fk_target"),
                    isIndexed: args.optBool("is_indexed") ?? false,
                    changeKind: args.optString("change_kind"),
                    renamedFrom: args.optString("renamed_from"),
                    dopePropertyRef: args.optString("dope_property_ref")))
            }),
        Tool(
            name: "rpir_summarize_architecture",
            description: "Write the architecture summary's own body — the plan narrative over the expanded rows.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
                ("body", "string", "The summary narrative (markdown)", true),
            ],
            run: { args, client in
                try client.archSummarize(ArchSummarizeRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    body: try args.string("body")))
            }),
        Tool(
            name: "rpir_propose_architecture",
            description: "drafting → proposed: put the expanded plan on the table for the plan gate.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
            ],
            run: { args, client in
                try client.archPropose(ArchProposeRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version")))
            }),
        Tool(
            name: "rpir_approve_architecture",
            description: "proposed → approved (terminal; unlocks implementation). The user's sign-off at the plan gate is what authorizes this call.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
            ],
            run: { args, client in
                try client.archApprove(ArchApproveRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version")))
            }),
        Tool(
            name: "rpir_revise_architecture",
            description: "proposed → drafting: the revision edge. Reopens the summary so options and rows can change; compose with rpir_open_architecture_option's supersede form to replace a proposal.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("expected_version", "number", "The summary version this write is based on", true),
            ],
            run: { args, client in
                try client.archRevise(ArchReviseRequest(
                    summaryUuid: try args.string("summary_uuid"),
                    expectedVersion: try args.int64("expected_version")))
            }),
        Tool(
            name: "kbite_open_maw",
            description: "Open a maw — the staging directory a kbite's raw sources are collected into before they are chewed and digested.",
            params: [
                ("kbite_name", "string", "The kbite this maw feeds", true),
                ("maw_path", "string", "Where the maw lives on disk", true),
            ],
            run: { args, client in
                try client.openKbiteMaw(KbiteMawOpenRequest(
                    kbiteName: try args.string("kbite_name"),
                    mawPath: try args.string("maw_path")))
            }),
        Tool(
            name: "kbite_digest",
            description: "Digest a chewed maw into the database and archive its raw sources.",
            params: [
                ("code", "string", "The kbite code being digested", true),
                ("kbite_open_path", "string", "The opened maw's path", true),
            ],
            run: { args, client in
                try client.digestKbite(KbiteDigestRequest(
                    code: try args.string("code"),
                    kbiteOpenPath: try args.string("kbite_open_path")))
            }),
    ]
}
