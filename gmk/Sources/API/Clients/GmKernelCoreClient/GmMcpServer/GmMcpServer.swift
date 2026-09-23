import Foundation

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

// Tools surface under the harness's plugin namespacing, spelled once as
// `CdeToolSpec.qualifiedName`; a bare mcp__gmcc__ matcher never fires. The
// entry tools carry their own `_meta` pin, so they are in every session's
// surface without a ToolSearch.

// MARK: - Minimal JSON value

enum JSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    /// Parses JSON data into a `JSON` value.
    ///
    /// - Parameter data: The raw JSON data to parse.
    /// - Returns: A JSON value, or nil if the data is not valid JSON.
    static func parse(_ data: Data) -> JSON? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return from(raw)
    }

    /// Converts an untyped value into a `JSON` value.
    ///
    /// - Parameter raw: An untyped value from JSON deserialization.
    /// - Returns: The equivalent JSON value.
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

    /// Accesses a value in a JSON object by key.
    ///
    /// - Parameter key: The object key.
    /// - Returns: The value at the key, or nil if this is not an object.
    subscript(key: String) -> JSON? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    /// Extracts a string value from a JSON value.
    ///
    /// - Returns: The string, or nil if this is not a string.
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// Extracts an integer value from a JSON number.
    ///
    /// - Returns: The integer, or nil if this is not a number.
    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    /// Extracts a 64-bit integer value from a JSON number.
    ///
    /// - Returns: The 64-bit integer, or nil if this is not a number.
    var int64Value: Int64? {
        guard case .number(let value) = self else { return nil }
        return Int64(value)
    }

    /// Extracts a boolean value from a JSON boolean.
    ///
    /// - Returns: The boolean, or nil if this is not a boolean.
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// Extracts an array of strings from a JSON array.
    ///
    /// - Returns: An array of strings, or nil if this is not an array.
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

    /// Extracts a required string argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The string value.
    /// - Throws: `ToolError` if the argument is missing or empty.
    func string(_ key: String) throws -> String {
        guard let value = json[key]?.stringValue, !value.isEmpty else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    /// Extracts an optional string argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The string value, or nil if absent.
    func optString(_ key: String) -> String? {
        json[key]?.stringValue
    }

    /// Extracts a required 64-bit integer argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The 64-bit integer value.
    /// - Throws: `ToolError` if the argument is missing.
    func int64(_ key: String) throws -> Int64 {
        guard let value = json[key]?.int64Value else {
            throw ToolError(message: "missing required argument '\(key)'")
        }
        return value
    }

    /// Extracts an optional integer argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The integer value, or nil if absent.
    func optInt(_ key: String) -> Int? {
        json[key]?.intValue
    }

    /// Extracts an optional boolean argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The boolean value, or nil if absent.
    func optBool(_ key: String) -> Bool? {
        json[key]?.boolValue
    }

    /// Extracts an optional string array argument.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: An array of strings, or nil if absent.
    func optStrings(_ key: String) -> [String]? {
        json[key]?.stringArray
    }

    /// Extracts a required boolean argument; false and absent are distinct.
    ///
    /// `optBool` cannot serve here; false and absent are different answers
    /// for a field like `nullable`, where guessing one is a migration written
    /// from a value nobody supplied.
    ///
    /// - Parameter key: The argument name.
    /// - Returns: The boolean value.
    /// - Throws: `ToolError` if the argument is missing.
    func bool(_ key: String) throws -> Bool {
        guard let value = json[key]?.boolValue else {
            throw ToolError(message: "missing required argument '\(key)' (true or false)")
        }
        return value
    }

    /// Parses the rating window options for exploration and review results.
    ///
    /// The rating window is shared by rpir_get_exploration and rpir_get_review,
    /// mirroring the CLI's RatingWindowOptions: mutually exclusive, 0-999,
    /// A:B inclusive. Without it a pen read of a ranked finding set is
    /// all-or-nothing, and the 80_000-byte result cap turns "all" into a
    /// truncation.
    ///
    /// - Returns: A tuple with the full flag and optional min/max bounds.
    /// - Throws: `ToolError` if the options are invalid or mutually violated.
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

// MARK: - CdeTool registry

struct CdeTool {
    let name: String
    let description: String
    /// {property name: (type, description, required)}.
    let params: [(String, String, String, Bool)]
    /// What makes THIS tool's result smaller, in the tool's own argument
    /// names. nil is a positive statement: the result cannot outgrow the
    /// budget, or nothing about it is divisible. The guard quotes it back
    /// verbatim, so a caller is never told to narrow without being told with
    /// what.

    /// True when this tool exists in order to REFUSE.
    ///
    /// It carries no wire verb, so it legitimately has no `VerbSpec` and the
    /// roster check must not read that absence as an undeclared tool. FLAGGED
    /// rather than matched on a `_not_supported` suffix, because some refusals
    /// do not carry it and a check keyed on spelling would pass them silently.
    var refuses: Bool = false

    /// Pinned into every session's listing through `_meta`, rather than left to
    /// a ToolSearch the agent has to think to run.
    var alwaysLoad: Bool = false

    var narrowing: CdeNarrowing?
    let run: (Args, any GmVerbCaller) throws -> any Encodable

    /// The roster row this tool is a projection of. nil for a name that is
    /// still served under the one-tool-per-verb shape.
    var spec: CdeToolSpec?

    /// Resolves the operation the caller selected for this tool.
    ///
    /// The selector is whichever schema property carries the op names — `op`
    /// for every tool but `cde_rpir_search`, which keys on `scope`.
    ///
    /// - Parameter args: The tool arguments.
    /// - Returns: The operation name, or nil if the tool has no ops.
    func resolvedOp(_ args: Args) -> String? {
        guard let spec, !spec.ops.isEmpty else { return nil }
        if let picked = args.optString(Self.selectorKey(spec)) { return picked }
        return spec.ops.count == 1 ? spec.ops[0].op : nil
    }

    /// Looks up the spec for an operation by name.
    ///
    /// - Parameter op: The operation name.
    /// - Returns: The operation spec, or nil if not found.
    func opSpec(_ op: String?) -> CdeOpSpec? {
        guard let op, let spec else { return nil }
        return spec.ops.first { $0.op == op }
    }

    /// Returns the schema property that carries operation names for a tool.
    ///
    /// - Parameter spec: The tool specification.
    /// - Returns: The property name (e.g., "op" or "scope").
    static func selectorKey(_ spec: CdeToolSpec) -> String {
        let ops = Set(spec.ops.map(\.op))
        guard case .object(let schema) = spec.schema,
            case .object(let properties)? = schema["properties"]
        else { return "op" }
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            guard case .object(let property) = value,
                case .array(let cases)? = property["enum"]
            else { continue }
            if Set(cases.compactMap { if case .string(let name) = $0 { return name } else { return nil } }) == ops {
                return key
            }
        }
        return "op"
    }

    var inputSchema: [String: Any] {
        // A roster-backed tool serves the schema it was generated with,
        // verbatim: anything rebuilt here is a second description of it.
        if let spec, case .object = spec.schema {
            return cdeJsonObject(spec.schema) as? [String: Any] ?? ["type": "object"]
        }
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

/// Converts a `GmJsonValue` to a JSON-serializable untyped tree.
///
/// The roster's schema crosses into the protocol's untyped world exactly here.
///
/// - Parameter value: The JSON value to convert.
/// - Returns: An untyped JSON-serializable value.
func cdeJsonObject(_ value: GmJsonValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let flag): return flag
    case .int(let number): return number
    case .double(let number): return number
    case .string(let text): return text
    case .array(let items): return items.map(cdeJsonObject)
    case .object(let fields): return fields.mapValues(cdeJsonObject)
    }
}

