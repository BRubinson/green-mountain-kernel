import Foundation

/// Compiled-in wire-protocol version. Bump whenever the wire shape changes.
/// The handshake compares client and server values; mismatch handling is
/// DIRECTIONAL: a newer client makes the (stale) daemon self-exit so the
/// freshly built binary can take over, while an older client is merely
/// rejected — the daemon stays up (an old pinned-Kit GMVibes must never be
/// able to kill-loop a fresh daemon).
public enum GMCCWireProtocol {
    /// v18 — m0017 RENAMED a wire field on an existing message rather than
    /// adding one: DopePropertyBody.related_property_ref became
    /// relationship_target_ref, and DopeNodeFields.related_property_uuid
    /// became relationship_target_uuid.
    ///
    /// That is an INCOMPATIBLE change under the rule in CLAUDE.md, and the
    /// failure it prevents is silent rather than loud: both fields are
    /// Optional, so a stale peer's `related_property_ref` decodes to nil, and
    /// a relationship property with a nil target then trips
    ///   CHECK ((data_type = 'relationship') = (relationship_target_uuid IS NOT NULL))
    /// at write time — or worse, writes nothing where a reference was meant.
    /// The handshake has to reject that peer instead of letting it through.
    ///
    /// v19 — m0018 RENAMED a payload TAG on an existing message: the
    /// diagram element type `dope_scope` became
    /// `dope_scope_persistence_layer`, and DiagramElementPayload's
    /// `dopeScope(DopeScopePayload)` case renamed with it.
    ///
    /// Incompatible for the same reason v18 was, and louder about it: the tag
    /// IS the discriminator, so a stale peer sending `dope_scope` decodes to
    /// an unknown case, and one receiving `dope_scope_persistence_layer`
    /// cannot map it onto any case it knows. The db CHECK now names only the
    /// new value too, so a stale writer's rows would be rejected outright.
    /// Reject the peer at the handshake instead.
    ///
    /// (The additive OPTIONAL fields that landed alongside it —
    /// DopeCogElementAddRequest.dope_persistence_code and
    /// DopeCogElementNode.dope_persistence_code — would NOT have bumped this
    /// on their own; they decode safely in both directions.)
    /// v20 — three NEW message types: PROMPT_DIAGRAM_QUALIFY / _GET / _LIST,
    /// the prompt_qualified_diagram surface (m0022). A new message type is an
    /// unambiguous bump under CLAUDE.md: a stale daemon answers UNKNOWN_TYPE
    /// to a verb that is supposed to exist, and a stale client cannot be told
    /// the verb is there.
    ///
    /// What did NOT bump this: the DiagramElementPayload cases added earlier
    /// in this same body of work. Those are ADDITIVE tags on an existing
    /// message and they ride under the additive-OPTIONAL convention — the
    /// convention was not abandoned, it simply does not cover new message
    /// types. Read the v18/v19 notes above for what a RENAME costs by
    /// contrast.
    ///
    /// And a bonus that falls out of landing v20 at all: those additive tags
    /// carried an accepted risk — an older peer meeting an unknown payload tag
    /// fails in the decoder rather than at the door. Once every peer is at
    /// v20 that risk is retired for free, because the handshake rejects a
    /// stale peer before any payload reaches a decoder.
    ///
    /// v21 → v22: KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE — the
    /// portable-kbite family. Three new message types, so the bump is
    /// mandatory under the same rule as v20.
    ///
    /// v22 → v23: the Diagram Studio train. Four new message types —
    /// DIAGRAM_SEARCH / DIAGRAM_DELETE / DIAGRAM_WRITE_REPO /
    /// DIAGRAM_INGEST — force the bump, and every otherwise-UNSAFE addition
    /// deliberately rides the same fence (the v20 "bonus", used on purpose
    /// this time): the uml_node payload kind, the widened
    /// DiagramConnectorHead vocabulary, ConnectorPayload.routingKind /
    /// tailKind, and diagram.visibility. A pre-v23 peer never reaches the
    /// decoders these would crash — the handshake rejects it at the door.
    /// v23 → v24: the dynamic-workflows train (m0025). New message families
    /// — PROMPT_START / PROMPT_RESUME / BOT_NEXT / BOT_GET,
    /// CLARIFY_QUESTION_ADD / CLARIFY_NOTE_ADD (CLARIFY_ASK retired; ANSWER
    /// retooled in place), CARE_PACKAGE_OPEN/REF_ADD/COMPLETE/GET,
    /// ARCH_OPTION_ADD / ARCH_DECIDE — force the bump, and the honest row
    /// reshapes ride the same fence: ExplorationSummaryRow +agentType
    /// (per-agent rows), the merged finding/file pair (EXPLORE_RANK now
    /// prompt-scoped), AgentBriefingRow's typed ref children riding
    /// BRIEFING_COMPLETE (body gone), the slimmed ClarificationSummaryRow,
    /// and SearchKind's retired clarification/key-file cases.
    ///
    /// v24 → v25: session-bound hook attribution (m0026). TWO structural
    /// changes force it, and only these two: the NEW message type
    /// AGENT_REGISTER, and the REMOVAL of BOT_SET_BASELINE. Both are
    /// unambiguous under CLAUDE.md — a stale daemon answers UNKNOWN_TYPE to a
    /// verb that is supposed to exist, and a stale client keeps sending one
    /// that no longer does.
    ///
    /// What did NOT bump this, and rides the same fence: every payload field
    /// of the attribution axis — ContextEnsureRequest.claude_session_id,
    /// FileChangeAdd's claude_session_id / claude_turn_id / tool_use_id /
    /// tool_name / agent_type / permission_mode / duration_ms /
    /// transcript_path, FileChangeAddResponse.deduplicated and the matching
    /// FileChangeRow fields. Those are additive OPTIONALs that decode safely
    /// in both directions, which is the convention that keeps GMVibes'
    /// vendored kit compatible. FileChangeAdd.client_key going away is
    /// likewise decode-safe (an unknown key is ignored) — it needs no bump of
    /// its own and simply travels with this one.
    public static let version = 25
}

