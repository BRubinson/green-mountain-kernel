import Foundation

/// The cold-start fast path: `cde_init` op=run, then `cde_rpir_briefing`
/// op=open. COMPOSITES, NOT VERBS. Every step below already exists as a daemon verb;
/// what cost fifteen calls was the capability being spread across five round
/// trips plus the reading needed to learn the shape of the phase being entered.
/// Composing them client-side needs no new `MessageType`, handler, migration or
/// wire bump. Every verb touched here is `.record` or `.read`, so this surface
/// needs no primary-door privilege.

// MARK: - Response shapes

/// What `cde_init` returns: everything the caller needed fifteen calls to
/// learn, including the shape of the phase it is ABOUT to enter.
struct PromptInitResult: Encodable {
    struct Resolution: Encodable {
        let matchedBy: String?
        /// True when this call created the prompt, false when it resolved an
        /// existing one.
        ///
        /// The user asked for this explicitly: a caller must always be told
        /// whether it is starting fresh or resuming.
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
        /// One of absent, building or ready.
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
    let gmfsRelativeStoragePath: String?
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

// MARK: - Dispatch

/// This file's contribution to `CdeDispatch`.
nonisolated(unsafe) let fastPathArms: CdeArms = [
    "cde_init": ["run": initArm],
    "cde_rpir_briefing": ["open": briefingOpenArm],
]

/// The cold start as one arm: identity from the working directory, the prompt
/// resolved or created, the derived phase, the lookahead and the briefing's
/// state, folded into a single answer.
private nonisolated(unsafe) let initArm: CdeArm = { args, client in
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
                    }
                ),
                promptUuid: nil,
                sessionUuid: sessionUuid,
                seq: nil,
                code: nil,
                name: nil,
                status: nil,
                gmfsRelativeStoragePath: nil,
                phase: nil,
                instructions: nil,
                gateBlockers: [],
                nextPhase: nil,
                briefing: nil,
                warnings: [
                    "selector '\(selector)' matched \(candidates.count) prompts — pass a seq or an exact name"
                ]
            )
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
                promptUuid: nil,
                sessionUuid: sessionUuid,
                seq: nil,
                code: nil,
                name: nil,
                status: nil,
                gmfsRelativeStoragePath: nil,
                phase: nil,
                instructions: nil,
                gateBlockers: [],
                nextPhase: nil,
                briefing: nil,
                warnings: ["no prompt matched. Pass create:true with name and detail to create one."]
            )
        }
        let row = try client.createPrompt(
            PromptCreateRequest(
                sessionUuid: sessionUuid,
                name: name,
                backstory: "",
                goal: "",
                detail: detail
            )
        )
        created = true
        matchedBy = "created"
        stub = PromptStub(
            uuid: row.uuid,
            sessionUuid: row.sessionUuid,
            seq: row.seq,
            code: row.code,
            name: row.name,
            status: row.status,
            version: row.version,
            gmfsRelativeStoragePath: row.gmfsRelativeStoragePath,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            reports: nil
        )
    }

    guard let prompt = stub else {
        throw ToolError(message: "prompt resolution produced no row")
    }

    // 5. resume IS the first-run path — fetch-or-create, phase derived
    //    from db evidence, so resuming and starting are one call.
    let resumed = try client.promptResume(
        PromptResumeRequest(
            promptUuid: prompt.uuid,
            variant: variant,
            clientKey: ClientKey.resolve()
        )
    )

    // 6. Current phase, its instructions, the gate blockers.
    let next = try client.botNext(BotNextRequest(promptUuid: prompt.uuid))

    // 7. THE LOOKAHEAD. Six of the fifteen calls went to a ref doc,
    //    agent frontmatter and WorkflowSpec.swift to learn the shape of
    //    the phase about to be entered. These are pure functions on the
    //    compiled-in spec — no round trip, no reading.
    let phases = WorkflowSpec.phases(for: variant)
    var nextPhase: PromptInitResult.NextPhase?
    // COMPARE RAW VALUES, NOT CASE NAMES. Phase has String raw values and no
    // CustomStringConvertible, so "\(Phase.clarifyOpen)" is "clarifyOpen"
    // while BOT_NEXT answers "clarify_open"; the six multi-word phases match
    // on the raw value alone. The name below is emitted for the same reason:
    // "reviewFix" is a spelling used nowhere else on the wire.
    if let current = phases.firstIndex(where: { $0.rawValue == next.phase }) {
        let upcoming = current + 1 < phases.count ? phases[current + 1] : phases[current]
        nextPhase = .init(
            name: upcoming.rawValue,
            instructions: WorkflowSpec.instructions(variant: variant, phase: upcoming),
            expectedAgents: WorkflowSpec.expectedExplorationAgents(for: variant).map { "\($0)" }
        )
    }

    // 8. Briefing state, so the caller knows whether to open one.
    var briefing: PromptInitResult.BriefingState = .init(state: "absent", uuid: nil, version: nil)
    if let got = try? client.briefingGet(BriefingGetRequest(promptUuid: prompt.uuid, step: "initial")) {
        briefing = .init(state: got.briefing.status, uuid: got.briefing.uuid, version: got.briefing.version)
    }

    // CAPTURE HEALTH. A session with no binding records nothing from the
    // PostToolUse hook, and the old failure mode was learning that never.
    if let bindings = ensured.claudeSessionBindingCount, bindings == 0 {
        warnings.append(
            "this session has no claude_session_binding row — PostToolUse file-change capture is OFF for it. Restart the session so SessionStart can bind it."
        )
    }

    return PromptInitResult(
        resolution: .init(matchedBy: matchedBy, created: created || resumed.created, candidates: nil),
        promptUuid: prompt.uuid,
        sessionUuid: sessionUuid,
        seq: prompt.seq,
        code: prompt.code,
        name: prompt.name,
        status: prompt.status,
        gmfsRelativeStoragePath: prompt.gmfsRelativeStoragePath,
        phase: next.phase,
        instructions: next.instructions,
        gateBlockers: next.gateBlockers,
        nextPhase: nextPhase,
        briefing: briefing,
        warnings: warnings
    )
}

/// Open the briefing row a briefer then fills — the only legal response to the
/// 'initial briefing not ready' gate blocker.
private nonisolated(unsafe) let briefingOpenArm: CdeArm = { args, client in
    try client.briefingOpen(
        BriefingOpenRequest(
            briefingForStep: args.optString("step") ?? "initial",
            promptUuid: try args.string("prompt_uuid"),
            clientKey: ClientKey.resolve()
        )
    )
}
