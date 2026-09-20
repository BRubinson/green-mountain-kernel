import Foundation
import GmDaemonSdk

// gm_mcp — the GMCC MCP stdio server: the agent PEN surface as typed MCP
// tools. A thin client of the daemon socket that reuses DaemonClient/WireCodec
// and NEVER touches the db, keeping the single-writer invariant. JSON-RPC 2.0
// is hand-rolled over newline-delimited stdio for exactly initialize,
// tools/list, tools/call and ping.

// THE SURFACE IS THE PEN, AND VerbRegistry DECLARES IT. Every tool below is a
// VerbSpec row carrying `pen:`, checked against the registry at startup so the
// two cannot drift. Nothing here authorizes anything: which tools an agent
// holds is set by its own definition, and the workflow's methodology is
// GUIDANCE in that definition and the pen sheet, never a refusal.

// READS MATTER AS MUCH AS WRITES: an agent that cannot read its own rows
// through the cde server shells out, and is then already outside it when it
// writes. Every read is PAGED here, in this layer, by `CdePager` over the
// daemon's whole typed response (see CdePagedResults.swift): the daemon and
// GMVibes keep whole records, and only this door cuts them to the harness's
// result cap. `narrowing` names the cursor the guard quotes back if a page
// still overflows.

// Tools surface as mcp__plugin_gmcc_cde__<tool>; a bare mcp__gmcc__ matcher
// never fires. The .mcp.json entry declares `alwaysLoad`, so the pen is in
// every session's surface without a ToolSearch.

// MARK: - Minimal JSON value

enum JSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    static func parse(_ data: Data) -> JSON? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return from(raw)
    }

    static func from(_ raw: Any) -> JSON {
        switch raw {
        case let value as String: return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        case let value as [Any]: return .array(value.map(from))
        case let value as [String: Any]: return .object(value.mapValues(from))
        default: return .null
        }
    }

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15 ? Int64(value) as Any : value
        case .string(let value): return value
        case .array(let value): return value.map(\.any)
        case .object(let value): return value.mapValues(\.any)
        }
    }

    subscript(key: String) -> JSON? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var int64Value: Int64? {
        guard case .number(let value) = self else { return nil }
        return Int64(value)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var stringArray: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap(\.stringValue)
    }
}

struct ToolError: Error {
    let message: String
}

// MARK: - Argument helpers

struct Args {
    let json: JSON

    func string(_ key: String) throws -> String {
        guard let value = json[key]?.stringValue, !value.isEmpty else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    func optString(_ key: String) -> String? {
        json[key]?.stringValue
    }

    func int64(_ key: String) throws -> Int64 {
        guard let value = json[key]?.int64Value else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    func optInt(_ key: String) -> Int? {
        json[key]?.intValue
    }

    func optBool(_ key: String) -> Bool? {
        json[key]?.boolValue
    }

    func optStrings(_ key: String) -> [String]? {
        json[key]?.stringArray
    }

    /// A REQUIRED boolean. `optBool` cannot serve here: false and absent are
    /// different answers for a field like `nullable`, where guessing one is a
    /// migration written from a value nobody supplied.
    func bool(_ key: String) throws -> Bool {
        guard let value = json[key]?.boolValue else {
            throw ToolError(message: "missing required argument '\(key)' (true or false)")
        }
        return value
    }

    /// The rating window shared by rpir_get_exploration and rpir_get_review, mirroring the
    /// CLI's RatingWindowOptions: mutually exclusive, 0-999, A:B inclusive.
    /// Without it a pen read of a ranked finding set is all-or-nothing, and
    /// the 80_000-byte result cap turns "all" into a truncation.
    func ratingWindow() throws -> (full: Bool, min: Int?, max: Int?) {
        let full = optBool("full") ?? false
        let maxRating = optInt("max_rating")
        let range = optString("rating_range")
        let picked = [full, maxRating != nil, range != nil].filter(\.self).count
        guard picked <= 1 else {
            throw ToolError(message: "full, max_rating, and rating_range are mutually exclusive")
        }
        if let range {
            let parts = range.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]),
                (0...999).contains(low), (0...999).contains(high), low <= high
            else {
                throw ToolError(message: "rating_range expects A:B with 0 <= A <= B <= 999, got '\(range)'")
            }
            return (false, low, high)
        }
        if let maxRating {
            guard (0...999).contains(maxRating) else {
                throw ToolError(message: "max_rating must be 0-999")
            }
            return (false, nil, maxRating)
        }
        return (full, nil, nil)
    }
}

// MARK: - Tool registry

struct Tool {
    let name: String
    let description: String
    /// {property name: (type, description, required)}
    let params: [(String, String, String, Bool)]
    /// What makes THIS tool's result smaller, in the tool's own argument
    /// names. nil is a positive statement: the result cannot outgrow the
    /// budget, or nothing about it is divisible. The guard quotes it back
    /// verbatim, so a caller is never told to narrow without being told with
    /// what.