/// Discriminator for every NDJSON message on the socket. One case per spec
/// message; each request type has its own handler in gmcc_daemon.
public enum MessageType: String, Codable, Hashable, CaseIterable, Sendable {
    // Infra
    case hello = "HELLO"
    case ping = "PING"
    case status = "STATUS"
    case shutdown = "SHUTDOWN"
    case subscribe = "SUBSCRIBE"
    case backup = "BACKUP"
    // Context bootstrap
    case contextEnsure = "CONTEXT_ENSURE"
    case contextGet = "CONTEXT_GET"
    // Listing (enumeration — the Landing browse surface)
    case projectList = "PROJECT_LIST"
    // v16 — the first project-level mutation (m0011's primary_project_branch).
    case projectUpdate = "PROJECT_UPDATE"
    // v17 — the masking/promotion/cogs/search family.
    case dopePromote = "DOPE_PROMOTE"
    case dopeCogAdd = "DOPE_COG_ADD"
    case dopeCogUpdate = "DOPE_COG_UPDATE"
    case dopeCogDelete = "DOPE_COG_DELETE"
    case dopeCogGet = "DOPE_COG_GET"
    case dopeCogElementAdd = "DOPE_COG_ELEMENT_ADD"
    case dopeCogElementUpdate = "DOPE_COG_ELEMENT_UPDATE"
    case dopeCogElementDelete = "DOPE_COG_ELEMENT_DELETE"
    case dopeSearch = "DOPE_SEARCH"
    case instanceList = "INSTANCE_LIST"
    case sessionList = "SESSION_LIST"
    // Session
    case sessionGet = "SESSION_GET"
    case sessionUpdate = "SESSION_UPDATE"
    // Prompts
    case promptCreate = "PROMPT_CREATE"
    case promptList = "PROMPT_LIST"
    case promptGet = "PROMPT_GET"
    case promptUpdateContent = "PROMPT_UPDATE_CONTENT"
    case promptSetStatus = "PROMPT_SET_STATUS"
    // Bot workflow machine (v24): the daemon-held state machine. START
    // creates the workflow row on a draft prompt (no status change — the
    // set-status door is untouched); RESUME adopts existing evidence; NEXT
    // computes the phase from db state and serves instructions + uuids;
    // GET is the raw row.
    case promptStart = "PROMPT_START"
    case promptResume = "PROMPT_RESUME"
    case botNext = "BOT_NEXT"
    case botGet = "BOT_GET"
    // Agent registry (v25): the spawner's authority write for one agent_id,
    // merged with the identity the SubagentStart hook records.
    case agentRegister = "AGENT_REGISTER"
    // Artifacts
    case artifactAdd = "ARTIFACT_ADD"
    case artifactList = "ARTIFACT_LIST"
    // Prompt-qualified diagrams (v20) — a prompt's reading of a rendered
    // diagram. Prompt-scoped, so it sits with the artifacts rather than with
    // the DIAGRAM family, which is owner-tier addressed.
    case promptDiagramQualify = "PROMPT_DIAGRAM_QUALIFY"
    case promptDiagramGet = "PROMPT_DIAGRAM_GET"
    case promptDiagramList = "PROMPT_DIAGRAM_LIST"
    // File changes
    case fileChangeAdd = "FILE_CHANGE_ADD"
    case fileChangeList = "FILE_CHANGE_LIST"
    // Kbites
    case kbiteList = "KBITE_LIST"
    case kbiteAdd = "KBITE_ADD"
    case kbiteRemove = "KBITE_REMOVE"
    case kbiteMawOpen = "KBITE_MAW_OPEN"
    case kbiteDigest = "KBITE_DIGEST"
    case kbiteGet = "KBITE_GET"
    case kbiteFileGet = "KBITE_FILE_GET"
    case kbiteSearch = "KBITE_SEARCH"
    case kbiteKeywordTag = "KBITE_KEYWORD_TAG"
    case kbiteExport = "KBITE_EXPORT"
    case kbiteImport = "KBITE_IMPORT"
    case kbiteDelete = "KBITE_DELETE"
    // Catalog search (instances + sessions, the GMVibes search bar)
    case catalogSearch = "CATALOG_SEARCH"
    // Full-text search over prompt/clarification/architecture text (v8)
    case search = "SEARCH"
    // Clarification machine (v24: the m0025 split — questions/notes/care
    // package; CLARIFY_ASK retired with the legacy single-table model)
    case clarifyOpen = "CLARIFY_OPEN"
    case clarifyQuestionAdd = "CLARIFY_QUESTION_ADD"
    case clarifyNoteAdd = "CLARIFY_NOTE_ADD"
    case clarifySeal = "CLARIFY_SEAL"
    case clarifyAnswer = "CLARIFY_ANSWER"
    case clarifyReopen = "CLARIFY_REOPEN"
    case clarifyFinalize = "CLARIFY_FINALIZE"
    case clarifyGet = "CLARIFY_GET"
    // Care package (v24): the standalone clarified-intent bundle.
    case carePackageOpen = "CARE_PACKAGE_OPEN"
    case carePackageRefAdd = "CARE_PACKAGE_REF_ADD"
    case carePackageComplete = "CARE_PACKAGE_COMPLETE"
    case carePackageGet = "CARE_PACKAGE_GET"
    // Architecture machine (v7)
    case archOpen = "ARCH_OPEN"
    case archSummarize = "ARCH_SUMMARIZE"
    case archPersistAdd = "ARCH_PERSIST_ADD"
    case archFieldAdd = "ARCH_FIELD_ADD"
    case archGeneralAdd = "ARCH_GENERAL_ADD"
    case archPropose = "ARCH_PROPOSE"
    case archApprove = "ARCH_APPROVE"
    case archRevise = "ARCH_REVISE"
    case archGet = "ARCH_GET"
    // Architecture options (v24): the architect pen inversion — option rows
    // written by architect agents; DECIDE selects one and rejects siblings.
    case archOptionAdd = "ARCH_OPTION_ADD"
    case archDecide = "ARCH_DECIDE"
    // Exploration report machine (v9)
    case exploreOpen = "EXPLORE_OPEN"
    case exploreKeyFileAdd = "EXPLORE_KEY_FILE_ADD"
    case exploreFindingAdd = "EXPLORE_FINDING_ADD"
    case exploreRank = "EXPLORE_RANK"
    case exploreComplete = "EXPLORE_COMPLETE"
    case exploreReopen = "EXPLORE_REOPEN"
    case exploreGet = "EXPLORE_GET"
    // Review report machine (v9)
    case reviewOpen = "REVIEW_OPEN"
    case reviewFindingAdd = "REVIEW_FINDING_ADD"
    case reviewRank = "REVIEW_RANK"
    case reviewResolve = "REVIEW_RESOLVE"
    case reviewComplete = "REVIEW_COMPLETE"
    case reviewReopen = "REVIEW_REOPEN"
    case reviewGet = "REVIEW_GET"
    // Agent briefing (v21): the context package a doper agent assembles for a
    // phase; consumed by spawned agents via the stub -> get pull.
    case briefingOpen = "BRIEFING_OPEN"
    case briefingComplete = "BRIEFING_COMPLETE"
    case briefingGet = "BRIEFING_GET"
    case briefingList = "BRIEFING_LIST"
    case briefingStub = "BRIEFING_STUB"
    // DOPED domain modeling (v11; dopeList v12)
    case dopeInit = "DOPE_INIT"
    case dopeList = "DOPE_LIST"
    case dopeGet = "DOPE_GET"
    case dopeNodeAdd = "DOPE_NODE_ADD"
    case dopeNodeUpdate = "DOPE_NODE_UPDATE"
    case dopeNodeDelete = "DOPE_NODE_DELETE"
    case dopeReadRepo = "DOPE_READ_REPO"
    case dopeMergePlan = "DOPE_MERGE_PLAN"
    case dopeResolve = "DOPE_RESOLVE"
    case dopeWriteRepo = "DOPE_WRITE_REPO"
    case dopeIngest = "DOPE_INGEST"
    // DIAGRAM domain modeling (v15). BATCH_APPLY is the primary interactive
    // write; the NODE verbs are one-mutation batches over the same store body.
    case diagramInit = "DIAGRAM_INIT"
    case diagramList = "DIAGRAM_LIST"
    case diagramGet = "DIAGRAM_GET"
    case diagramNodeAdd = "DIAGRAM_NODE_ADD"
    case diagramNodeUpdate = "DIAGRAM_NODE_UPDATE"
    case diagramNodeDelete = "DIAGRAM_NODE_DELETE"
    case diagramBatchApply = "DIAGRAM_BATCH_APPLY"
    // Diagram Studio (v23): cross-tier browse/search (LIST keeps its
    // no-union picker contract), row delete, and the public-visibility
    // serialization pair (the dope write-repo/ingest twins).
    case diagramSearch = "DIAGRAM_SEARCH"
    case diagramDelete = "DIAGRAM_DELETE"
    case diagramWriteRepo = "DIAGRAM_WRITE_REPO"
    case diagramIngest = "DIAGRAM_INGEST"
    // Git-state resolution (v7)
    case sessionResolve = "SESSION_RESOLVE"
    case instanceCurrentSession = "INSTANCE_CURRENT_SESSION"
    // Daemon config (v7)
    case pathsGet = "PATHS_GET"
    case configSet = "CONFIG_SET"
    // Audit
    case eventList = "EVENT_LIST"
    // Daemon → client only
    case event = "EVENT"
    case error = "ERROR"
}

