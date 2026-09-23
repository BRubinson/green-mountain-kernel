import Foundation

/// What a verb is: a write, or a read.
///
/// A CLASSIFICATION, not a permission — nothing in this file refuses anybody. It exists so the pen sheet can put reads
/// before writes, and so `gm_hook verbs` can say which side of the line a MessageType falls on.
enum VerbRole: Hashable, Sendable {
    /// A write. `agentPhases` is DECLARATIVE metadata: the workflow phases in
    /// which this write normally happens. `nil` means "every phase".
    case record(agentPhases: [WorkflowSpec.Phase]?)

    /// A read.
    case read
}

/// One row per daemon verb: the message, how a human invokes it, the pen tool
/// that replaces that invocation for an agent, and who may call it.
struct VerbSpec: Hashable, Sendable {
    let messageType: MessageType
    /// The canonical `gm` invocation, or "" for transport-internal verbs that
    /// have no CLI surface (HELLO, SUBSCRIBE, EVENT, ERROR).
    let gmInvocation: String
    /// EVERY OTHER `gm` SPELLING THAT SENDS THIS SAME MessageType.
    ///
    /// Wrappers over a single verb — `gm bot summary` IS EXPLORE_OPEN — mean one canonical invocation does not cover
    /// the CLI, and a spelling absent from this list is a write the deny set does not see.
    let gmAliases: [String]
    /// The MCP pen tool an agent uses instead of `gmInvocation`, when one
    /// exists. `nil` means this verb is not on the pen surface.
    let cdeTool: String?
    let role: VerbRole

    /// Canonical first, then every alias.
    ///
    /// Empty for transport-internal verbs.
    var gmInvocations: [String] {
        gmInvocation.isEmpty ? [] : [gmInvocation] + gmAliases
    }

    /// Creates a verb specification.
    /// - Parameters:
    ///   - messageType: The message type this verb handles.
    ///   - gmInvocation: The canonical `gm` command invocation.
    ///   - role: The verb role (read or record).
    ///   - gmAliases: Alternative `gm` command spellings.
    ///   - cdeTool: The MCP pen tool name, or nil if not on the pen surface.
    init(
        _ messageType: MessageType,
        gm gmInvocation: String,
        role: VerbRole,
        aliases gmAliases: [String] = [],
        cde cdeTool: String? = nil
    ) {
        self.messageType = messageType
        self.gmInvocation = gmInvocation
        self.gmAliases = gmAliases
        self.cdeTool = cdeTool
        self.role = role
    }
}

/// The single declaration of the daemon's verb surface, read by the `gm_mcp`
/// pen roster (checked against this at startup), by `CdeSheet`, by `gm_hook
/// verbs` and by the suite, instead of several drifting copies.
///
/// Every `MessageType` must be here or in an explicit allowlist. IT AUTHORIZES
/// NOTHING. The workflow's methodology — one reader calibrates the cross-agent
/// rank, decides among options, and seals — is GUIDANCE carried by
/// `primaryPenTools` and each agent's tool list, never a refusal.
enum VerbRegistry {

    // MARK: - Methodology (guidance, never a gate)

    /// The four pen OPS that ADVANCE the machine, as `tool.op`.
    ///
    /// Named so the pen sheet can tell a persona which calls belong to the reader who calibrates and seals — a
    /// statement about how good work gets produced, not a permission check. Nothing refuses a caller for using one.
    ///
    /// They are ops rather than tools because the consolidation put each of them
    /// on a phase tool every agent already holds: naming the TOOL here would
    /// withhold the whole phase.
    static let primaryPenTools: Set<String> = [
        "cde_prompt.set_status",
        "cde_rpir_architecture.decide",
        "cde_rpir_review.rank",
        "cde_rpir_clarify.package_close",
    ]

    // MARK: - Lookup

    private static let byMessageType: [MessageType: VerbSpec] = {
        var map: [MessageType: VerbSpec] = [:]
        for spec in all { map[spec.messageType] = spec }
        return map
    }()

    /// Looks up a verb spec by message type.
    /// - Parameter type: The message type to look up.
    /// - Returns: The verb spec for the message type, or nil if not found.
    static func spec(for type: MessageType) -> VerbSpec? {
        byMessageType[type]
    }

