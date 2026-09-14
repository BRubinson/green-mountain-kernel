import Foundation

/// What a verb is: a write, or a read. A CLASSIFICATION, not a permission —
/// nothing in this file refuses anybody. It exists so the pen sheet can put
/// reads before writes, and so `gm_hook verbs` can say which side of the
/// line a MessageType falls on.
public enum VerbRole: Hashable, Sendable {
    /// A write. `agentPhases` is DECLARATIVE metadata: the workflow phases in
    /// which this write normally happens. `nil` means "every phase".
    case record(agentPhases: [WorkflowSpec.Phase]?)

    /// A read.
    case read
}

/// One row per daemon verb: the message, how a human invokes it, the pen tool
/// that replaces that invocation for an agent, and who may call it.
public struct VerbSpec: Hashable, Sendable {
    public let messageType: MessageType
    /// The canonical `gm` invocation, or "" for transport-internal verbs that
    /// have no CLI surface (HELLO, SUBSCRIBE, EVENT, ERROR).
    public let gmInvocation: String
    /// EVERY OTHER `gm` SPELLING THAT SENDS THIS SAME MessageType.
    ///
    /// The registry's promise is that the deny set cannot drift from the verb
    /// set. One `gmInvocation` per MessageType keeps that promise against the
    /// ROSTER but not against the CLI, because `gm` ships wrappers over single
    /// verbs: `gm bot summary` IS `gm explore open` (EXPLORE_OPEN). A spelling
    /// absent from this list is a write the guard does not see — the drift the
    /// registry exists to make impossible.
    ///
    /// `VerbRegistryTests.testEveryGmLeafCommandIsRegisteredOrExplicitlyLocal`
    /// walks `gm`'s own ArgumentParser tree and fails the build on the next
    /// omission, so this list cannot silently fall behind the CLI.
    public let gmAliases: [String]
    /// The MCP pen tool an agent uses instead of `gmInvocation`, when one
    /// exists. `nil` means this verb is not on the pen surface.
    public let penTool: String?
    public let role: VerbRole

    /// Canonical first, then every alias. Empty for transport-internal verbs.
    public var gmInvocations: [String] {
        gmInvocation.isEmpty ? [] : [gmInvocation] + gmAliases
    }

    public init(
        _ messageType: MessageType,
        gm gmInvocation: String,
        aliases gmAliases: [String] = [],
        pen penTool: String? = nil,
        role: VerbRole
    ) {
        self.messageType = messageType
        self.gmInvocation = gmInvocation
        self.gmAliases = gmAliases
        self.penTool = penTool
        self.role = role
    }
}

/// The single declaration of the daemon's verb surface — one catalogue read by
/// everything that needs to know what verbs exist, instead of several drifting
/// copies:
///
///   1. the `gm_mcp` pen roster (checked against this at startup),
///   2. `PenSheet`, the generated agent-facing sheet,
///   3. `gm_hook verbs`, the machine-readable catalogue,
///   4. the tests (`VerbRegistryTests`, `WorkflowSpecTests`).
///
/// `VerbRegistryTests` asserts every `MessageType` is either here or in an
/// explicit allowlist, so adding a verb without adding a row FAILS THE BUILD —
/// the `CheatsheetTests` precedent applied to the verb catalogue.
///
/// IT AUTHORIZES NOTHING. This is a single-user local dev harness; there is no
/// caller to constrain. The workflow's methodology — the primary calibrates the
/// cross-agent rank, decides among options, and seals — is GUIDANCE carried by
/// `primaryPenTools` below and by each agent's own tool list, never a refusal.
public enum VerbRegistry {

    // MARK: - Methodology (guidance, never a gate)

    /// The four pen tools that ADVANCE the machine. Named so the pen sheet can
    /// tell a persona which calls belong to the reader who calibrates and
    /// seals — a statement about how good work gets produced, not a permission
    /// check. Nothing refuses a caller for using one.
    public static let primaryPenTools: Set<String> = [
        "cde_set_status", "rpir_decide_architecture", "rpir_rank_reviews", "rpir_close_care_package",
    ]

