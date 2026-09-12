import Foundation
import GMCCDaemonKit

/// The cold-start fast path: `prompt_init` → `init_briefing` →
/// `wait_for_briefing`.
///
/// WHY THESE ARE COMPOSITES, NOT VERBS. Every step below already exists as a
/// daemon verb. What cost fifteen calls was never missing capability — it was
/// that the capability was spread across five round trips plus reading a ref
/// doc, an agent definition, and `WorkflowSpec.swift` itself to learn the shape
/// of the phase about to be entered. Composing them client-side buys the whole
/// win with no new `MessageType`, no handler, no migration, and no wire bump.
///
/// EVERY VERB TOUCHED HERE IS `.record` OR `.read`. `promptCreate`,
/// `promptStart`, `promptResume` and `briefingOpen` are all
/// `.record` in VerbRegistry and legal for this client's role. The belief that
/// they were primary doors — and that this therefore needed a new
/// primary-admitting surface — was simply wrong, and checking it is what turned
/// a redesign into three wrappers.

// MARK: - Response shapes

/// What `prompt_init` returns: everything the caller needed fifteen calls to
/// learn, including the shape of the phase it is ABOUT to enter.
struct PromptInitResult: Encodable {
    struct Resolution: Encodable {
        let matchedBy: String?
        /// True when this call created the prompt, false when it resolved an
        /// existing one. The user asked for this explicitly: a caller must
        /// always be told whether it is starting fresh or resuming.
        let created: Bool
        /// Populated ONLY when the selector was ambiguous — and when it is, no
        /// prompt was touched.
        let candidates: [Candidate]?
    }

    struct Candidate: Encodable {
        let seq: Int64
        let code: String
        let name: String
        let status: String
        let uuid: String
    }

    struct NextPhase: Encodable {
        let name: String?
        let instructions: String?
        let expectedAgents: [String]
    }

    struct BriefingState: Encodable {
        /// absent | building | ready
        let state: String
        let uuid: String?
        let version: Int64?
    }

    let resolution: Resolution
    let promptUuid: String?
    let sessionUuid: String?
    let seq: Int64?
    let code: String?
    let name: String?
    let status: String?
    let ckfsRelativeStoragePath: String?
    let phase: String?
    let instructions: String?
    let gateBlockers: [String]
    let nextPhase: NextPhase?
    let briefing: BriefingState?
    /// Non-fatal conditions the caller must see but that must not fail the
    /// call — chiefly a session with no binding, which means capture is off.
    let warnings: [String]
}

struct BriefingWaitResult: Encodable {
    /// ready | timed_out — a timeout is a RESULT, never an error.
    let status: String
    let briefingUuid: String?
    let briefingStatus: String?
    let version: Int64?
    let note: String?
}

// MARK: - Tools