    /// Every `gm` spelling the registry knows, canonical and alias alike. This
    /// is the set the PreToolUse guard's deny list is generated from and the
    /// set the CLI-coverage test checks `gm`'s command tree against.
    static var gmInvocations: Set<String> {
        Set(all.flatMap(\.gmInvocations))
    }

    /// Looks up a verb spec by `gm` command invocation.
    /// - Parameter invocation: The `gm` command path (canonical or alias).
    /// - Returns: The verb spec for the invocation, or nil if not found.
    static func spec(forInvocation invocation: String) -> VerbSpec? {
        byInvocation[invocation]
    }

    private static let byInvocation: [String: VerbSpec] = {
        var map: [String: VerbSpec] = [:]
        for spec in all {
            for invocation in spec.gmInvocations { map[invocation] = spec }
        }
        return map
    }()

    /// Tools carrying at least one writing op, so the guard can tell a write's
    /// over-budget response from a read's.
    ///
    /// A write that reached the guard has already landed, which makes "call it again, narrower" the one advice a caller
    /// must not follow: these verbs append, so the retry writes a second row. Read off the roster, never hand-listed,
    /// so it cannot drift. The per-OP answer is the one that matters on a mixed tool and lives on `CdeOpSpec.isWrite`;
    /// this is the whole-tool fallback.
    static var writeCdeTools: Set<String> {
        Set(CdeToolRoster.specs.filter { $0.ops.contains(where: \.isWrite) }.map(\.name))
    }

    /// The served roster, which is where a tool name is declared at all.
    static var cdeToolNames: Set<String> { CdeToolRoster.names }

    /// MessageTypes deliberately left out of `all`.
    ///
    /// Daemon → client only: they are never dispatched, so they have no caller and no role.
    static let unroledMessageTypes: Set<MessageType> = [.event, .error]

    // MARK: - The table
    //
    // ONE ROW PER MessageType. Adding a case to MessageType without adding a
    // row here (or to `unroledMessageTypes`) fails VerbRegistryTests.