/// Version-first pre-head: `type` stays a RAW STRING so the protocol-version
/// gate runs even for message names this build doesn't know. A newer client
/// invoking a newer-only message must get PROTOCOL_MISMATCH (+ directional
/// self-exit), not a decode failure — same forward-compat rule as
/// ErrorPayload.code and event kind. Narrow to MessageType only AFTER the
/// version check; unknown-but-version-matched names get UNKNOWN_TYPE echoing
/// the real request_id.
public struct RawEnvelopeHead: Codable, Hashable, Sendable {
    public let protocolVersion: Int
    public let typeRaw: String
    public let requestId: String?

    public var type: MessageType? { MessageType(rawValue: typeRaw) }

    // The intentional rename ("type" is kept raw for forward compat).
    // Sibling keys MUST stay bare cases: an explicit snake_case raw value
    // stops matching under .convertFromSnakeCase and the field silently
    // decodes to nil. "type" has no underscore, so it is a fixed point of
    // both key strategies.
    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case typeRaw = "type"
        case requestId
    }

    public init(
        protocolVersion: Int,
        typeRaw: String,
        requestId: String?
    ) {
        self.protocolVersion = protocolVersion
        self.typeRaw = typeRaw
        self.requestId = requestId
    }
}

/// The minimal prefix decodable from any incoming line — enough to route the
/// message and enforce the protocol-version handshake before the payload type
/// is known.
public struct EnvelopeHead: Codable, Hashable, Sendable {
    public let protocolVersion: Int
    public let type: MessageType
    public let requestId: String