    /// True when this tool exists in order to REFUSE. It carries no wire verb,
    /// so it legitimately has no `VerbSpec` and the roster check must not read
    /// that absence as an undeclared tool. FLAGGED rather than matched on a
    /// `_not_supported` suffix, because some refusals do not carry it and a
    /// check keyed on spelling would pass them silently.
    var refuses: Bool = false

    var narrowing: CdeNarrowing?
    let run: (Args, any GmVerbCaller) throws -> any Encodable

    var inputSchema: [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for (name, type, description, isRequired) in params {
            if type == "array" {
                properties[name] = ["type": "array", "items": ["type": "string"], "description": description]
            } else if type == "array<object>" {
                // An array whose ITEMS are objects. Without this the generator
                // emitted items:{type:string} for every array, so a tool whose
                // handler required objects — rpir_rank_reviews — advertised a schema
                // its own handler rejected, and could not be called as declared.
                properties[name] = ["type": "array", "items": ["type": "object"], "description": description]
            } else {
                properties[name] = ["type": type, "description": description]
            }
            if isRequired { required.append(name) }
        }
        return ["type": "object", "properties": properties, "required": required]
    }
}

/// Zero-uuid resolution shared by the bot tools: explicit prompt uuid →
/// ClientKey → the session resolved from CLAUDE_PROJECT_DIR/cwd.
private func botSelector(_ args: Args, _ client: any GmVerbCaller) -> (String?, String?, String?) {
    let promptUuid = args.optString("prompt_uuid")
    var session: String?
    if promptUuid == nil {
        session = try? ContextBuilder.resolveSessionUuid(client)
    }
    return (promptUuid, ClientKey.resolve(), session)
}

/// The record reads are prompt-keyed, and an agent is rarely told a uuid —
/// so an explicit `prompt_uuid` wins, and otherwise the workflow BOT_GET
/// already resolves answers it. Same zero-uuid contract the bot tools have.
private func resolvePromptUuid(_ args: Args, _ client: any GmVerbCaller) throws -> String {
    if let explicit = args.optString("prompt_uuid") { return explicit }
    let (prompt, key, session) = botSelector(args, client)
    return
        try client.botGet(
            BotGetRequest(
                promptUuid: prompt,
                clientKey: key,
                sessionUuid: session
            )
        )
        .workflow.promptUuid
}

/// Shared schema rows for the two rating-windowed reads.
private let ratingWindowParams: [(String, String, String, Bool)] = [
    ("full", "boolean", "Return every finding as a full row (no stub partition)", false),
    ("max_rating", "number", "Widen/narrow the full-row window to ratings 0...N", false),
    ("rating_range", "string", "Full-row window as A:B (inclusive rating bounds)", false),
]

private let promptSelectorParam: (String, String, String, Bool) =
    ("prompt_uuid", "string", "Explicit prompt uuid (omit to resolve YOUR workflow's prompt)", false)

/// The two rows every paged read carries. Paging is the cde layer's own
/// contract — see CdePagedResults.swift — so these never reach the daemon.
let pageParams: [(String, String, String, Bool)] = [
    ("cursor", "string", "page.next_cursor from the previous call (opaque) — omit for the first page", false),
    (
        "page_bytes", "number",
        "Page budget in bytes (default 30000, max 45000); every array and every long text is paged inside it",
        false
    ),
]

/// One pager per call, from the shared page arguments.
func makePager(_ args: Args) throws -> CdePager {
    let bytes = min(args.optInt("page_bytes") ?? CdeResultBudget.pageBytes, CdeResultBudget.maxBytes)
    do {
        return try CdePager(pageBytes: bytes, cursor: args.optString("cursor"))
    } catch let error as CdePagerError {
        throw ToolError(message: error.description)
    }
}

/// The narrowing every paged read declares: the cursor first, then whatever
/// selector reads one body.
func pagedNarrowing(_ tool: String, selectors: [String] = []) -> CdeNarrowing {
    let extra = selectors.isEmpty ? "" : "; \(selectors.joined(separator: " / ")) for one body"
    return CdeNarrowing(
        parameters: ["cursor", "page_bytes"] + selectors,
        retryWith: "\(tool) with cursor = page.next_cursor\(extra)"
    )
}