    // MARK: - Lookup

    private static let byMessageType: [MessageType: VerbSpec] = {
        var map: [MessageType: VerbSpec] = [:]
        for spec in all { map[spec.messageType] = spec }
        return map
    }()

    public static func spec(for type: MessageType) -> VerbSpec? {
        byMessageType[type]
    }

    /// Every `gm` spelling the registry knows, canonical and alias alike. This
    /// is the set the PreToolUse guard's deny list is generated from and the
    /// set the CLI-coverage test checks `gm`'s command tree against.
    public static var gmInvocations: Set<String> {
        Set(all.flatMap(\.gmInvocations))
    }

    /// The row a `gm` command path belongs to, whatever spelling it uses.
    public static func spec(forInvocation invocation: String) -> VerbSpec? {
        byInvocation[invocation]
    }

    private static let byInvocation: [String: VerbSpec] = {
        var map: [String: VerbSpec] = [:]
        for spec in all {
            for invocation in spec.gmInvocations { map[invocation] = spec }
        }
        return map
    }()

    /// Every pen tool that is 1:1 with a verb, plus the composites below.
    /// Pen tools whose verb RECORDS something, so the guard can tell a write's
    /// over-budget response from a read's. A write that reached the guard has
    /// already landed, which makes "call it again, narrower" the one advice a
    /// caller must not follow: these verbs append, so the retry writes a
    /// second row. Derived from `role`, never hand-listed, so it cannot drift.
    public static var writePenTools: Set<String> {
        var names = Set(all.compactMap { spec -> String? in
            guard let pen = spec.penTool else { return nil }
            if case .record = spec.role { return pen }
            return nil
        })
        // The composites carry no VerbSpec of their own. Both of these open
        // rows (PROMPT_CREATE/PROMPT_RESUME, BRIEFING_OPEN), so both are writes.
        names.formUnion(["cde_init", "rpir_open_briefing", "rpir_close_brief"])
        return names
    }

    public static var penToolNames: Set<String> {
        Set(all.compactMap(\.penTool)).union(compositePenTools.keys)
    }

    /// Pen tools that are NOT 1:1 with a MessageType — a convenience the pen
    /// composes out of several verbs, so they carry no VerbSpec of their own.
    public static let compositePenTools: [String: [MessageType]] = [
        // FIVE NAMED DOORS OVER ONE VERB (v30). `SEARCH` is full-text across the
        // whole record and takes a `kinds` filter; the bridge names one door per
        // record type because a caller hunting an old finding does not want
        // questions and plans in the result. They sit here rather than as five
        // `pen:` values because `VerbSpec.penTool` is one name per verb — which
        // is the right constraint for the 1:1 case and simply does not describe
        // this one.
        "rpir_search_exploration": [.search],
        "rpir_search_clarification": [.search],
        "rpir_search_architecture": [.search],
        "rpir_search_architecture_option": [.search],
        "rpir_search_review": [.search],
        // Same shape: a second door over DOPE_SEARCH that pins scope to project
        // and refuses the session fallback, which is what makes it global.
        "dope_search_global": [.dopeSearch],
        // A SECOND NAME OVER BRIEFING_COMPLETE. The bridge declares both
        // `rpir_write_brief` (fill the page) and `rpir_close_brief` (done with
        // it); the verb does both in one write. Here rather than as a `pen:`
        // value for the same reason as the searches above — `penTool` is one
        // name per verb, and this is the second.
        "rpir_close_brief": [.briefingComplete],

        // BOT_GET to find the workflow's prompt, then PROMPT_GET to read it.
        "cde_load_prompt": [.botGet, .promptGet],

        // THE COLD-START FAST PATH. One call from "the user typed 10" to a
        // running briefing, composed client-side out of verbs that already
        // exist — which is why none of these needed a new MessageType, a
        // handler, or a migration.
        "cde_init": [
            .contextEnsure,     // $PWD + git branch -> project/instance/session
            .promptList,        // the candidate set the resolver folds over
            .promptCreate,      // only with create:true AND name AND detail
            .promptResume,      // fetch-or-create; its `created` flag is new-vs-resumed
            .botNext,           // phase, instructions, gate blockers
            .briefingGet,       // absent | building | ready
        ],
        "rpir_open_briefing": [.briefingOpen],
    ]