    public init(
        protocolVersion: Int,
        type: MessageType,
        requestId: String
    ) {
        self.protocolVersion = protocolVersion
        self.type = type
        self.requestId = requestId
    }
}

/// Client → daemon message wrapper.
public struct RequestEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let type: MessageType
    public let requestId: String
    public let payload: Payload

    public init(
        type: MessageType,
        requestId: String = UUID().uuidString.lowercased(),
        payload: Payload
    ) {
        self.protocolVersion = GMCCWireProtocol.version
        self.type = type
        self.requestId = requestId
        self.payload = payload
    }
}

/// Daemon → client message wrapper. `requestId` echoes the request (empty for
/// unsolicited event notifications).
public struct ResponseEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let type: MessageType
    public let requestId: String
    public let ok: Bool
    public let payload: Payload?
    public let error: ErrorPayload?

    public init(
        type: MessageType,
        requestId: String,
        ok: Bool,
        payload: Payload? = nil,
        error: ErrorPayload? = nil
    ) {
        self.protocolVersion = GMCCWireProtocol.version
        self.type = type
        self.requestId = requestId
        self.ok = ok
        self.payload = payload
        self.error = error
    }
}

public enum ErrorCode: String, Codable, Hashable, CaseIterable, Sendable {
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case badRequest = "BAD_REQUEST"
    case unknownType = "UNKNOWN_TYPE"
    case dbError = "DB_ERROR"
    case internalError = "INTERNAL_ERROR"
    // Domain codes (StoreError → wire)
    case notFound = "NOT_FOUND"
    case versionConflict = "VERSION_CONFLICT"
    case invalidTransition = "INVALID_TRANSITION"
    case contentLocked = "CONTENT_LOCKED"
    /// The prompt exists but has no clarification/architecture/exploration/
    /// review summary yet — open one. Plain NOT_FOUND means only that the
    /// uuid itself is unknown.
    case summaryAbsent = "SUMMARY_ABSENT"
}