/// A tool as a projection of its roster row: the name, the description and the
/// served schema come from the roster, and the bodies from the dispatch table.
///
/// An EXTENSION so the memberwise init survives for the names still served one
/// tool per verb.
extension CdeTool {

    /// Creates a tool from a roster specification and dispatch table.
    ///
    /// - Parameters:
    ///   - spec: The tool specification from the roster.
    ///   - dispatch: The operation dispatch table.
    init(spec: CdeToolSpec, dispatch: [String: CdeArm]) {
        let ops = spec.ops.map(\.op)
        let selector = CdeTool.selectorKey(spec)
        self.init(
            name: spec.name,
            description: spec.description,
            params: [],
            refuses: spec.refuses,
            alwaysLoad: spec.alwaysLoad,
            narrowing: nil,
            run: { args, client in
                guard !spec.refuses else {
                    throw ToolError(message: spec.description)
                }
                guard let op = args.optString(selector) ?? (ops.count == 1 ? ops.first : nil) else {
                    throw ToolError(
                        message: "\(spec.name) needs \(selector): \(ops.joined(separator: " | "))"
                    )
                }
                guard ops.contains(op) else {
                    throw ToolError(
                        message: "\(spec.name) has no \(selector) '\(op)': \(ops.joined(separator: " | "))"
                    )
                }
                guard let arm = dispatch[op] else {
                    throw ToolError(
                        message: "\(spec.name) \(selector)=\(op) is declared but not answered by this binary"
                    )
                }
                return try arm(args, client)
            },
            spec: spec
        )
    }
}