    static let all: [VerbSpec] = [

        // ── Infra ────────────────────────────────────────────────────────
        VerbSpec(.hello, gm: "", role: .read),
        VerbSpec(.ping, gm: "gm ping", role: .read),
        VerbSpec(.status, gm: "gm status", role: .read),
        // `gm daemon restart` runs Stop before Start — same SHUTDOWN.
        VerbSpec(
            .shutdown,
            gm: "gm daemon stop",
            role: .record(agentPhases: nil),
            aliases: ["gm daemon restart"]
        ),
        VerbSpec(.subscribe, gm: "gm events --follow", role: .read),
        // `gm sandbox refresh` takes the sanctioned Online Backup of prod.
        VerbSpec(
            .backup,
            gm: "gm backup",
            role: .record(agentPhases: nil),
            aliases: ["gm sandbox refresh"]
        ),
        // `gm context env` emits the SessionStart env block from PATHS_GET and
        // nothing else — `Context.Env.run()` calls `pathsGet` alone, and the
        // provisioning write is the separate `gm context ensure`. Registering
        // it as a WRITE would make the guard deny a pure read, which is the
        // fail-CLOSED direction the guard's contract forbids.
        VerbSpec(.pathsGet, gm: "gm paths", role: .read, aliases: ["gm context env"]),
        VerbSpec(.configSet, gm: "gm config set", role: .record(agentPhases: nil)),
        VerbSpec(.eventList, gm: "gm events", role: .read),
        // TX_BATCH is a RECORD verb even though it carries reads as well as
        // writes: the batch commits as one transaction, so the write role of
        // the most privileged inner line is the role of the whole envelope.
        // Registering it as a read would let the guard wave through writes it
        // cannot see, which is the fail-OPEN direction the guard forbids.
        VerbSpec(.txBatch, gm: "gm tx batch", role: .record(agentPhases: nil)),

        // ── Agent test mutual exclusion ──────────────────────────────────
        // A mutex for AGENTS, above the kernel's own flock: flock stops two
        // kernels writing one db, these stop two agents building and testing
        // one repo. `agentPhases: nil` on every write here is deliberate —
        // claiming the test lock is not a workflow phase, and pinning a phase
        // list would refuse the ad-hoc validation the lock exists to
        // serialise.
        VerbSpec(.testSuiteList, gm: "gm test suites", role: .read),
        VerbSpec(.testLockStatus, gm: "gm test lock-status", role: .read),
        VerbSpec(.testLockAcquire, gm: "gm test lock-acquire", role: .record(agentPhases: nil)),
        VerbSpec(.testLockRelease, gm: "gm test lock-release", role: .record(agentPhases: nil)),
        VerbSpec(.testRunStart, gm: "gm test run-start", role: .record(agentPhases: nil)),
        VerbSpec(.testRunStatus, gm: "gm test run-status", role: .read),

        // ── The harness envelope ─────────────────────────────────────────
        // Two TRANSPORTS over one (verb, json) envelope. Both are `.record`
        // rather than `.read`, because an MCP tool call is whatever the tool
        // underneath it is and classing either as `.read` would slip a write
        // past a read-only path. `agentPhases: nil` because phase discipline
        // belongs to the verb being CARRIED, checked when the kernel dispatches
        // it; pinning a list here would apply one prompt's phase to every tool
        // call in the process.
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
        VerbSpec(
            .sessionUpdate,
            gm: "gm session update",
            role: .record(agentPhases: nil),
            cde: "cde_session"
        ),
        VerbSpec(.sessionResolve, gm: "gm session resolve", role: .read),

        // ── Prompts ──────────────────────────────────────────────────────
        VerbSpec(.promptCreate, gm: "gm prompt create", role: .record(agentPhases: nil)),
        VerbSpec(.promptList, gm: "gm prompt list", role: .read, cde: "cde_prompt"),
        // `gm bot current_prompt` resolves the workflow, then sends this.
        VerbSpec(
            .promptGet,
            gm: "gm prompt get",
            role: .read,
            aliases: ["gm bot current_prompt"]
        ),
        VerbSpec(
            .promptUpdateContent,
            gm: "gm prompt update-content",
            role: .record(agentPhases: nil),
            cde: "cde_prompt"
        ),
        // THE ONLY THING THAT MOVES A PROMPT — the primary's call, by methodology.
        VerbSpec(
            .promptSetStatus,
            gm: "gm prompt set-status",
            role: .record(agentPhases: nil),
            cde: "cde_prompt"
        ),
        VerbSpec(.promptStart, gm: "gm prompt start", role: .record(agentPhases: nil)),
        VerbSpec(.promptResume, gm: "gm prompt resume", role: .record(agentPhases: nil)),

        // ── Bot workflow machine ─────────────────────────────────────────
        VerbSpec(
            .botNext,
            gm: "gm bot next",
            role: .read,
            aliases: ["gm bot status"]
        ),
        VerbSpec(.botGet, gm: "gm bot get", role: .read),

        // ── Agent registry ───────────────────────────────────────────────
        // DELIBERATELY NO PEN TOOL. The registration is the SPAWNER's claim
        // about an agent it spawned; an agent registering ITSELF is exactly
        // the self-reported trust this surface replaces. A workflow script
        // calls it, which is the one named exception to "workflow scripts
        // never touch gm".
        // The alias is the SubagentStart half of the same row: the hook writes
        // identity, `gm agent register` writes authority, and both land here.
        VerbSpec(
            .agentRegister,
            gm: "gm agent register",
            role: .record(agentPhases: nil),
            aliases: ["gm_hook_subagent_start"]
        ),

        // ── Artifacts / prompt-qualified diagrams ────────────────────────
        // `gm render` writes the rendered artifact row it just produced.
        VerbSpec(
            .artifactAdd,
            gm: "gm artifact add",
            role: .record(agentPhases: nil),
            aliases: ["gm render"]
        ),
        VerbSpec(.artifactList, gm: "gm artifact list", role: .read),
        VerbSpec(.promptDiagramQualify, gm: "gm prompt-diagram qualify", role: .record(agentPhases: nil)),
        VerbSpec(.promptDiagramGet, gm: "gm prompt-diagram get", role: .read),
        VerbSpec(.promptDiagramList, gm: "gm prompt-diagram list", role: .read),

        // ── File changes ─────────────────────────────────────────────────
        // The `gm_hook_post_tool_use` executable is the SAME write under the
        // machine's spelling, registered as an alias so the PreToolUse deny set
        // can see it: an agent running it by hand would forge capture rows for
        // a tool call that never happened. NO `pen:` NAME, DELIBERATELY —
        // capture happens ONLY as the PostToolUse hook, and a pen door here is
        // that same forgery offered as a typed tool. Do not "complete" this row
        // in a coverage sweep.
        VerbSpec(
            .fileChangeAdd,
            gm: "gm file-change add",
            role: .record(agentPhases: nil),
            aliases: ["gm_hook_post_tool_use"]
        ),
        VerbSpec(.fileChangeList, gm: "gm file-change list", role: .read, cde: "cde_prompt"),

        // ── Kbites ───────────────────────────────────────────────────────
        VerbSpec(.kbiteList, gm: "gm kbite list", role: .read),
        VerbSpec(.kbiteAdd, gm: "gm kbite add", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteRemove, gm: "gm kbite remove", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteMawOpen, gm: "gm kbite maw-open", role: .record(agentPhases: nil), cde: "cde_kbite"),
        VerbSpec(.kbiteDigest, gm: "gm kbite digest", role: .record(agentPhases: nil), cde: "cde_kbite"),
        VerbSpec(.kbiteGet, gm: "gm kbite get", role: .read),
        VerbSpec(.kbiteFileGet, gm: "gm kbite file-get", role: .read),
        VerbSpec(.kbiteSearch, gm: "gm kbite search", role: .read, cde: "cde_kbite"),
        VerbSpec(.kbiteKeywordTag, gm: "gm kbite keyword-tag", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteExport, gm: "gm kbite export", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteImport, gm: "gm kbite import", role: .record(agentPhases: nil)),
        VerbSpec(.kbiteDelete, gm: "gm kbite delete", role: .record(agentPhases: nil)),

        // ── Search ───────────────────────────────────────────────────────
        VerbSpec(.catalogSearch, gm: "gm catalog search", role: .read, cde: "cde_session"),
        VerbSpec(.search, gm: "gm search", role: .read),

        // ── Clarification machine ────────────────────────────────────────
        VerbSpec(
            .clarifyOpen,
            gm: "gm clarify open",
            role: .record(agentPhases: [.clarifyOpen]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(
            .clarifyQuestionAdd,
            gm: "gm clarify question-add",
            role: .record(agentPhases: [.clarifyOpen]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(
            .clarifyNoteAdd,
            gm: "gm clarify note-add",
            role: .record(agentPhases: [.clarifyOpen]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(
            .clarifySeal,
            gm: "gm clarify seal",
            role: .record(agentPhases: [.clarifyOpen]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(
            .clarifyAnswer,
            gm: "gm clarify answer",
            role: .record(agentPhases: [.clarifyUser]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(.clarifyReopen, gm: "gm clarify reopen", role: .record(agentPhases: nil)),
        VerbSpec(
            .clarifyFinalize,
            gm: "gm clarify finalize",
            role: .record(agentPhases: [.clarifyUser]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(.clarifyGet, gm: "gm clarify get", role: .read, cde: "cde_rpir_clarify"),

        // ── Care package ─────────────────────────────────────────────────
        VerbSpec(
            .carePackageOpen,
            gm: "gm clarify package-open",
            role: .record(agentPhases: [.carePackage]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(
            .carePackageRefAdd,
            gm: "gm clarify package-add",
            role: .record(agentPhases: [.carePackage]),
            cde: "cde_rpir_clarify"
        ),
        // The package SEAL: the clarified intent lives only here — the
        // primary's call, by methodology.
        VerbSpec(
            .carePackageComplete,
            gm: "gm clarify package-complete",
            role: .record(agentPhases: [.carePackage]),
            cde: "cde_rpir_clarify"
        ),
        VerbSpec(.carePackageGet, gm: "gm clarify package-get", role: .read, cde: "cde_rpir_clarify"),

        // ── Architecture machine ─────────────────────────────────────────
        VerbSpec(
            .archOpen,
            gm: "gm arch open",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archSummarize,
            gm: "gm arch summarize",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archPersistAdd,
            gm: "gm arch persist-add",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archFieldAdd,
            gm: "gm arch field-add",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archGeneralAdd,
            gm: "gm arch general-add",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archOptionAdd,
            gm: "gm arch option-add",
            role: .record(agentPhases: [.archOptions]),
            cde: "cde_rpir_architecture"
        ),
        // DECIDE selects one option and rejects its siblings — the primary's
        // call, by methodology.
        VerbSpec(
            .archDecide,
            gm: "gm arch decide",
            role: .record(agentPhases: [.archOptions]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archPropose,
            gm: "gm arch propose",
            role: .record(agentPhases: [.architecture]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archApprove,
            gm: "gm arch approve",
            role: .record(agentPhases: [.planGate]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(
            .archRevise,
            gm: "gm arch revise",
            role: .record(agentPhases: [.planGate]),
            cde: "cde_rpir_architecture"
        ),
        VerbSpec(.archGet, gm: "gm arch get", role: .read, cde: "cde_rpir_architecture"),

        // ── Exploration machine ──────────────────────────────────────────
        // bot_summary IS explore open: fetch-or-open the caller's per-agent
        // row. Amendment A2 grants it to the merged clarifier, which is what
        // lets ensureSummary run for a clarifier that never explored.
        //
        // `gm bot summary` is the OTHER CLI spelling of this same verb, and it
        // is the one the cheatsheet core hands to every spawned agent — so it
        // was the guard's single biggest blind spot until it was listed here.
        VerbSpec(
            .exploreOpen,
            gm: "gm explore open",
            role: .record(agentPhases: [.explore, .clarifyOpen]),
            aliases: ["gm bot summary"],
            cde: "cde_rpir_explore"
        ),
        VerbSpec(
            .exploreKeyFileAdd,
            gm: "gm explore key-file-add",
            role: .record(agentPhases: [.explore])
        ),
        VerbSpec(
            .exploreFindingAdd,
            gm: "gm explore finding-add",
            role: .record(agentPhases: [.explore]),
            cde: "cde_rpir_explore"
        ),
        // The rerank belongs to the merged clarifier, which runs in
        // clarify_open.
        VerbSpec(
            .exploreRank,
            gm: "gm explore rank",
            role: .record(agentPhases: [.explore, .clarifyOpen]),
            cde: "cde_rpir_explore"
        ),
        // Any agent may seal synthesis once everything is ranked.
        VerbSpec(
            .exploreComplete,
            gm: "gm explore complete",
            role: .record(agentPhases: [.explore, .clarifyOpen]),
            cde: "cde_rpir_explore"
        ),
        VerbSpec(.exploreReopen, gm: "gm explore reopen", role: .record(agentPhases: nil)),
        VerbSpec(.exploreGet, gm: "gm explore get", role: .read, cde: "cde_rpir_explore"),

        // ── Review machine ───────────────────────────────────────────────
        VerbSpec(.reviewOpen, gm: "gm review open", role: .record(agentPhases: [.review]), cde: "cde_rpir_review"),
        VerbSpec(
            .reviewFindingAdd,
            gm: "gm review finding-add",
            role: .record(agentPhases: [.review, .reviewFix]),
            cde: "cde_rpir_review"
        ),
        // Cross-agent calibration — one reader does it, by methodology.
        VerbSpec(
            .reviewRank,
            gm: "gm review rank",
            role: .record(agentPhases: [.review]),
            cde: "cde_rpir_review"
        ),
        VerbSpec(
            .reviewResolve,
            gm: "gm review resolve",
            role: .record(agentPhases: [.reviewFix]),
            cde: "cde_rpir_review"
        ),
        VerbSpec(
            .reviewComplete,
            gm: "gm review complete",
            role: .record(agentPhases: [.review]),
            cde: "cde_rpir_review"
        ),
        VerbSpec(.reviewReopen, gm: "gm review reopen", role: .record(agentPhases: nil)),
        VerbSpec(.reviewGet, gm: "gm review get", role: .read, cde: "cde_rpir_review"),

        // ── Agent briefing ───────────────────────────────────────────────
        VerbSpec(.briefingOpen, gm: "gm briefing open", role: .record(agentPhases: [.briefing])),
        VerbSpec(
            .briefingComplete,
            gm: "gm briefing complete",
            role: .record(agentPhases: [.briefing]),
            cde: "cde_rpir_briefing"
        ),
        VerbSpec(
            .briefingGet,
            gm: "gm briefing get",
            role: .read,
            aliases: ["gm bot briefing"],
            cde: "cde_rpir_briefing"
        ),
        VerbSpec(.briefingList, gm: "gm briefing list", role: .read),
        VerbSpec(.briefingStub, gm: "gm briefing stub", role: .read),

        // ── DOPED domain modeling ────────────────────────────────────────
        VerbSpec(.dopeInit, gm: "gm dope init", role: .record(agentPhases: nil)),
        VerbSpec(.dopeList, gm: "gm dope list", role: .read),
        VerbSpec(.dopeGet, gm: "gm dope get", role: .read),
        VerbSpec(.dopeSearch, gm: "gm dope search", role: .read, cde: "cde_dope"),
        // ONE MessageType PER LEVEL, FIVE CLI SPELLINGS EACH. Every `gm dope
        // {scope,persistence,entity,property,enum,option}-{add,update,delete}`
        // funnels into these three verbs (Dope.runAdd / runUpdate / runDelete),
        // so all of them are writes and all of them must be visible to the
        // deny set. Only the persistence spelling was registered.
        VerbSpec(
            .dopeNodeAdd,
            gm: "gm dope persistence-add",
            role: .record(agentPhases: nil),
            aliases: [
                "gm dope domain-add", "gm dope entity-add",
                "gm dope property-add", "gm dope enum-add",
                "gm dope option-add",
            ]
        ),
        VerbSpec(
            .dopeNodeUpdate,
            gm: "gm dope persistence-update",
            role: .record(agentPhases: nil),
            aliases: [
                "gm dope domain-update", "gm dope scope-update",
                "gm dope entity-update", "gm dope property-update",
                "gm dope enum-update", "gm dope option-update",
            ]
        ),
        VerbSpec(
            .dopeNodeDelete,
            gm: "gm dope persistence-delete",
            role: .record(agentPhases: nil),
            aliases: [
                "gm dope domain-delete", "gm dope entity-delete",
                "gm dope property-delete", "gm dope enum-delete",
                "gm dope option-delete",
            ]
        ),
        VerbSpec(.dopePromote, gm: "gm dope promote", role: .record(agentPhases: nil)),
        VerbSpec(.dopeReadRepo, gm: "gm dope read-repo", role: .read),
        VerbSpec(.dopeMergePlan, gm: "gm dope merge-plan", role: .read),
        VerbSpec(.dopeResolve, gm: "gm dope resolve", role: .record(agentPhases: nil)),
        VerbSpec(.dopeWriteRepo, gm: "gm dope write-repo", role: .record(agentPhases: nil), cde: "cde_dope"),
        // `gm dope sync` runs DopeBootSync, which sends DOPE_INIT and
        // DOPE_INGEST — a write, files → db, forward only.
        VerbSpec(
            .dopeIngest,
            gm: "gm dope ingest",
            role: .record(agentPhases: nil),
            aliases: ["gm dope sync"]
        ),
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
        VerbSpec(
            .diagramInit,
            gm: "gm diagram init",
            role: .record(agentPhases: nil),
            aliases: ["gm diagram from-dope"]
        ),
        VerbSpec(.diagramList, gm: "gm diagram list", role: .read),
        VerbSpec(.diagramGet, gm: "gm diagram get", role: .read),
        VerbSpec(.diagramSearch, gm: "gm diagram search", role: .read),
        VerbSpec(.diagramNodeAdd, gm: "gm diagram element-add", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeUpdate, gm: "gm diagram element-update", role: .record(agentPhases: nil)),
        VerbSpec(.diagramNodeDelete, gm: "gm diagram element-delete", role: .record(agentPhases: nil)),
        // `gm diagram update` is a one-mutation batch under the hood.
        VerbSpec(
            .diagramBatchApply,
            gm: "gm diagram batch-apply",
            role: .record(agentPhases: nil),
            aliases: ["gm diagram update"]
        ),
        VerbSpec(.diagramDelete, gm: "gm diagram delete", role: .record(agentPhases: nil)),
        VerbSpec(.diagramWriteRepo, gm: "gm diagram write-repo", role: .record(agentPhases: nil)),
        VerbSpec(.diagramIngest, gm: "gm diagram ingest", role: .record(agentPhases: nil)),
    ]
}