// `nonisolated(unsafe)` because a library target gives globals no implicit
// main-actor isolation and `[Tool]` cannot be `Sendable`: a `Tool` carries
// `run`/`degrade` closures over `Args` and `DaemonClient`. What makes it safe
// is that the array is built ONCE, never mutated, and read only from the single
// stdio read loop in `GmMcpServer.main()` — one thread, one connection, no
// concurrency in this process.
nonisolated(unsafe) let tools: [Tool] =
    [
        Tool(
            name: "rpir_next",
            description:
                "Current workflow phase + instructions + uuid bundle + gate blockers. Zero-uuid: resolves YOUR workflow.",
            params: [("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false)],
            run: { args, client in
                let (prompt, key, session) = botSelector(args, client)
                return try client.botNext(
                    BotNextRequest(
                        promptUuid: prompt,
                        clientKey: key,
                        sessionUuid: session
                    )
                )
            }
        ),
        Tool(
            name: "cde_load_prompt",
            description:
                "The workflow's prompt row — read the prompt without being told a uuid. The prompt's detail / backstory / goal arrive as text windows; loop on cursor until page.next_cursor is null.",
            params: [("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false)] + pageParams,
            narrowing: pagedNarrowing("cde_load_prompt"),
            run: { args, client in
                let (prompt, key, session) = botSelector(args, client)
                let workflow =
                    try client.botGet(
                        BotGetRequest(
                            promptUuid: prompt,
                            clientKey: key,
                            sessionUuid: session
                        )
                    )
                    .workflow
                let response = try client.getPrompt(PromptGetRequest(promptUuid: workflow.promptUuid))
                var pager = try makePager(args)
                return try CdePromptPage.build(response, pager: &pager)
            }
        ),
        Tool(
            name: "rpir_open_exploration",
            description:
                "Fetch-or-open an exploration summary (identity is the self-reported agent_type; 'synthesis' is the prompt-level seal row the clarifier opens once everything is ranked).",
            params: [
                ("agent_type", "string", "aggressive|conservative|pragmatic|alternative|general|synthesis", true),
                ("agent_id", "string", "Self-reported agent id for dedup/tracking", false),
                ("prompt_uuid", "string", "Explicit prompt uuid (escape hatch)", false),
            ],
            run: { args, client in
                let agentType = try args.string("agent_type")
                // No synthesis guard here, by design: any agent may open and
                // seal the synthesis row once everything is ranked. The merged
                // clarifier opens it (it never explored, so nothing else can have
                // opened one for it) and completes it in the same pass.
                let (prompt, key, session) = botSelector(args, client)
                let workflow =
                    try client.botGet(
                        BotGetRequest(
                            promptUuid: prompt,
                            clientKey: key,
                            sessionUuid: session
                        )
                    )
                    .workflow
                return try client.exploreOpen(
                    ExploreOpenRequest(
                        promptUuid: workflow.promptUuid,
                        agentType: agentType,
                        agentId: args.optString("agent_id")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_load_exploration_brief",
            description: "Fetch a briefing + staleness. Zero-uuid form: pass only step and YOUR briefing resolves.",
            params: [
                ("briefing_uuid", "string", "Explicit briefing uuid", false),
                ("prompt_uuid", "string", "Owner prompt uuid", false),
                ("step", "string", "Briefing step (initial)", false),
            ] + pageParams,
            narrowing: pagedNarrowing("rpir_load_exploration_brief"),
            run: { args, client in
                var session: String?
                if args.optString("briefing_uuid") == nil, args.optString("prompt_uuid") == nil {
                    session = try? ContextBuilder.resolveSessionUuid(client)
                }
                let response = try client.briefingGet(
                    BriefingGetRequest(
                        briefingUuid: args.optString("briefing_uuid"),
                        promptUuid: args.optString("prompt_uuid"),
                        sessionUuid: session,
                        step: args.optString("step") ?? "initial",
                        clientKey: ClientKey.resolve()
                    )
                )
                var pager = try makePager(args)
                return try CdeBriefingPage.build(response, pager: &pager)
            }
        ),
        Tool(
            name: "rpir_write_brief",
            description: """
                building → ready: write the briefing's ref set (opinion-free; the daemon \
                stamps staleness + kbite briefs). ALL THREE ref classes are REQUIRED of \
                you: a briefing records what it LOOKED FOR, not only what it found. Pass \
                [] for a class you searched and came up empty on — that is a real answer. \
                Omitting a class is refused, because absent is indistinguishable from \
                never having looked.
                """,
            params: [
                ("briefing_uuid", "string", "The briefing to complete", true),
                ("expected_version", "number", "The briefing version this write was based on", true),
                (
                    "dope_refs", "array",
                    "Dope dot-path CODES (never uuids). Pass [] if you searched and found none — omitting this is refused",
                    true
                ),
                (
                    "kbite_refs", "array",
                    "Kbite file uuids. Pass [] if you searched and found none — omitting this is refused", true
                ),
                (
                    "file_change_refs", "array",
                    "file_change uuids. Pass [] if there are none — omitting this is refused", true
                ),
                ("agent_id", "string", "Self-reported agent id", false),
            ],
            run: { args, client in
                try client.briefingComplete(
                    BriefingCompleteRequest(
                        briefingUuid: try args.string("briefing_uuid"),
                        expectedVersion: try args.int64("expected_version"),
                        dopeRefs: args.optStrings("dope_refs"),
                        kbiteRefs: args.optStrings("kbite_refs"),
                        fileChangeRefs: args.optStrings("file_change_refs"),
                        agentId: args.optString("agent_id")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_write_explorations",
            description:
                "Insert an exploration finding (self-rate 0=critical…999=ignore; unranked blocks the synthesis seal).",
            params: [
                ("summary_uuid", "string", "Your exploration summary uuid", true),
                (
                    "kind", "string",
                    "persistence_model|implementation_pattern|existing_functionality|scope_creep_risk|general_relevant_change|key_file|other",
                    true
                ),
                ("title", "string", "Finding title", true),
                ("body", "string", "Finding body", true),
                ("file_path", "string", "Repo-relative anchor path", false),
                ("agent_name", "string", "Your methodology persona", true),
                ("agent_id", "string", "Self-reported agent id", false),
                ("rating", "number", "0-999 self-rating", false),
            ],
            run: { args, client in
                guard let kind = ExplorationFindingKind(rawValue: try args.string("kind")) else {
                    throw ToolError(message: "unknown finding kind")
                }
                return try client.exploreFindingAdd(
                    ExploreFindingAddRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        kind: kind,
                        title: try args.string("title"),
                        body: try args.string("body"),
                        filePath: args.optString("file_path"),
                        agentName: try args.string("agent_name"),
                        agentId: args.optString("agent_id"),
                        rating: args.optInt("rating")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_complete_exploration",
            description:
                "Seal a summary with its overview — your own methodology row, or the synthesis row once every finding is ranked (it refuses while anything is unranked).",
            params: [
                ("summary_uuid", "string", "Your exploration summary uuid", true),
                ("expected_version", "number", "The summary version this write was based on", true),
                ("overview", "string", "Your overview narrative", true),
            ],
            run: { args, client in
                try client.exploreComplete(
                    ExploreCompleteRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        expectedVersion: try args.int64("expected_version"),
                        overview: try args.string("overview")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_write_reviews",
            description: "Insert a review finding (self-rate 0=critical…999=ignore).",
            params: [
                ("summary_uuid", "string", "The review summary uuid", true),
                (
                    "kind", "string", "correctness_bug|spec_deviation|regression_risk|security|simplification|other",
                    true
                ),
                ("title", "string", "Finding title", true),
                ("body", "string", "Finding body", true),
                ("file_path", "string", "Repo-relative path", false),
                ("line_start", "number", "First line", false),
                ("line_end", "number", "Last line", false),
                ("agent_name", "string", "Your methodology persona", true),
                ("agent_id", "string", "Self-reported agent id", false),
                ("rating", "number", "0-999 self-rating", false),
            ],
            run: { args, client in
                guard let kind = ReviewFindingKind(rawValue: try args.string("kind")) else {
                    throw ToolError(message: "unknown finding kind")
                }
                return try client.reviewFindingAdd(
                    ReviewFindingAddRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        kind: kind,
                        title: try args.string("title"),
                        body: try args.string("body"),
                        filePath: args.optString("file_path"),
                        lineStart: args.optInt("line_start"),
                        lineEnd: args.optInt("line_end"),
                        agentName: try args.string("agent_name"),
                        agentId: args.optString("agent_id"),
                        rating: args.optInt("rating")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_write_clarification_questions",
            description:
                "Insert a user-facing clarification question (+ordered options) while the summary is building.",
            params: [
                ("summary_uuid", "string", "The clarification summary uuid", true),
                ("question", "string", "The question text", true),
                ("options", "array", "Ordered pre-authored options", false),
                ("agent_name", "string", "Your persona", false),
                ("agent_id", "string", "Self-reported agent id", false),
            ],
            run: { args, client in
                try client.clarifyQuestionAdd(
                    ClarifyQuestionAddRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        question: try args.string("question"),
                        options: args.optStrings("options"),
                        agentName: args.optString("agent_name"),
                        agentId: args.optString("agent_id")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_write_clarification_notes",
            description: "Insert an internal clarification note (weight 0=critical…999; any summary state).",
            params: [
                ("summary_uuid", "string", "The clarification summary uuid", true),
                ("body", "string", "The note text", true),
                ("confused_entity_uuid", "string", "Soft ref to the confusing entity", false),
                ("confused_entity_type", "string", "exploration_finding|briefing|question|other", false),
                ("weight", "number", "0-999 importance (0=critical)", false),
                ("question_uuid", "string", "Attach to an answered question", false),
                ("agent_name", "string", "Your persona", false),
                ("agent_id", "string", "Self-reported agent id", false),
            ],
            run: { args, client in
                try client.clarifyNoteAdd(
                    ClarifyNoteAddRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        body: try args.string("body"),
                        confusedEntityUuid: args.optString("confused_entity_uuid"),
                        confusedEntityType: args.optString("confused_entity_type"),
                        weight: args.optInt("weight"),
                        questionUuid: args.optString("question_uuid"),
                        agentName: args.optString("agent_name"),
                        agentId: args.optString("agent_id")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_write_care_package",
            description:
                "Add one care package ref while building (dope code / kbite file / curated exploration COPY — never re-explore).",
            params: [
                ("package_uuid", "string", "The care package uuid", true),
                ("kind", "string", "dope|kbite|exploration", true),
                ("dope_code", "string", "Dope dot-path CODE (kind dope)", false),
                ("note", "string", "Curatorial note (kind dope)", false),
                ("kbite_file_uuid", "string", "Kbite file uuid (kind kbite)", false),
                ("title", "string", "Curated title (kind exploration)", false),
                ("body", "string", "Curated body (kind exploration)", false),
                ("file_path", "string", "Repo-relative anchor (kind exploration)", false),
                ("source_finding_uuid", "string", "Provenance ref (kind exploration)", false),
            ],
            run: { args, client in
                guard let kind = CarePackageRefKind(rawValue: try args.string("kind")) else {
                    throw ToolError(message: "kind must be dope|kbite|exploration")
                }
                return try client.carePackageRefAdd(
                    CarePackageRefAddRequest(
                        packageUuid: try args.string("package_uuid"),
                        kind: kind,
                        dopeCode: args.optString("dope_code"),
                        note: args.optString("note"),
                        kbiteFileUuid: args.optString("kbite_file_uuid"),
                        curatedTitle: args.optString("title"),
                        curatedBody: args.optString("body"),
                        filePath: args.optString("file_path"),
                        sourceFindingUuid: args.optString("source_finding_uuid")
                    )
                )
            }
        ),
        Tool(
            name: "rpir_open_architecture_option",
            description:
                "Write YOUR methodology's architecture Option row (the architect pen; one per agent_name). To REVISE an existing proposal, pass supersedes_option_uuid + expected_version together: the old row is kept as rejected history and a selected row hands its selection to the revision.",
            params: [
                ("summary_uuid", "string", "The architecture summary uuid", true),
                ("agent_name", "string", "Your methodology persona", true),
                ("agent_id", "string", "Self-reported agent id", false),
                ("body", "string", "Your full proposal (markdown)", true),
                (
                    "supersedes_option_uuid", "string",
                    "Option row this proposal REPLACES (revision door; requires expected_version)", false
                ),
                (
                    "expected_version", "number",
                    "The superseded row's version (revision door; requires supersedes_option_uuid)", false
                ),
            ],
            run: { args, client in
                try client.archOptionAdd(
                    ArchOptionAddRequest(
                        summaryUuid: try args.string("summary_uuid"),
                        agentName: try args.string("agent_name"),
                        agentId: args.optString("agent_id"),
                        body: try args.string("body"),
                        supersedesOptionUuid: args.optString("supersedes_option_uuid"),
                        expectedVersion: args.optInt("expected_version").map(Int64.init)
                    )
                )
            }
        ),
        Tool(
            name: "dope_search_session",
            description: "FTS over the session's dope tree (hits carry dot-paths).",
            params: [
                ("query", "string", "The search query", true),
                ("scope", "string", "prompt|session|project (default session)", false),
                ("session_uuid", "string", "Explicit session uuid", false),
                ("prompt_uuid", "string", "Prompt scope selector", false),
                ("limit", "number", "Max hits", false),
            ] + pageParams,
            narrowing: pagedNarrowing("dope_search_session"),
            run: { args, client in
                let scopeRaw = args.optString("scope") ?? "session"
                guard let scope = DopeSearchScope(rawValue: scopeRaw) else {
                    throw ToolError(message: "scope must be prompt|session|project")
                }
                var session = args.optString("session_uuid")
                if session == nil, scope != .project {
                    session = try? ContextBuilder.resolveSessionUuid(client)
                }
                let response = try client.dopeSearch(
                    DopeSearchRequest(
                        query: try args.string("query"),
                        scope: scope,
                        sessionUuid: session,
                        promptUuid: args.optString("prompt_uuid"),
                        limit: args.optInt("limit")
                    )
                )
                var pager = try makePager(args)
                return try CdeHitsPage.build(response.hits, pager: &pager)
            }
        ),
        Tool(
            name: "kbite_search",
            description: "bm25-ranked kbite file stubs with briefs — read briefs, then kbite_file_get.",
            params: [
                ("query", "string", "The search query", true),
                ("limit", "number", "Max hits", false),
            ] + pageParams,
            narrowing: pagedNarrowing("kbite_search"),
            run: { args, client in
                let response = try client.searchKbites(
                    KbiteSearchRequest(
                        query: try args.string("query"),
                        limit: args.optInt("limit")
                    )
                )
                var pager = try makePager(args)
                return try CdeHitsPage.build(response.hits, pager: &pager)
            }
        ),

        // ── Reading the record ───────────────────────────────────────────────
        //
        // The half of the pen that makes the other half usable: an agent reads
        // the prompt's own rows here instead of shelling out to `gm ... get`.
        // Every one is prompt-keyed and zero-uuid by default. rpir_rank_explorations rides
        // along because it is the same reader's next move — read the findings,
        // calibrate them in one batch.

        Tool(
            name: "rpir_get_exploration",
            description:
                "The prompt's exploration record: summaries, key files, findings inside the rating window, stubs outside it. Default window is ratings under 100; unranked findings are ALWAYS full rows (they are the work queue).",
            params: [
                promptSelectorParam,
                ("agent_type", "string", "Filter to one agent's summary (omit for all)", false),
                ("finding_uuid", "string", "Return exactly this finding in full and nothing else", false),
            ] + ratingWindowParams + pageParams,
            narrowing: pagedNarrowing("rpir_get_exploration", selectors: ["finding_uuid"]),
            run: { args, client in
                let window = try args.ratingWindow()
                let findingUuid = args.optString("finding_uuid")
                // A pinned finding needs its body whatever its rating, so the
                // window is widened to everything for that one read.
                let response = try client.exploreGet(
                    ExploreGetRequest(
                        promptUuid: try resolvePromptUuid(args, client),
                        agentType: args.optString("agent_type"),
                        full: findingUuid != nil ? true : window.full,
                        ratingMin: findingUuid != nil ? nil : window.min,
                        ratingMax: findingUuid != nil ? nil : window.max
                    )
                )
                var pager = try makePager(args)
                return try CdeExplorationPage.build(response, pager: &pager, findingUuid: findingUuid)
            }
        ),
        Tool(
            name: "rpir_rank_explorations",
            description:
                "Batch-rank exploration findings PROMPT-wide: one atomic calibrated batch across every summary. One bad pair rejects the whole batch; 0 unranked is what lets the synthesis seal pass.",
            params: [
                ("ratings", "array", "\"<finding-uuid>:<0-999>\" pairs (0=critical, 999=tombstone)", true),
                promptSelectorParam,
            ],
            run: { args, client in
                let raw = args.optStrings("ratings") ?? []
                guard !raw.isEmpty else {
                    throw ToolError(message: "pass at least one rating as \"<finding-uuid>:<0-999>\"")
                }
                let pairs: [FindingRating] = try raw.map { pair in
                    let parts = pair.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, let rating = Int(parts[1]), (0...999).contains(rating) else {
                        throw ToolError(message: "rating '\(pair)' is not <finding-uuid>:<0-999>")
                    }
                    return FindingRating(findingUuid: String(parts[0]), rating: rating)
                }
                return try client.exploreRank(
                    ExploreRankRequest(
                        promptUuid: try resolvePromptUuid(args, client),
                        ratings: pairs
                    )
                )
            }
        ),
        Tool(
            name: "rpir_get_review",
            description:
                "The prompt's review record: summary, findings inside the rating window, stubs outside it. Same window semantics as rpir_get_exploration.",
            params: [
                promptSelectorParam,
                ("finding_uuid", "string", "Return exactly this finding in full and nothing else", false),
            ] + ratingWindowParams + pageParams,
            narrowing: pagedNarrowing("rpir_get_review", selectors: ["finding_uuid"]),
            run: { args, client in
                let window = try args.ratingWindow()
                let findingUuid = args.optString("finding_uuid")
                let response = try client.reviewGet(
                    ReviewGetRequest(
                        promptUuid: try resolvePromptUuid(args, client),
                        full: findingUuid != nil ? true : window.full,
                        ratingMin: findingUuid != nil ? nil : window.min,
                        ratingMax: findingUuid != nil ? nil : window.max
                    )
                )
                var pager = try makePager(args)
                return try CdeReviewPage.build(response, pager: &pager, findingUuid: findingUuid)
            }
        ),
        Tool(
            name: "rpir_get_clarification",
            description:
                "The prompt's clarification record: summary, questions (+answers), notes, and the care package with its dope staleness when one exists.",
            params: [
                promptSelectorParam,
                (
                    "note_weight_max", "number",
                    "Weight window over the notes: at or below stays a full row, above drops to note_stubs (unweighted notes are always full)",
                    false
                ),
                ("note_uuid", "string", "Return exactly this note in full and nothing else", false),
            ] + pageParams,
            // The care package is ALWAYS a counts-only stub here — it has its
            // own door. Questions are never windowed: a question plus its
            // pre-authored options is bounded by what a human can answer.
            narrowing: pagedNarrowing("rpir_get_clarification", selectors: ["note_uuid"]),
            run: { args, client in
                let noteUuid = args.optString("note_uuid")
                let response = try client.clarifyGet(
                    ClarifyGetRequest(
                        promptUuid: try resolvePromptUuid(args, client),
                        includeCarePackage: false,
                        noteWeightMax: noteUuid != nil ? nil : args.optInt("note_weight_max")
                    )
                )
                var pager = try makePager(args)
                return try CdeClarificationPage.build(response, pager: &pager, noteUuid: noteUuid)
            }
        ),
        Tool(
            name: "rpir_get_care_package",
            description:
                "The prompt's sealed care package on its own: the clarified intent (as text windows), the dope and kbite refs, and the curated exploration copies as a stub roster (title, path, excerpt, size). Pass ref_uuid to read one curated body in full; loop on cursor until page.next_cursor is null.",
            params: [
                promptSelectorParam,
                (
                    "ref_uuid", "string",
                    "Return exactly this exploration ref's curated body in full, the rest as stubs",
                    false
                ),
            ] + pageParams,
            narrowing: pagedNarrowing("rpir_get_care_package", selectors: ["ref_uuid"]),
            run: { args, client in
                let response = try client.carePackageGet(
                    CarePackageGetRequest(promptUuid: try resolvePromptUuid(args, client))
                )
                var pager = try makePager(args)
                return try CdeCarePackagePage.build(
                    response.package,
                    pager: &pager,
                    refUuid: args.optString("ref_uuid")
                )
            }
        ),
        Tool(
            name: "rpir_get_architecture",
            description:
                "The approved architecture with its implementation state: persistence changes (whole) before general changes (stubs with a leading excerpt), each joined to its recorded file changes, plus the touched-but-unplanned set. This is the implementation spec. The summary body, the decision rationale, one option body (option_uuid) or one change_code (change_uuid) arrive as text windows; loop on cursor until page.next_cursor is null.",
            params: [
                promptSelectorParam,
                ("option_uuid", "string", "Return exactly this option's body in full", false),
                ("change_uuid", "string", "Return exactly this general change's change_code in full", false),
                ("limit", "number", "Cap the general change stub roster to its first N rows", false),
            ] + pageParams,
            // THE CDE LAYER IS WHAT CUTS, NOT THE DAEMON. The daemon is read
            // unnarrowed — every body in hand — and CdeArchitecturePage decides
            // what becomes a stub or a window, so GMVibes and this door read
            // one verb with one meaning.
            narrowing: pagedNarrowing("rpir_get_architecture", selectors: ["option_uuid", "change_uuid"]),
            run: { args, client in
                let response = try client.archGet(
                    ArchGetRequest(promptUuid: try resolvePromptUuid(args, client))
                )
                var pager = try makePager(args)
                return try CdeArchitecturePage.build(
                    response,
                    pager: &pager,
                    optionUuid: args.optString("option_uuid"),
                    changeUuid: args.optString("change_uuid"),
                    limit: args.optInt("limit")
                )
            }
        ),
        Tool(
            name: "cde_search_file_changes",
            description:
                "Recorded file changes for the prompt (or an explicit session/path). What the machine believes you have touched — read it to check your own capture.",
            params: [
                promptSelectorParam,
                ("session_uuid", "string", "List a whole session instead of one prompt", false),
                ("path", "string", "Filter to one repo-relative path", false),
                ("limit", "number", "Max rows to consider, newest first (default 2000)", false),
            ] + pageParams,
            narrowing: pagedNarrowing("cde_search_file_changes"),
            run: { args, client in
                let session = args.optString("session_uuid")
                // An explicit session read is session-scoped; otherwise the
                // prompt is resolved the same way every other record read is.
                let prompt = session == nil ? try resolvePromptUuid(args, client) : args.optString("prompt_uuid")
                // The whole list is fetched and paged HERE, so the default
                // limit is the record, not the page: a row is ~1.2 KB and a
                // 2,000-row prompt is a ~2.4 MB local read per page.
                let response = try client.listFileChanges(
                    FileChangeListRequest(
                        sessionUuid: session,
                        promptUuid: prompt,
                        relativePath: args.optString("path"),
                        limit: args.optInt("limit") ?? 2_000
                    )
                )
                var pager = try makePager(args)
                return try CdeFileChangePage.build(response, pager: &pager)
            }
        ),
    ] + makeFastPathTools() + makePrimaryDoorTools() + makePhaseDoorTools() + makeBridgeDoorTools() + makeRecallDoors()
// MARK: - Upfront loading

// EVERY PEN TOOL LOADS UPFRONT, declared once as `"alwaysLoad": true` on this
// server's `.mcp.json` entry rather than per-tool here. Session startup then
// waits on a socket connect, capped at the 5-second connect timeout.
//
// Deferring most of the surface costs more than the context it saves: an agent
// holding a correct frontmatter tool list finds every deferred pen call failing
// until it thinks to run a ToolSearch by exact name, which from inside the
// agent is indistinguishable from the server not being registered at all.

// MARK: - The initialize instructions, generated from the registry

/// The `instructions` field of `initialize` is generated from VerbRegistry by
/// `CdeSheet` in GmDaemonSdk, so it cannot drift from the roster. The
/// SubagentStart hook hands spawned agents the same generated text: two
/// generators over one registry drift apart.

/// Startup diagnostics on stderr, since stdout belongs to the protocol. The
/// roster and the registry must be the same set, so a mismatched binary says so
/// in the MCP log instead of silently serving a surface nobody declared.
@MainActor func validateRosterAgainstRegistry() {
    let lines = GmCdeTools.rosterProblems()
    guard !lines.isEmpty else { return }
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

extension GmCdeTools {
    /// The roster check, as DATA rather than as a side effect on stderr, so a
    /// test can assert it is empty. A mismatch printed only at `gm_mcp` startup
    /// is found by whoever reads an MCP log, which is nobody.
    ///
    /// BOTH DIRECTIONS MATTER. An ORPHAN — served, undeclared — is a tool with
    /// no role decision behind it. A MISSING — declared, unserved — is a
    /// capability the pen advertises and cannot deliver, and a one-directional
    /// gate passes that cleanly.
    @MainActor public static func rosterProblems() -> [String] {
        // Refusals are excluded from the ORPHAN direction only. They have no
        // verb by construction, so "served with no VerbSpec" is their normal
        // state — but they must still be DECLARED by the bridge, which the
        // missing direction below and the generator's own check both enforce.
        let served = Set(tools.filter { !$0.refuses }.map(\.name))
        let declared = VerbRegistry.cdeToolNames
        var lines: [String] = []
        for orphan in served.subtracting(declared).sorted() {
            lines.append("serves '\(orphan)' with no VerbSpec — the door has made no role decision about it")
        }
        for missing in declared.subtracting(served).sorted() {
            lines.append("VerbRegistry declares pen tool '\(missing)' but this binary does not serve it")
        }
        let instructionBytes = CdeSheet.instructions.utf8.count
        if instructionBytes > 2_048 {
            lines.append("initialize instructions are \(instructionBytes) bytes (budget 2048)")
        }
        return lines
    }
}

// MARK: - Rendering (byte-budgeted)

/// Tool results are the wire response as sorted-key JSON, the form agents
/// parse. THIS NEVER CLIPS: cutting the JSON at a byte count lands the cut
/// inside whichever key sorts there and eats the rest silently. Every read is
/// paged by `CdePager` before it gets here, so the guard's withhold note is a
/// last resort. The threshold and the envelope shape live in
/// `CdeResultBudget` in GmDaemonSdk so the test package can exercise them.
func renderResult(tool: Tool, value: any Encodable) throws -> String {
    try CdeResultBudget.render(
        tool: tool.name,
        narrowing: tool.narrowing,
        value: value,
        isWrite: VerbRegistry.writeCdeTools.contains(tool.name)
    )
}

// MARK: - JSON-RPC loop

func writeMessage(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func respond(id: Any, result: [String: Any]) {
    writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
}

func respondError(id: Any, code: Int, message: String) {
    writeMessage(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

// A LIBRARY target, so the multi-call `gm_kernel` Mach-O can carry the MCP
// personality and `gm_mcp` is a shim over `GmMcpServer.main()`. Top-level code
// is legal solely in an executable target's `main.swift`, which is why these
// statements are a function body.

public enum GmMcpServer {

    /// The `gm_mcp` personality: a JSON-RPC 2.0 server on newline-delimited
    /// stdio, relaying every `tools/call` to the daemon over the unix socket.
    /// It stays a CHILD OF THE HARNESS. Three things depend on that and cannot
    /// be supplied from inside the kernel process: the harness owns this stdin;
    /// `ClientKey.resolve()` walks process ancestry for the activation-claim
    /// key; and the chdir below gives one cwd per session. `@MainActor` matches
    /// the implicit isolation of top-level code, which is what lets
    /// `validateRosterAgainstRegistry()` be called plainly.
    @MainActor
    public static func main() {
        // Servers spawn with the project dir as cwd; CLAUDE_PROJECT_DIR is the
        // stable root — chdir so GitContext.detect() resolves the right repo even
        // if the harness launched us elsewhere.
        if let projectDir = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"],
            !projectDir.isEmpty
        {
            FileManager.default.changeCurrentDirectoryPath(projectDir)
        }

        // ONE CLIENT, ONE SOCKET. Every pen tool is served by the same connection —
        // there is no caller role on the wire and nothing for the daemon to decide
        // about who is on the other end.
        let client = DaemonClient()
        defer { client.close() }

        validateRosterAgainstRegistry()

        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let message = JSON.parse(Data(line.utf8)) else { continue }
            let method = message["method"]?.stringValue ?? ""
            let id = message["id"]?.any
            // Notifications (no id) are consumed silently.
            guard let id, !(id is NSNull) else { continue }

            switch method {
            case "initialize":
                // Pin the protocol revision this server actually implements — never
                // echo the client's (claiming support for future revisions).
                respond(
                    id: id,
                    result: [
                        "protocolVersion": "2024-11-05",
                        "capabilities": ["tools": [String: Any]()],
                        "serverInfo": [
                            "name": "gmcc-cde",
                            "version": "\(GmWireProtocol.version)",
                        ],
                        // Loaded at session start, ahead of any tool schema — the only
                        // place the pen gets to state its own contract.
                        "instructions": CdeSheet.instructions,
                    ]
                )
            case "ping":
                respond(id: id, result: [:])
            case "tools/list":
                respond(
                    id: id,
                    result: [
                        "tools": tools.map { tool in
                            var entry: [String: Any] = [
                                "name": tool.name,
                                "description": tool.description,
                                "inputSchema": tool.inputSchema,
                            ]
                            return entry
                        }
                    ]
                )
            case "tools/call":
                let name = message["params"]?["name"]?.stringValue ?? ""
                let arguments = Args(json: message["params"]?["arguments"] ?? .object([:]))
                guard let tool = tools.first(where: { $0.name == name }) else {
                    respondError(id: id, code: -32602, message: "unknown tool '\(name)'")
                    continue
                }
                do {
                    let result = try tool.run(arguments, client)
                    respond(
                        id: id,
                        result: [
                            "content": [
                                [
                                    "type": "text",
                                    "text": try renderResult(tool: tool, value: result),
                                ]
                            ],
                            "isError": false,
                        ]
                    )
                } catch {
                    let text: String
                    switch error {
                    case let toolError as ToolError:
                        text = toolError.message
                    case let clientError as DaemonClientError:
                        text = "\(clientError)"
                    default:
                        text = "\(error)"
                    }
                    // Tool-level failures ride the result envelope (isError), never
                    // a protocol error — the agent should read and react to them.
                    respond(
                        id: id,
                        result: [
                            "content": [["type": "text", "text": "ERROR: \(text)"]],
                            "isError": true,
                        ]
                    )
                }
            default:
                respondError(id: id, code: -32601, message: "method '\(method)' not supported")
            }
        }
    }
}