/// Resolves prompt uuid, client key, and session for bot tools.
///
/// Shared by the bot tools: explicit prompt uuid → ClientKey → the session
/// resolved from CLAUDE_PROJECT_DIR/cwd.
///
/// - Parameters:
///   - args: The tool arguments.
///   - client: The verb caller.
/// - Returns: A tuple of (prompt uuid, client key, session uuid).
private func botSelector(_ args: Args, _ client: any GmVerbCaller) -> (String?, String?, String?) {
    let promptUuid = args.optString("prompt_uuid")
    var session: String?
    if promptUuid == nil {
        session = try? ContextBuilder.resolveSessionUuid(client)
    }
    return (promptUuid, ClientKey.resolve(), session)
}

/// Resolves a prompt uuid for record reads when one is not explicit.
///
/// The record reads are prompt-keyed, and an agent is rarely told a uuid —
/// so an explicit `prompt_uuid` wins, and otherwise the workflow BOT_GET
/// already resolves answers it. Same zero-uuid contract the bot tools have.
///
/// - Parameters:
///   - args: The tool arguments.
///   - client: The verb caller.
/// - Returns: The resolved prompt uuid.
/// - Throws: `ToolError` if resolution fails.
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

/// Creates a pager from the shared page arguments.
///
/// - Parameter args: The tool arguments.
/// - Returns: A configured pager.
/// - Throws: `ToolError` if pager initialization fails.
func makePager(_ args: Args) throws -> CdePager {
    let bytes = min(args.optInt("page_bytes") ?? CdeResultBudget.pageBytes, CdeResultBudget.maxBytes)
    do {
        return try CdePager(pageBytes: bytes, cursor: args.optString("cursor"))
    } catch let error as CdePagerError {
        throw ToolError(message: error.description)
    }
}

/// Creates narrowing options for paged reads: cursor and optional selectors.
///
/// The narrowing every paged read declares: the cursor first, then whatever
/// selector reads one body.
///
/// - Parameters:
///   - tool: The tool name.
///   - selectors: Optional selector names for single-body reads.
/// - Returns: The narrowing specification.
func pagedNarrowing(_ tool: String, selectors: [String] = []) -> CdeNarrowing {
    let extra = selectors.isEmpty ? "" : "; \(selectors.joined(separator: " / ")) for one body"
    return CdeNarrowing(
        parameters: ["cursor", "page_bytes"] + selectors,
        retryWith: "\(tool) with cursor = page.next_cursor\(extra)"
    )
}

// MARK: - The dispatch table

/// One op's body: the same `(Args, caller) -> Encodable` shape the served tools
/// have always had.
typealias CdeArm = (Args, any GmVerbCaller) throws -> any Encodable

/// tool → op → body.
///
/// Each door file contributes its own, and `CdeDispatch` merges them.
typealias CdeArms = [String: [String: CdeArm]]

/// This file's own contribution: the record reads and writes that were served
/// under one name per verb.
nonisolated(unsafe) let gmMcpServerArms: CdeArms = [
    "cde_prompt": promptArms(),
    "cde_dope": dopeArms(),
    "cde_kbite": kbiteArms(),
    "cde_rpir_briefing": briefingArms(),
    "cde_rpir_explore": exploreArms(),
    "cde_rpir_clarify": clarifyArms(),
    "cde_rpir_architecture": architectureArms(),
    "cde_rpir_review": reviewArms(),
]