/// A function rather than a global `let`: `Tool` holds a closure and is not
/// Sendable, which Swift 6 refuses as shared mutable state at file scope. The
/// roster in main.swift escapes this only by living in top-level code.
func makeFastPathTools() -> [Tool] { [

    Tool(
        name: "prompt_init",
        description: """
            START A BOT RUN. Resolve a prompt by what a person actually types — a seq (10), \
            a code (p10), a name, or a unique fragment of one — or create it, enter the workflow \
            machine, and return everything needed to act: the uuid bundle, the derived phase and \
            its instructions, the NEXT phase's expected agents, gate blockers, and whether a \
            briefing is needed or already exists. Always reports whether the prompt is NEW or \
            RESUMED. Session and project come from the working directory and git branch, so no \
            uuid has to be known in advance. An ambiguous selector returns candidates and \
            touches nothing.
            """,
        params: [
            ("selector", "string", "Prompt seq (10), code (p10), exact name, or a unique fragment of a name", false),
            ("variant", "string", "Workflow variant: bot | rpi | team (default bot)", false),
            ("create", "boolean", "Create the prompt when the selector matches nothing. Requires name and detail — a typo must never create a prompt", false),
            ("name", "string", "Name for a newly created prompt (with create)", false),
            ("detail", "string", "Detail text for a newly created prompt (with create). STAY TRUE: the user's passed prompt, verbatim", false),
        ],
        run: { args, client in
            let variant = BotVariant(rawValue: args.optString("variant") ?? "bot") ?? .bot
            var warnings: [String] = []

            // 1. $PWD + git branch -> project / instance / session. This is the
            //    "keyed on cwd+branch" resolution: the caller holds no uuid and
            //    is never asked for one.
            let context = try ContextBuilder.ensureRequest()
            let ensured = try client.ensureContext(context)
            let sessionUuid = ensured.sessionUuid

            // 2 + 3. The candidate set, then a pure fold over it.
            let selector = args.optString("selector")
            var stub: PromptStub?
            var matchedBy: String?
            var created = false

            if let selector, !selector.isEmpty {
                let stubs = try client.listPrompts(PromptListRequest(sessionUuid: sessionUuid)).prompts
                switch PromptResolver.resolve(selector, in: stubs) {
                case let .matched(hit, by):
                    stub = hit
                    matchedBy = by.rawValue
                case let .ambiguous(candidates):
                    // NOTHING IS TOUCHED. Returning a guess here would file a
                    // whole run against the wrong prompt, permanently.
                    return PromptInitResult(
                        resolution: .init(
                            matchedBy: nil,
                            created: false,
                            candidates: candidates.map {
                                .init(seq: $0.seq, code: $0.code, name: $0.name, status: $0.status, uuid: $0.uuid)
                            }),
                        promptUuid: nil, sessionUuid: sessionUuid, seq: nil, code: nil, name: nil,
                        status: nil, ckfsRelativeStoragePath: nil, phase: nil, instructions: nil,
                        gateBlockers: [], nextPhase: nil, briefing: nil,
                        warnings: ["selector '\(selector)' matched \(candidates.count) prompts — pass a seq or an exact name"])
                case .notFound:
                    break
                }
            }

            // 4. Creation is OPT-IN and needs both halves. A mistyped selector
            //    must not silently become a new prompt.
            if stub == nil {
                let wantsCreate = args.json["create"]?.boolValue ?? false
                guard wantsCreate,
                      let name = args.optString("name"),
                      let detail = args.optString("detail")
                else {
                    return PromptInitResult(
                        resolution: .init(matchedBy: nil, created: false, candidates: nil),
                        promptUuid: nil, sessionUuid: sessionUuid, seq: nil, code: nil, name: nil,
                        status: nil, ckfsRelativeStoragePath: nil, phase: nil, instructions: nil,
                        gateBlockers: [], nextPhase: nil, briefing: nil,
                        warnings: ["no prompt matched. Pass create:true with name and detail to create one."])
                }
                let row = try client.createPrompt(PromptCreateRequest(
                    sessionUuid: sessionUuid,
                    name: name,
                    backstory: "",
                    goal: "",
                    detail: detail))
                created = true
                matchedBy = "created"
                stub = PromptStub(
                    uuid: row.uuid, sessionUuid: row.sessionUuid, seq: row.seq, code: row.code,
                    name: row.name, status: row.status, version: row.version,
                    ckfsRelativeStoragePath: row.ckfsRelativeStoragePath, reports: nil,
                    createdAt: row.createdAt, updatedAt: row.updatedAt)
            }

            guard let prompt = stub else {
                throw ToolError(message: "prompt resolution produced no row")
            }

            // 5. resume IS the first-run path — fetch-or-create, phase derived
            //    from db evidence, so resuming and starting are one call.
            let resumed = try client.promptResume(PromptResumeRequest(
                promptUuid: prompt.uuid,
                variant: variant,
                clientKey: ClientKey.resolve()))

            // 6. Current phase, its instructions, the gate blockers.
            let next = try client.botNext(BotNextRequest(promptUuid: prompt.uuid))

            // 7. THE LOOKAHEAD. Six of the fifteen calls went to a ref doc,
            //    agent frontmatter and WorkflowSpec.swift to learn the shape of
            //    the phase about to be entered. These are pure functions on the
            //    compiled-in spec — no round trip, no reading.
            let phases = WorkflowSpec.phases(for: variant)
            var nextPhase: PromptInitResult.NextPhase?
            // COMPARE RAW VALUES, NOT CASE NAMES. Phase has String raw values and
            // no CustomStringConvertible, so "\(Phase.clarifyOpen)" is
            // "clarifyOpen" while bot_next emits "clarify_open" — the six
            // multi-word phases (clarify_open, clarify_user, care_package,
            // arch_options, plan_gate, review_fix) could never match, and
            // next_phase came back silently null for half the graph. The name
            // below is emitted for the same reason: "reviewFix" is a spelling
            // used nowhere else on the wire.
            if let current = phases.firstIndex(where: { $0.rawValue == next.phase }) {
                let upcoming = current + 1 < phases.count ? phases[current + 1] : phases[current]
                nextPhase = .init(
                    name: upcoming.rawValue,
                    instructions: WorkflowSpec.instructions(variant: variant, phase: upcoming),
                    expectedAgents: WorkflowSpec.expectedExplorationAgents(for: variant).map { "\($0)" })
            }

            // 8. Briefing state, so the caller knows whether to open one.
            var briefing: PromptInitResult.BriefingState = .init(state: "absent", uuid: nil, version: nil)
            if let got = try? client.briefingGet(BriefingGetRequest(promptUuid: prompt.uuid, step: "initial")) {
                briefing = .init(state: got.briefing.status, uuid: got.briefing.uuid, version: got.briefing.version)
            }

            // CAPTURE HEALTH. A session with no binding records nothing from the
            // PostToolUse hook, and the old failure mode was learning that never.
            if let bindings = ensured.claudeSessionBindingCount, bindings == 0 {
                warnings.append("this session has no claude_session_binding row — PostToolUse file-change capture is OFF for it. Restart the session so SessionStart can bind it.")
            }

            return PromptInitResult(
                resolution: .init(matchedBy: matchedBy, created: created || resumed.created, candidates: nil),
                promptUuid: prompt.uuid,
                sessionUuid: sessionUuid,
                seq: prompt.seq,
                code: prompt.code,
                name: prompt.name,
                status: prompt.status,
                ckfsRelativeStoragePath: prompt.ckfsRelativeStoragePath,
                phase: next.phase,
                instructions: next.instructions,
                gateBlockers: next.gateBlockers,
                nextPhase: nextPhase,
                briefing: briefing,
                warnings: warnings)
        }),

    Tool(
        name: "init_briefing",
        description: """
            Open the briefing row a doper then fills. The only legal response to the \
            'initial briefing not ready' gate blocker, and the very next call after prompt_init \
            for a prompt whose briefing is absent.
            """,
        params: [
            ("prompt_uuid", "string", "Owner prompt uuid", true),
            ("step", "string", "Briefing step (default initial)", false),
        ],
        run: { args, client in
            try client.briefingOpen(BriefingOpenRequest(
                promptUuid: try args.string("prompt_uuid"),
                briefingForStep: args.optString("step") ?? "initial",
                clientKey: ClientKey.resolve()))
        }),

    Tool(
        name: "wait_for_briefing",
        description: """
            Block until the briefing reads ready, then return it. A TIMEOUT IS A RESULT, \
            not an error: call again to keep waiting. Default 60s, capped at 110s — a tool call \
            from the main conversation that runs past ~2 minutes is moved to a background task \
            and silently hands control back, so a longer wait would return nothing useful.
            """,
        params: [
            ("prompt_uuid", "string", "Owner prompt uuid", true),
            ("step", "string", "Briefing step (default initial)", false),
            ("timeout_seconds", "number", "How long to wait, 1-110 (default 60)", false),
        ],
        run: { args, client in
            let promptUuid = try args.string("prompt_uuid")
            let step = args.optString("step") ?? "initial"
            let requested = args.json["timeout_seconds"]?.int64Value ?? 60
            // Clamped, not trusted: the ceiling is a harness property, so a
            // caller asking for 600 must still get an answer it can act on.
            let timeout = Int(max(1, min(requested, 110)))

            let outcome = try awaitBriefingReady(timeoutSeconds: timeout, fetch: {
                try? client.briefingGet(BriefingGetRequest(promptUuid: promptUuid, step: step))
            })
            switch outcome {
            case let .ready(response):
                return BriefingWaitResult(
                    status: "ready",
                    briefingUuid: response.briefing.uuid,
                    briefingStatus: response.briefing.status,
                    version: response.briefing.version,
                    note: nil)
            case let .timedOut(lastSeen):
                return BriefingWaitResult(
                    status: "timed_out",
                    briefingUuid: lastSeen?.uuid,
                    briefingStatus: lastSeen?.status,
                    version: lastSeen?.version,
                    note: lastSeen == nil
                        ? "no briefing row exists yet — call init_briefing first"
                        : "still \(lastSeen?.status ?? "building") after \(timeout)s — call again to keep waiting")
            }
        }),
] }