    /// MessageTypes deliberately left out of `all`. Daemon → client only: they
    /// are never dispatched, so they have no caller and no role.
    public static let unroledMessageTypes: Set<MessageType> = [.event, .error]

    // MARK: - The table
    //
    // ONE ROW PER MessageType. Adding a case to MessageType without adding a
    // row here (or to `unroledMessageTypes`) fails VerbRegistryTests.

    public static let all: [VerbSpec] = [

        // ── Infra ────────────────────────────────────────────────────────
        VerbSpec(.hello, gm: "", role: .read),
        VerbSpec(.ping, gm: "gm ping", role: .read),
        VerbSpec(.status, gm: "gm status", role: .read),
        // `gm daemon restart` runs Stop before Start — same SHUTDOWN.
        VerbSpec(.shutdown, gm: "gm daemon stop", aliases: ["gm daemon restart"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.subscribe, gm: "gm events --follow", role: .read),
        // `gm sandbox refresh` takes the sanctioned Online Backup of prod.
        VerbSpec(.backup, gm: "gm backup", aliases: ["gm sandbox refresh"],
                 role: .record(agentPhases: nil)),
        // `gm context env` emits the SessionStart env block from PATHS_GET and
        // nothing else — `Context.Env.run()` calls `pathsGet` alone, and the
        // provisioning write is the separate `gm context ensure`. Registering
        // it as a WRITE would make the guard deny a pure read, which is the
        // fail-CLOSED direction the guard's contract forbids.
        VerbSpec(.pathsGet, gm: "gm paths", aliases: ["gm context env"], role: .read),
        VerbSpec(.configSet, gm: "gm config set", role: .record(agentPhases: nil)),
        VerbSpec(.eventList, gm: "gm events", role: .read),
        // TX_BATCH is a RECORD verb even though it carries reads as well as
        // writes: the batch commits as one transaction, so the write role of
        // the most privileged inner line is the role of the whole envelope.
        // Registering it as a read would let the guard wave through writes it
        // cannot see, which is the fail-OPEN direction the guard forbids.
        VerbSpec(.txBatch, gm: "gm tx batch", role: .record(agentPhases: nil)),

        // ── Agent test mutual exclusion (v29) ────────────────────────────
        // A mutex for AGENTS, above the kernel's own flock: flock stops two
        // kernels writing one db, these stop two agents building and testing
        // one repo.
        //
        // `agentPhases: nil` on all three writes is deliberate rather than
        // unconsidered. Claiming the test lock is not a workflow phase — an
        // agent validating a build may be anywhere in its prompt, or in no
        // prompt at all, and pinning these to a phase list would refuse the
        // exact ad-hoc validation the lock exists to serialise.
        VerbSpec(.testSuiteList, gm: "gm test suites", role: .read),
        VerbSpec(.testLockStatus, gm: "gm test lock-status", role: .read),
        VerbSpec(.testLockAcquire, gm: "gm test lock-acquire", role: .record(agentPhases: nil)),
        VerbSpec(.testLockRelease, gm: "gm test lock-release", role: .record(agentPhases: nil)),
        VerbSpec(.testRunStart, gm: "gm test run-start", role: .record(agentPhases: nil)),
        VerbSpec(.testRunStatus, gm: "gm test run-status", role: .read),

        // ── The harness envelope (v30) ───────────────────────────────────
        //
        // Two TRANSPORTS over one (verb, json) envelope. Both are `.record`
        // rather than `.read`: an MCP tool call is whatever the tool underneath
        // it is, and the roster is majority-write; a hook event exists to
        // record. Classing either as `.read` would let it slip a write past a
        // read-only path.
        //
        // `agentPhases: nil` for the same reason the test-lock writes take it —
        // these are TRANSPORTS, not workflow steps. The phase discipline
        // belongs to the verb being carried, which is checked when the kernel
        // dispatches it, not to the envelope carrying it. Pinning a phase list
        // here would apply one prompt's phase to every tool call in the process.
        VerbSpec(.mcpCall, gm: "gm mcp call", role: .record(agentPhases: nil)),
        VerbSpec(.hookEvent, gm: "gm hook event", role: .record(agentPhases: nil)),

        // ── Context bootstrap ────────────────────────────────────────────
        VerbSpec(.contextEnsure, gm: "gm context ensure", role: .record(agentPhases: nil)),
        VerbSpec(.contextGet, gm: "gm context get", role: .read),

        // ── Project / instance / session ─────────────────────────────────
        VerbSpec(.projectList, gm: "gm project list", role: .read),
        VerbSpec(.projectUpdate, gm: "gm project update", role: .record(agentPhases: nil)),
        VerbSpec(.instanceList, gm: "gm instance list", role: .read),
        VerbSpec(.instanceCurrentSession, gm: "gm instance current-session", role: .read),
        VerbSpec(.sessionList, gm: "gm session list", role: .read),
        VerbSpec(.sessionGet, gm: "gm session get", role: .read),
        VerbSpec(.sessionUpdate, gm: "gm session update", pen: "projects_update_session", role: .record(agentPhases: nil)),
        VerbSpec(.sessionResolve, gm: "gm session resolve", role: .read),

        // ── Prompts ──────────────────────────────────────────────────────
        VerbSpec(.promptCreate, gm: "gm prompt create", role: .record(agentPhases: nil)),
        VerbSpec(.promptList, gm: "gm prompt list", role: .read),
        // `gm bot current_prompt` resolves the workflow, then sends this.
        VerbSpec(.promptGet, gm: "gm prompt get", aliases: ["gm bot current_prompt"],
                 role: .read),
        VerbSpec(.promptUpdateContent, gm: "gm prompt update-content", role: .record(agentPhases: nil)),
        // THE ONLY THING THAT MOVES A PROMPT — the primary's call, by methodology.
        VerbSpec(.promptSetStatus, gm: "gm prompt set-status", pen: "cde_set_status",
                 role: .record(agentPhases: nil)),
        VerbSpec(.promptStart, gm: "gm prompt start", role: .record(agentPhases: nil)),
        VerbSpec(.promptResume, gm: "gm prompt resume", role: .record(agentPhases: nil)),

        // ── Bot workflow machine ─────────────────────────────────────────
        VerbSpec(.botNext, gm: "gm bot next", aliases: ["gm bot status"],
                 pen: "rpir_next", role: .read),
        VerbSpec(.botGet, gm: "gm bot get", role: .read),

        // ── Agent registry ───────────────────────────────────────────────
        // DELIBERATELY NO PEN TOOL. The registration is the SPAWNER's claim
        // about an agent it spawned; an agent registering ITSELF is exactly
        // the self-reported trust this surface replaces. A workflow script
        // calls it, which is the one named exception to "workflow scripts
        // never touch gm".
        // The alias is the SubagentStart half of the same row: the hook writes
        // identity, `gm agent register` writes authority, and both land here.
        VerbSpec(.agentRegister, gm: "gm agent register",
                 aliases: ["gm hook subagent-start"], role: .record(agentPhases: nil)),

        // ── Artifacts / prompt-qualified diagrams ────────────────────────
        // `gm render` writes the rendered artifact row it just produced.
        VerbSpec(.artifactAdd, gm: "gm artifact add", aliases: ["gm render"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.artifactList, gm: "gm artifact list", role: .read),
        VerbSpec(.promptDiagramQualify, gm: "gm prompt-diagram qualify", role: .record(agentPhases: nil)),
        VerbSpec(.promptDiagramGet, gm: "gm prompt-diagram get", role: .read),
        VerbSpec(.promptDiagramList, gm: "gm prompt-diagram list", role: .read),

        // ── File changes ─────────────────────────────────────────────────
        // `gm hook post-tool-use` is the SAME write under the machine's
        // spelling: the hook shim runs it with a raw payload on stdin. It is
        // registered as an alias so the PreToolUse deny set — which is
        // generated from this registry — can see it, because an agent typing
        // it by hand would be forging capture rows for a tool call that never
        // happened.
        VerbSpec(.fileChangeAdd, gm: "gm file-change add",
                 aliases: ["gm hook post-tool-use"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.fileChangeList, gm: "gm file-change list", pen: "cde_search_file_changes", role: .read),

        // ── Kbites ───────────────────────────────────────────────────────
        VerbSpec(.kbiteList, gm: "gm kbite list", role: .read),
        VerbSpec(.kbiteAdd, gm: "gm kbite add", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteRemove, gm: "gm kbite remove", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteMawOpen, gm: "gm kbite maw-open", pen: "kbite_open_maw", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteDigest, gm: "gm kbite digest", pen: "kbite_digest", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteGet, gm: "gm kbite get", role: .read),
        VerbSpec(.kbiteFileGet, gm: "gm kbite file-get", role: .read),
        VerbSpec(.kbiteSearch, gm: "gm kbite search", pen: "kbite_search", role: .read),
        VerbSpec(.kbiteKeywordTag, gm: "gm kbite keyword-tag", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteExport, gm: "gm kbite export", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteImport, gm: "gm kbite import", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteDelete, gm: "gm kbite delete", role: .record(agentPhases: nil)),

        // ── Search ───────────────────────────────────────────────────────
        VerbSpec(.catalogSearch, gm: "gm catalog search", pen: "projects_search", role: .read),
        VerbSpec(.search, gm: "gm search", role: .read),

        // ── Clarification machine ────────────────────────────────────────
        VerbSpec(.clarifyOpen, gm: "gm clarify open", pen: "rpir_open_clarification", role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyQuestionAdd, gm: "gm clarify question-add", pen: "rpir_write_clarification_questions",
                 role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyNoteAdd, gm: "gm clarify note-add", pen: "rpir_write_clarification_notes",
                 role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifySeal, gm: "gm clarify seal", role: .record(agentPhases: [.clarifyOpen])),
        VerbSpec(.clarifyAnswer, gm: "gm clarify answer", pen: "rpir_answer_clarification_question", role: .record(agentPhases: [.clarifyUser])),
        VerbSpec(.clarifyReopen, gm: "gm clarify reopen", role: .record(agentPhases: nil)),
        VerbSpec(.clarifyFinalize, gm: "gm clarify finalize", pen: "rpir_finalize_clarification", role: .record(agentPhases: [.clarifyUser])),
        VerbSpec(.clarifyGet, gm: "gm clarify get", pen: "rpir_get_clarification", role: .read),

        // ── Care package ─────────────────────────────────────────────────
        VerbSpec(.carePackageOpen, gm: "gm clarify package-open", pen: "rpir_open_care_package",
                 role: .record(agentPhases: [.carePackage])),
        VerbSpec(.carePackageRefAdd, gm: "gm clarify package-add", pen: "rpir_write_care_package",
                 role: .record(agentPhases: [.carePackage])),
        // The package SEAL: the clarified intent lives only here — the
        // primary's call, by methodology.
        VerbSpec(.carePackageComplete, gm: "gm clarify package-complete",
                 pen: "rpir_close_care_package", role: .record(agentPhases: [.carePackage])),
        VerbSpec(.carePackageGet, gm: "gm clarify package-get", role: .read),

        // ── Architecture machine ─────────────────────────────────────────
        VerbSpec(.archOpen, gm: "gm arch open", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archSummarize, gm: "gm arch summarize", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archPersistAdd, gm: "gm arch persist-add", pen: "rpir_write_architecture_persistence_changes", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archFieldAdd, gm: "gm arch field-add", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archGeneralAdd, gm: "gm arch general-add", pen: "rpir_write_architecture_general_changes", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archOptionAdd, gm: "gm arch option-add", pen: "rpir_open_architecture_option",
                 role: .record(agentPhases: [.archOptions])),
        // DECIDE selects one option and rejects its siblings — the primary's
        // call, by methodology.
        VerbSpec(.archDecide, gm: "gm arch decide", pen: "rpir_decide_architecture",
                 role: .record(agentPhases: [.archOptions])),
        VerbSpec(.archPropose, gm: "gm arch propose", role: .record(agentPhases: [.architecture])),
        VerbSpec(.archApprove, gm: "gm arch approve", role: .record(agentPhases: [.planGate])),
        VerbSpec(.archRevise, gm: "gm arch revise", role: .record(agentPhases: [.planGate])),
        VerbSpec(.archGet, gm: "gm arch get", pen: "rpir_get_architecture", role: .read),

        // ── Exploration machine ──────────────────────────────────────────
        // bot_summary IS explore open: fetch-or-open the caller's per-agent
        // row. Amendment A2 grants it to the merged clarifier, which is what
        // lets ensureSummary run for a clarifier that never explored.
        //
        // `gm bot summary` is the OTHER CLI spelling of this same verb, and it
        // is the one the cheatsheet core hands to every spawned agent — so it
        // was the guard's single biggest blind spot until it was listed here.
        VerbSpec(.exploreOpen, gm: "gm explore open", aliases: ["gm bot summary"],
                 pen: "rpir_open_exploration",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        VerbSpec(.exploreKeyFileAdd, gm: "gm explore key-file-add",
                 role: .record(agentPhases: [.explore])),
        VerbSpec(.exploreFindingAdd, gm: "gm explore finding-add", pen: "rpir_write_explorations",
                 role: .record(agentPhases: [.explore])),
        // The rerank belongs to the merged clarifier, which runs in
        // clarify_open.
        VerbSpec(.exploreRank, gm: "gm explore rank", pen: "rpir_rank_explorations",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        // Any agent may seal synthesis once everything is ranked.
        VerbSpec(.exploreComplete, gm: "gm explore complete", pen: "rpir_complete_exploration",
                 role: .record(agentPhases: [.explore, .clarifyOpen])),
        VerbSpec(.exploreReopen, gm: "gm explore reopen", role: .record(agentPhases: nil)),
        VerbSpec(.exploreGet, gm: "gm explore get", pen: "rpir_get_exploration", role: .read),

        // ── Review machine ───────────────────────────────────────────────
        VerbSpec(.reviewOpen, gm: "gm review open", pen: "rpir_open_review", role: .record(agentPhases: [.review])),
        VerbSpec(.reviewFindingAdd, gm: "gm review finding-add", pen: "rpir_write_reviews",
                 role: .record(agentPhases: [.review, .reviewFix])),
        // Cross-agent calibration — one reader does it, by methodology.
        VerbSpec(.reviewRank, gm: "gm review rank", pen: "rpir_rank_reviews",
                 role: .record(agentPhases: [.review])),
        VerbSpec(.reviewResolve, gm: "gm review resolve", pen: "rpir_resolve_review_finding", role: .record(agentPhases: [.reviewFix])),
        VerbSpec(.reviewComplete, gm: "gm review complete", pen: "rpir_complete_review", role: .record(agentPhases: [.review])),
        VerbSpec(.reviewReopen, gm: "gm review reopen", role: .record(agentPhases: nil)),
        VerbSpec(.reviewGet, gm: "gm review get", pen: "rpir_get_review", role: .read),

        // ── Agent briefing ───────────────────────────────────────────────
        VerbSpec(.briefingOpen, gm: "gm briefing open", role: .record(agentPhases: [.briefing])),
        VerbSpec(.briefingComplete, gm: "gm briefing complete", pen: "rpir_write_brief",
                 role: .record(agentPhases: [.briefing])),
        VerbSpec(.briefingGet, gm: "gm briefing get", aliases: ["gm bot briefing"],
                 pen: "rpir_load_exploration_brief", role: .read),
        VerbSpec(.briefingList, gm: "gm briefing list", role: .read),
        VerbSpec(.briefingStub, gm: "gm briefing stub", role: .read),

        // ── DOPED domain modeling ────────────────────────────────────────
        VerbSpec(.dopeInit, gm: "gm dope init", role: .record(agentPhases: nil)),
        VerbSpec(.dopeList, gm: "gm dope list", role: .read),
        VerbSpec(.dopeGet, gm: "gm dope get", role: .read),
        VerbSpec(.dopeSearch, gm: "gm dope search", pen: "dope_search_session", role: .read),
        // ONE MessageType PER LEVEL, FIVE CLI SPELLINGS EACH. Every `gm dope
        // {scope,persistence,entity,property,enum,option}-{add,update,delete}`
        // funnels into these three verbs (Dope.runAdd / runUpdate / runDelete),
        // so all of them are writes and all of them must be visible to the
        // deny set. Only the persistence spelling was registered.
        VerbSpec(.dopeNodeAdd, gm: "gm dope persistence-add",
                 aliases: [
                    "gm dope domain-add", "gm dope entity-add",
                    "gm dope property-add", "gm dope enum-add",
                    "gm dope option-add",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeNodeUpdate, gm: "gm dope persistence-update",
                 aliases: [
                    "gm dope domain-update", "gm dope scope-update",
                    "gm dope entity-update", "gm dope property-update",
                    "gm dope enum-update", "gm dope option-update",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeNodeDelete, gm: "gm dope persistence-delete",
                 aliases: [
                    "gm dope domain-delete", "gm dope entity-delete",
                    "gm dope property-delete", "gm dope enum-delete",
                    "gm dope option-delete",
                 ],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopePromote, gm: "gm dope promote", role: .record(agentPhases: nil)),
        VerbSpec(.dopeReadRepo, gm: "gm dope read-repo", role: .read),
        VerbSpec(.dopeMergePlan, gm: "gm dope merge-plan", role: .read),
        VerbSpec(.dopeResolve, gm: "gm dope resolve", role: .record(agentPhases: nil)),
        VerbSpec(.dopeWriteRepo, gm: "gm dope write-repo", pen: "dope_update_session", role: .record(agentPhases: nil)),
        // `gm dope sync` runs DopeBootSync, which sends DOPE_INIT and
        // DOPE_INGEST — a write, files → db, forward only.
        VerbSpec(.dopeIngest, gm: "gm dope ingest", aliases: ["gm dope sync"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogAdd, gm: "gm cog add", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogUpdate, gm: "gm cog update", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogDelete, gm: "gm cog delete", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogGet, gm: "gm cog get", role: .read),
        VerbSpec(.dopeCogElementAdd, gm: "gm cog element-add", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogElementUpdate, gm: "gm cog element-update", role: .record(agentPhases: nil)),
        VerbSpec(.dopeCogElementDelete, gm: "gm cog element-delete", role: .record(agentPhases: nil)),

        // ── Diagrams ─────────────────────────────────────────────────────
        // `gm diagram from-dope` regenerates a canvas: DIAGRAM_INIT, then one
        // atomic DIAGRAM_BATCH_APPLY.
        VerbSpec(.diagramInit, gm: "gm diagram init", aliases: ["gm diagram from-dope"],
                 role: .record(agentPhases: nil)),
        VerbSpec(.diagramList, gm: "gm diagram list", role: .read),
        VerbSpec(.diagramGet, gm: "gm diagram get", role: .read),
        VerbSpec(.diagramSearch, gm: "gm diagram search", role: .read),
        VerbSpec(.diagramNodeAdd, gm: "gm diagram element-add", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeUpdate, gm: "gm diagram element-update", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeDelete, gm: "gm diagram element-delete", role: .record(agentPhases: nil)),
        // `gm diagram update` is a one-mutation batch under the hood.
        VerbSpec(.diagramBatchApply, gm: "gm diagram batch-apply",
                 aliases: ["gm diagram update"], role: .record(agentPhases: nil)),
        VerbSpec(.diagramDelete, gm: "gm diagram delete", role: .record(agentPhases: nil)),
        VerbSpec(.diagramWriteRepo, gm: "gm diagram write-repo", role: .record(agentPhases: nil)),
        VerbSpec(.diagramIngest, gm: "gm diagram ingest", role: .record(agentPhases: nil)),
    ]
}