/// Returns the dispatch table for prompt-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func promptArms() -> [String: CdeArm] {
    var prompt: [String: CdeArm] = [:]
    prompt["load"] = { args, client in
        let (promptUuid, key, session) = botSelector(args, client)
        let workflow =
            try client.botGet(
                BotGetRequest(
                    promptUuid: promptUuid,
                    clientKey: key,
                    sessionUuid: session
                )
            )
            .workflow
        let response = try client.getPrompt(PromptGetRequest(promptUuid: workflow.promptUuid))
        var pager = try makePager(args)
        return try CdePromptPage.build(response, pager: &pager)
    }
    prompt["list"] = { args, client in
        let session = try args.optString("session_uuid") ?? ContextBuilder.resolveSessionUuid(client)
        let response = try client.listPrompts(PromptListRequest(sessionUuid: session))
        guard let selector = args.optString("selector") else { return response }
        // AMBIGUITY IS A RESULT. The resolver returns every candidate rather
        // than picking one, and the caller is handed the same set.
        switch PromptResolver.resolve(selector, in: response.prompts) {
        case .matched(let stub, _): return PromptListResponse(prompts: [stub])
        case .ambiguous(let stubs): return PromptListResponse(prompts: stubs)
        case .notFound: return PromptListResponse(prompts: [])
        }
    }
    prompt["draft"] = { args, client in
        try client.updatePromptContent(
            PromptUpdateContentRequest(
                promptUuid: try args.string("prompt_uuid"),
                expectedVersion: try args.int64("expected_version"),
                backstory: args.optString("backstory"),
                goal: args.optString("goal"),
                detail: args.optString("detail")
            )
        )
    }
    prompt["file_changes"] = { args, client in
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
    return prompt
}

/// Returns the dispatch table for dope-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func dopeArms() -> [String: CdeArm] {
    var dope: [String: CdeArm] = [:]
    dope["search_session"] = { args, client in
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
    return dope
}

/// Returns the dispatch table for kbite-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func kbiteArms() -> [String: CdeArm] {
    var kbite: [String: CdeArm] = [:]
    kbite["search"] = { args, client in
        let response = try client.searchKbites(
            KbiteSearchRequest(
                query: try args.string("query"),
                limit: args.optInt("limit")
            )
        )
        var pager = try makePager(args)
        return try CdeHitsPage.build(response.hits, pager: &pager)
    }
    return kbite
}