/// Error envelope. `code` travels as a RAW STRING so a daemon that grows new
/// codes can't make an older pinned-Kit client fail to decode the whole
/// envelope — clients switch on the typed accessor and fall through on nil.
public struct ErrorPayload: Codable, Hashable, Sendable {
    public let codeRaw: String
    public let message: String
    /// Set on PROTOCOL_MISMATCH so clients can be directional too: retry with
    /// autostart only when a freshly built binary would win.
    public let daemonProtocolVersion: Int?

    public var code: ErrorCode? { ErrorCode(rawValue: codeRaw) }

    // Same rule as RawEnvelopeHead: only the intentional rename is explicit,
    // every sibling stays a bare case ("daemon_protocol_version" as a raw
    // value would silently decode to nil under .convertFromSnakeCase — and
    // with it the client's directional PROTOCOL_MISMATCH retry).
    private enum CodingKeys: String, CodingKey {
        case codeRaw = "code"
        case message
        case daemonProtocolVersion
    }

    public init(code: ErrorCode, message: String, daemonProtocolVersion: Int? = nil) {
        self.codeRaw = code.rawValue
        self.message = message
        self.daemonProtocolVersion = daemonProtocolVersion
    }
}

/// Payload type for responses that carry no data.
public struct EmptyPayload: Codable, Hashable, Sendable {
    public init() {}
}

/// NDJSON framing helpers: one JSON document per `\n`-terminated line.
/// Coders come from WireCodec — the snake_case key strategies are the wire's
/// entire casing contract now that types carry no CodingKeys.
public enum NDJSON {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try WireCodec.encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try WireCodec.decoder.decode(type, from: line)
    }
}