/// Returns the dispatch table for briefing-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func briefingArms() -> [String: CdeArm] {
    var briefing: [String: CdeArm] = [:]
    briefing["load"] = { args, client in
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
    briefing["write"] = { args, client in
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
    return briefing
}

/// Returns the dispatch table for exploration-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func exploreArms() -> [String: CdeArm] {
    var explore: [String: CdeArm] = [:]
    explore["open"] = { args, client in
        let agentType = try args.string("agent_type")
        // No synthesis guard here, by design: any agent may open and
        // seal the synthesis row once everything is ranked. The merged
        // clarifier opens it (it never explored, so nothing else can have
        // opened one for it) and completes it in the same pass.
        let (promptUuid, key, session) = botSelector(args, client)
        let workflow =
            try client.botGet(
                BotGetRequest(
                    promptUuid: promptUuid,
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
    explore["write"] = { args, client in
        guard let kind = ExplorationFindingKind(rawValue: try args.string("kind")) else {
            throw ToolError(message: "unknown finding kind")
        }
        return try client.exploreFindingAdd(
            ExploreFindingAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                kind: kind,
                title: try args.string("title"),
                body: try args.string("body"),
                agentName: try args.string("agent_name"),
                filePath: args.optString("file_path"),
                agentId: args.optString("agent_id"),
                rating: args.optInt("rating")
            )
        )
    }
    explore["rank"] = { args, client in
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
    explore["complete"] = { args, client in
        try client.exploreComplete(
            ExploreCompleteRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version"),
                overview: try args.string("overview")
            )
        )
    }
    explore["get"] = { args, client in
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
    return explore
}

/// Returns the dispatch table for clarification-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func clarifyArms() -> [String: CdeArm] {
    var clarify: [String: CdeArm] = [:]
    clarify["write_questions"] = { args, client in
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
    clarify["write_notes"] = { args, client in
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
    clarify["get"] = { args, client in
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
    clarify["package_write"] = { args, client in
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
    clarify["package_get"] = { args, client in
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
    return clarify
}

/// Returns the dispatch table for architecture-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func architectureArms() -> [String: CdeArm] {
    var architecture: [String: CdeArm] = [:]
    architecture["open_option"] = { args, client in
        try client.archOptionAdd(
            ArchOptionAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                agentName: try args.string("agent_name"),
                body: try args.string("body"),
                agentId: args.optString("agent_id"),
                supersedesOptionUuid: args.optString("supersedes_option_uuid"),
                expectedVersion: args.optInt("expected_version").map(Int64.init)
            )
        )
    }
    architecture["get"] = { args, client in
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
    return architecture
}

/// Returns the dispatch table for review-related operations.
///
/// - Returns: A map of operation names to their implementations.
private func reviewArms() -> [String: CdeArm] {
    var review: [String: CdeArm] = [:]
    review["write"] = { args, client in
        guard let kind = ReviewFindingKind(rawValue: try args.string("kind")) else {
            throw ToolError(message: "unknown finding kind")
        }
        return try client.reviewFindingAdd(
            ReviewFindingAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                kind: kind,
                title: try args.string("title"),
                body: try args.string("body"),
                agentName: try args.string("agent_name"),
                filePath: args.optString("file_path"),
                lineStart: args.optInt("line_start"),
                lineEnd: args.optInt("line_end"),
                agentId: args.optString("agent_id"),
                rating: args.optInt("rating")
            )
        )
    }
    review["get"] = { args, client in
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
    return review
}

/// THE ONE TABLE OF BODIES.
///
/// Every door file hands its arms in here; a tool is served with the ops this
/// table holds for it, and the startup check reports any op the roster declares
/// that nothing answers.
enum CdeDispatch {

    /// Add one contribution per door file as it converts.
    nonisolated(unsafe) static let table: CdeArms = merge([
        gmMcpServerArms, recallDoorArms, phaseDoorArms, primaryDoorArms, fastPathArms,
    ])

    /// Merges multiple dispatch tables into a single table.
    ///
    /// - Parameter contributions: The dispatch tables to merge.
    /// - Returns: The merged dispatch table.
    private static func merge(_ contributions: [CdeArms]) -> CdeArms {
        var table: CdeArms = [:]
        for contribution in contributions {
            for (tool, arms) in contribution {
                table[tool, default: [:]].merge(arms) { _, latest in latest }
            }
        }
        return table
    }

    /// Returns lines where the roster and dispatch table disagree.
    ///
    /// A tool with no arms at all is a skew like any other: an empty
    /// contribution and an unconverted door file are indistinguishable, so
    /// neither is excused.
    ///
    /// - Returns: An array of problem descriptions.
    static func problems() -> [String] {
        var lines: [String] = []
        for spec in CdeToolRoster.specs {
            let arms = table[spec.name] ?? [:]
            let declared = Set(spec.ops.map(\.op))
            let served = Set(arms.keys)
            let unanswered = declared.subtracting(served).sorted()
            let unknown = served.subtracting(declared).sorted()
            if !unanswered.isEmpty {
                lines.append(
                    "\(spec.name): roster declares \(unanswered.joined(separator: ", ")) with no dispatch arm"
                )
            }
            if !unknown.isEmpty {
                lines.append(
                    "\(spec.name): dispatch answers \(unknown.joined(separator: ", ")) "
                        + "which the roster does not declare"
                )
            }
        }
        for tool in table.keys.sorted() where CdeToolRoster.spec(named: tool) == nil {
            lines.append("dispatch carries '\(tool)' which the roster does not declare")
        }
        return lines
    }
}

// THE ROSTER IS THE ONLY SOURCE OF THIS VOCABULARY. Every name is declared by a
// `GmAgentTool` in `AgenticsCore/Tools` and reflected into `CdeToolRoster`: the
// plugin's `allowed-tools` frontmatter is generated from the same declarations,
// so a name the server invents is never granted and a name the roster declares
// but the server does not serve is a grant resolving to nothing.

// REFUSALS ARE PUBLISHED RATHER THAN OMITTED, and they ride this same
// projection. An omitted tool is indistinguishable from a capability nobody
// thought of, and an agent that cannot see a refusal invents a workaround. A
// refusal carries no ops by construction, so it lands here with an empty
// dispatch table and answers its own declaration.

// `nonisolated(unsafe)` because a library target gives globals no implicit
// main-actor isolation and `[CdeTool]` cannot be `Sendable`: a `CdeTool` carries
// `run`/`degrade` closures over `Args` and `DaemonClient`. What makes it safe
// is that the array is built ONCE, never mutated, and read only from the single
// stdio read loop in `GmMcpServer.main()` — one thread, one connection, no
// concurrency in this process.
nonisolated(unsafe) let tools: [CdeTool] =
    CdeToolRoster.specs.map { CdeTool(spec: $0, dispatch: CdeDispatch.table[$0.name] ?? [:]) }

// MARK: - Upfront loading

// THE ENTRY TOOLS LOAD UPFRONT, pinned one at a time through each tool's own
// `_meta["anthropic/alwaysLoad"]` rather than server-wide on `.mcp.json`.
// Deferring the WHOLE surface costs more than the context it saves: every
// deferred call fails until the agent thinks to run a ToolSearch by exact
// name, which from inside the agent looks like an unregistered server. The
// pins answer that — what an agent needs to reach the rest is always listed,
// and the phase tools it is told to load by name are not.

// MARK: - The initialize instructions, generated from the registry

/// The `instructions` field of `initialize` is generated from VerbRegistry by
/// `CdeSheet` in GmDaemonSdk, so it cannot drift from the roster. The
/// SubagentStart hook hands spawned agents the same generated text: two
/// generators over one registry drift apart.

/// Startup refusal on stderr, since stdout belongs to the protocol.
///
/// The roster, the registry and the dispatch table must agree, and a binary
/// that serves a surface nobody declared exits instead of answering — a pen
/// that half-works is discovered one failing call at a time, by an agent with
/// no way to tell a build skew from its own mistake.
@MainActor func validateRosterAgainstRegistry() {
    // THE ONE READER THAT REFUSES. `CdeToolRoster.specs` degrades to empty for
    // everything else, which for the pen means serving nothing at all — so the
    // decode failure is turned back into an exit here rather than in shared.
    if let error = CdeToolRoster.rosterDecodeError {
        let report = "gm_mcp: \(CdeToolRoster.generatedPath) is not a decodable [CdeToolSpec]: \(error)\n"
        FileHandle.standardError.write(Data(report.utf8))
        exit(1)
    }
    let lines = GmCdeTools.rosterProblems()
    guard !lines.isEmpty else { return }
    let report = "gm_mcp: roster and dispatch disagree; refusing to serve\n" + lines.joined(separator: "\n") + "\n"
    FileHandle.standardError.write(Data(report.utf8))
    exit(1)
}

extension GmCdeTools {
    /// Reports discrepancies between the roster and dispatch tables.
    ///
    /// The roster check is DATA rather than a side effect on stderr, so a
    /// test can assert it is empty. NEITHER NAME DIRECTION IS REPRESENTABLE:
    /// `tools` is `CdeToolRoster.specs` mapped one-for-one and
    /// `VerbRegistry.cdeToolNames` IS `CdeToolRoster.names`, so neither an
    /// undeclared served name nor an unserved declared one can be constructed.
    /// What stays checkable is the CONTENT of a row — its verbs, its answered
    /// ops, its schema shape.
    ///
    /// - Returns: An array of problem descriptions.
    static func rosterProblems() -> [String] {
        var lines: [String] = []
        for spec in CdeToolRoster.specs where !spec.refuses {
            for op in spec.ops {
                for verb in op.verbs where VerbRegistry.spec(for: verb) == nil {
                    lines.append("\(spec.name) op=\(op.op) names verb \(verb.rawValue), which has no VerbSpec")
                }
            }
            lines.append(contentsOf: schemaShapeProblems(spec))
        }
        lines.append(contentsOf: CdeDispatch.problems())
        let instructionBytes = CdeSheet.instructions.utf8.count
        if instructionBytes > 2_048 {
            lines.append("initialize instructions are \(instructionBytes) bytes (budget 2048)")
        }
        return lines
    }

    /// Returns problems with a tool's schema shape.
    ///
    /// A schema whose `required` list names anything beyond the op selector is
    /// a tool Claude Code refuses to call for every op but the one that happens
    /// to need those arguments. Per-op required-ness is a RUNTIME answer; the
    /// JSON schema carries only the selector.
    ///
    /// - Parameter spec: The tool specification to check.
    /// - Returns: An array of problem descriptions.
    private static func schemaShapeProblems(_ spec: CdeToolSpec) -> [String] {
        var lines: [String] = []
        let selector = CdeTool.selectorKey(spec)
        // cde_rpir_search keys on `scope` and takes `query` for every scope, so
        // its selector pair is the one legitimate two-entry required list.
        let expected = selector == "op" ? ["op"] : [selector, "query"]
        guard case .object(let schema) = spec.schema else {
            return ["\(spec.name) has no object schema"]
        }
        let required: [String]
        if case .array(let entries)? = schema["required"] {
            required = entries.compactMap { if case .string(let key) = $0 { return key } else { return nil } }
        } else {
            required = []
        }
        if required.sorted() != expected.sorted() {
            lines.append(
                "\(spec.name) schema requires [\(required.joined(separator: ", "))]; "
                    + "only [\(expected.joined(separator: ", "))] may be required"
            )
        }
        guard case .object(let properties)? = schema["properties"] else {
            return lines + ["\(spec.name) schema declares no properties"]
        }
        // Every argument an op is documented to need must be a property the
        // schema declares, or the agent is asked for a key it cannot pass.
        for op in spec.ops {
            for key in op.requiredParams where properties[key] == nil {
                lines.append("\(spec.name) op=\(op.op) needs '\(key)', which the schema does not declare")
            }
        }
        return lines
    }
}

// MARK: - Rendering (byte-budgeted)

/// Renders a tool result as JSON with byte budgeting applied.
///
/// CdeTool results are the wire response as sorted-key JSON, the form agents
/// parse. Cutting JSON at a byte count lands the cut mid-key and loses the
/// rest silently; paging by `CdePager` before here prevents it. `op` and the
/// OP's narrowing/write flag come from the caller's pick; on tools with mixed
/// op kinds, one answer cannot fit all calls.
///
/// - Parameters:
///   - tool: The tool being rendered.
///   - value: The result value to encode.
///   - op: The operation name, if applicable.
/// - Returns: The JSON-encoded result as a string.
/// - Throws: `ToolError` if rendering fails.
func renderResult(tool: CdeTool, value: any Encodable, op: String? = nil) throws -> String {
    let opSpec = tool.opSpec(op)
    let label = op.map { "\(tool.name) op=\($0)" } ?? tool.name
    return try CdeResultBudget.render(
        tool: opSpec == nil ? tool.name : label,
        narrowing: opSpec?.narrowing ?? tool.narrowing,
        value: value,
        isWrite: opSpec?.isWrite ?? VerbRegistry.writeCdeTools.contains(tool.name)
    )
}

// MARK: - JSON-RPC loop

/// Writes a JSON-RPC message to stdout.
///
/// - Parameter object: The message to write.
func writeMessage(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// Sends a successful JSON-RPC response.
///
/// - Parameters:
///   - id: The request id.
///   - result: The result object.
func respond(id: Any, result: [String: Any]) {
    writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
}

/// Sends a JSON-RPC error response.
///
/// - Parameters:
///   - id: The request id.
///   - code: The error code.
///   - message: The error message.
func respondError(id: Any, code: Int, message: String) {
    writeMessage(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

// A LIBRARY target, so the multi-call `gm_kernel` Mach-O can carry the MCP
// personality and `gm_mcp` is a shim over `GmMcpServer.main()`. Top-level code
// is legal solely in an executable target's `main.swift`, which is why these
// statements are a function body.

enum GmMcpServer {

    /// The `gm_mcp` personality: a JSON-RPC 2.0 MCP server over stdio.
    ///
    /// A JSON-RPC 2.0 server on newline-delimited stdio, relaying every
    /// `tools/call` to the daemon over the unix socket. A CHILD OF THE
    /// HARNESS: the harness owns this stdin; `ClientKey.resolve()` walks
    /// process ancestry for the activation-claim key; chdir gives one cwd
    /// per session. `@MainActor` matches the implicit isolation of top-level
    /// code.
    @MainActor
    static func main() {
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
                            if tool.alwaysLoad {
                                entry["_meta"] = ["anthropic/alwaysLoad": true]
                            }
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
                    let op = tool.resolvedOp(arguments)
                    let result = try tool.run(arguments, client)
                    respond(
                        id: id,
                        result: [
                            "content": [
                                [
                                    "type": "text",
                                    "text": try renderResult(tool: tool, value: result, op: op),
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
                    // CdeTool-level failures ride the result envelope (isError), never
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
