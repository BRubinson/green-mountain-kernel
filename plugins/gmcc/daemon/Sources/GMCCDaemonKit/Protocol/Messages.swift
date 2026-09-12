import Foundation

// Codable wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from
// WireCodec's key strategies — types declare NO CodingKeys (the two
// intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

// MARK: - Identity

/// The identity block wrapped into every domain table. Defined once here;
/// GRDB records declare these five columns flat because GRDB flattens only
/// top-level Codable properties into columns.
public struct BaseEntity: Codable, Hashable, Sendable {
    /// Serial rowid — internal to the db, nil before insert.
    public let id: Int64?
    /// v4 lowercase — the external join key shared with ckfs yamls and the wire.
    public let uuid: String
    /// Incremented by the daemon on every write (optimistic concurrency —
    /// guarded updates require the caller's expected_version to match).
    public let version: Int64
    public let createdAt: String
    public let updatedAt: String

    public init(id: Int64? = nil, uuid: String, version: Int64, createdAt: String, updatedAt: String) {
        self.id = id
        self.uuid = uuid
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Kinds of rows in the append-only daemon_event table. Stored as free text in
/// the db; this enum is the write-path enforcement. On the wire (events,
/// EVENT_LIST) kind travels as a raw string so old clients survive new kinds.
public enum DaemonEventKind: String, Codable, Hashable, CaseIterable, Sendable {
    case createProject = "CREATE_PROJECT"
    case createInstance = "CREATE_INSTANCE"
    case createSession = "CREATE_SESSION"
    case updateSession = "UPDATE_SESSION"
    // Added with m0011's project.primary_project_branch. New kinds travel as
    // raw strings (see the v7 note above), so this needs no version bump.
    case updateProject = "UPDATE_PROJECT"
    case createPrompt = "CREATE_PROMPT"
    case updatePrompt = "UPDATE_PROMPT"
    case promptStatusChange = "PROMPT_STATUS_CHANGE"
    case addArtifact = "ADD_ARTIFACT"
    case fileChange = "FILE_CHANGE"
    case backup = "BACKUP"
    case daemonStart = "DAEMON_START"
    case daemonStop = "DAEMON_STOP"
    case addKbite = "ADD_KBITE"
    case removeKbite = "REMOVE_KBITE"
    case kbiteDigest = "KBITE_DIGEST"
    case kbiteKeywordTag = "KBITE_KEYWORD_TAG"
    // v7 — new kinds travel as raw strings on the wire, so no version bump is
    // ever needed to add one.
    case clarificationChange = "CLARIFICATION_CHANGE"
    case architectureChange = "ARCHITECTURE_CHANGE"
    case configSet = "CONFIG_SET"
    // v9 — durable rows like clarificationChange (never ephemeral): the
    // exploration/review report machines.
    case explorationChange = "EXPLORATION_CHANGE"
    case reviewChange = "REVIEW_CHANGE"
    // v11 — durable rows: the DOPED domain-modeling machine.
    case dopeChange = "DOPE_CHANGE"
    // v15 — durable rows: the DIAGRAM machine (GMVibes' live-refresh signal;
    // one event per granular mutation OR per whole batch).
    case diagramChange = "DIAGRAM_CHANGE"
    // v20 — durable rows: a prompt qualified a rendered diagram. Distinct
    // from diagramChange on purpose — nothing about the CANVAS moved, so a
    // diagram listener must not be told to refetch a tree.
    case promptDiagramQualified = "PROMPT_DIAGRAM_QUALIFIED"
    // v21 — durable rows: the agent-briefing machine (open/reset, complete,
    // and nothing else — reads never event). Payload carries the step, the
    // status edge, and the stamped scope revision so GMVibes can refresh a
    // briefing panel without a fetch-diff.
    case briefingChange = "BRIEFING_CHANGE"
    // v24 — durable rows: the bot workflow machine (start/resume, derived
    // phase transitions, done). Payload carries the variant/phase so GMVibes
    // can render workflow progress without a fetch-diff.
    case workflowChange = "WORKFLOW_CHANGE"
    // v22 — durable rows: the portable-kbite verbs. Export is a read and
    // never events; import/delete are content mutations.
    case kbiteImport = "KBITE_IMPORT"
    case kbiteDelete = "KBITE_DELETE"
    /// A payload-borne write named a Claude conversation that no
    /// claude_session_binding row resolves, from a repo the daemon KNOWS.
    /// Durable and deliberately noisy: refusing such a write silently is the
    /// failure mode session-bound attribution exists to remove, so dead
    /// capture leaves a row saying so. An unknown repo never reaches here —
    /// it is refused without an event, because a hook firing in somebody
    /// else's repo is normal.
    case hookUnbound = "HOOK_UNBOUND"
    /// The daemon had to invent an agent_registration because a write
    /// arrived for an agent_id nobody had registered. The row is created
    /// from the payload rather than the write being dropped, and this event
    /// is what keeps the invention visible: it means the spawner never
    /// registered.
    case agentUnregistered = "AGENT_UNREGISTERED"
    /// Ephemeral broadcast only (id 0, never a daemon_event row, never a
    /// replay cursor) — emitted by MemoryWatcher when a prompt's memory/
    /// directory changes on disk.
    case promptMemoryChange = "PROMPT_MEMORY_CHANGED"
    /// Ephemeral broadcast only (id 0, never a daemon_event row, never a
    /// replay cursor) — emitted when an instance repo's HEAD changes on disk.
    /// Payload: {"instance_uuid", "head_state", "current_branch"|null,
    ///           "current_session_code"|null}; subject_uuid = the instance
    /// uuid. On reconnect ask INSTANCE_CURRENT_SESSION once rather than
    /// replaying.
    case checkoutChange = "CHECKOUT_CHANGE"
}

/// The four registry levels a kbite can be activated at. rawValue drives the
/// `{scope}_active_kbite` / `{scope}_uuid` table and column names — the only
/// way dynamic SQL identifiers are ever built (enum-bound, no injection).
public enum KbiteScope: String, Codable, Hashable, CaseIterable, Sendable {
    case project
    case instance
    case session
    case prompt
}

/// Where a KBITE_KEYWORD_TAG attach/detach lands: the kbite-level vocabulary
/// junction or the per-resource-file junction.
public enum KeywordTagLevel: String, Codable, Hashable, CaseIterable, Sendable {
    case kbite
    case file
}

public enum ChangeKind: String, Codable, Hashable, CaseIterable, Sendable {
    case edit
    case create
    case delete
    case rename
}

/// Prompt lifecycle v2. Transitions are forward-only and adjacent-only, with
/// exactly one skip edge (reviewing is optional):
/// draft → clarifying → architecting → implementing → reviewing → done
///                                          └───────── skip ───────↗
/// Legacy note: the old terminal `clarified` was mapped to `done` by m0002.
public enum PromptStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case draft
    case clarifying
    case architecting
    case implementing
    case reviewing
    case done

    /// The legal next states as an explicit set, so the one skip edge is
    /// stated rather than hidden in a permissive switch. Gate coupling
    /// (backing summary requirements) lives in Store.setPromptStatus.
    public var allowedNext: Set<PromptStatus> {
        switch self {
        case .draft: return [.clarifying]
        case .clarifying: return [.architecting]
        case .architecting: return [.implementing]
        case .implementing: return [.reviewing, .done]
        case .reviewing: return [.done]
        case .done: return []
        }
    }
}

/// Clarification summary lifecycle: building → answering → complete, with one
/// backward revision edge (complete → answering, the `reopen` verb) so an
/// answer discovered wrong during architecting stays fixable db-natively.
public enum ClarificationStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case building
    case answering
    case complete

    public var allowedNext: Set<ClarificationStatus> {
        switch self {
        case .building: return [.answering]
        case .answering: return [.complete]
        case .complete: return [.answering]
        }
    }
}

/// One clarification row's answer state.
public enum ClarificationRowStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case open
    case answered
    case skipped
}

/// Architecture summary lifecycle: drafting → proposed → approved, with one
/// backward revision edge (proposed → drafting, the `revise` verb). approved
/// is terminal and unlocks the prompt's architecting → implementing gate.
public enum ArchitectureStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case drafting
    case proposed
    case approved

    public var allowedNext: Set<ArchitectureStatus> {
        switch self {
        case .drafting: return [.proposed]
        case .proposed: return [.approved, .drafting]
        case .approved: return []
        }
    }
}

/// Fidelity of an architecture_general_change's change_code: sketch-level
/// pseudo code, near-code draft, or drop-in actual code.
public enum ChangeDepth: String, Codable, Hashable, CaseIterable, Sendable {
    case pseudo
    case draft
    case actual
}

/// The daemon_config key space is enum-bound — an unknown key is BAD_REQUEST,
/// keeping config a typed subsystem rather than a free-form bag.
public enum ConfigKey: String, Codable, Hashable, CaseIterable, Sendable {
    case ckfsRoot = "ckfs_root"
    case kbiteRoot = "kbite_root"
    case kbiteOpenRoot = "kbite_open_root"
    case kbiteDigestedRoot = "kbite_digested_root"
}

/// Column-only since v7: session.status was retired from the wire (every live
/// row read 'active' forever; checked-out state is git-derived via
/// SESSION_RESOLVE). The enum documents the column's legal values.
public enum SessionStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case active
    case closed
}

/// Exploration report lifecycle: exploring → complete, with one backward
/// revision edge (complete → exploring, the `reopen` verb) — explore is the
/// most re-run report (resume, team fallback), so re-runs update the same
/// summary db-natively (last-run-wins, like the file world it replaces).
public enum ExplorationStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case exploring
    case complete

    public var allowedNext: Set<ExplorationStatus> {
        switch self {
        case .exploring: return [.complete]
        case .complete: return [.exploring]
        }
    }
}

/// Review report lifecycle: reviewing → complete, with the same backward
/// revision edge as ExplorationStatus. Named ReviewSummaryStatus so it can't
/// be confused with ReviewFindingStatus (the per-finding resolution machine).
public enum ReviewSummaryStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case reviewing
    case complete

    public var allowedNext: Set<ReviewSummaryStatus> {
        switch self {
        case .reviewing: return [.complete]
        case .complete: return [.reviewing]
        }
    }
}

/// What an exploration finding is about. `keyFile` (m0025) is the merged
/// exploration_key_file shape: a path-anchored finding with empty body.
public enum ExplorationFindingKind: String, Codable, Hashable, CaseIterable, Sendable {
    case persistenceModel = "persistence_model"
    case implementationPattern = "implementation_pattern"
    case existingFunctionality = "existing_functionality"
    case scopeCreepRisk = "scope_creep_risk"
    case generalRelevantChange = "general_relevant_change"
    case keyFile = "key_file"
    case other
}

/// Per-agent exploration summary vocabulary (m0025). The four methodology
/// personas plus `general` (inline/rpi runs) and `synthesis` — the
/// prompt-level seal row the primary completes last (its complete refuses
/// while any finding across the prompt is unranked). CHECKless in the db;
/// this registry is the validity surface.
public enum ExplorationAgentType: String, Codable, Hashable, CaseIterable, Sendable {
    case aggressive
    case conservative
    case pragmatic
    case alternative
    case general
    case synthesis
}

/// What a review finding is about.
public enum ReviewFindingKind: String, Codable, Hashable, CaseIterable, Sendable {
    case correctnessBug = "correctness_bug"
    case specDeviation = "spec_deviation"
    case regressionRisk = "regression_risk"
    case security
    case simplification
    case other
}

/// The review's overall verdict, carried only by REVIEW_COMPLETE.
public enum ReviewVerdict: String, Codable, Hashable, CaseIterable, Sendable {
    case approved
    case approvedWithNits = "approved_with_nits"
    case changesRequested = "changes_requested"
}

/// Per-finding resolution, recorded during the fix loop (which runs AFTER the
/// summary completes — the deliberate inversion of the clarify child-lock).
/// open → fixed | accepted | wont_fix, plus lateral correction edges among the
/// resolved values; never back to open.
public enum ReviewFindingStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case open
    case fixed
    case accepted
    case wontFix = "wont_fix"

    public var allowedNext: Set<ReviewFindingStatus> {
        switch self {
        case .open: return [.fixed, .accepted, .wontFix]
        case .fixed: return [.accepted, .wontFix]
        case .accepted: return [.fixed, .wontFix]
        case .wontFix: return [.fixed, .accepted]
        }
    }
}

/// One (finding, rating) pair of a batch rank. Ratings run 0–999: 0 is an
/// absolute critical finding, 999 an always-false-positive tombstone; the
/// consumption threshold sits at 100.
public struct FindingRating: Codable, Hashable, Sendable {
    public let findingUuid: String
    public let rating: Int

    public init(findingUuid: String, rating: Int) {
        self.findingUuid = findingUuid
        self.rating = rating
    }
}

// MARK: - HELLO

public struct Hello: Codable, Hashable, Sendable {
    public let clientName: String
    public let pid: Int32

    public init(clientName: String, pid: Int32) {
        self.clientName = clientName
        self.pid = pid
    }
}

public struct HelloAck: Codable, Hashable, Sendable {
    public let daemonPid: Int32
    public let protocolVersion: Int

    public init(daemonPid: Int32, protocolVersion: Int) {
        self.daemonPid = daemonPid
        self.protocolVersion = protocolVersion
    }
}

// MARK: - PING

public struct PingRequest: Codable, Hashable, Sendable {
    public init() {}
}

public struct PingResponse: Codable, Hashable, Sendable {
    public let daemonPid: Int32
    public let protocolVersion: Int
    public let buildSha: String
    public let buildDate: String
    public let startedAt: String
    public let uptimeSeconds: Int

    public init(
        daemonPid: Int32,
        protocolVersion: Int,
        buildSha: String,
        buildDate: String,
        startedAt: String,
        uptimeSeconds: Int
    ) {
        self.daemonPid = daemonPid
        self.protocolVersion = protocolVersion
        self.buildSha = buildSha
        self.buildDate = buildDate
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - STATUS

public struct StatusRequest: Codable, Hashable, Sendable {
    public init() {}
}

/// One table's row count. An array of pairs rather than [String: Int] because
/// the coder key strategies rewrite dictionary String keys ("prompt_artifact"
/// would decode as "promptArtifact"); an array is immune and stays sorted.
public struct TableCount: Codable, Hashable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct StatusResponse: Codable, Hashable, Sendable {
    public let daemonPid: Int32
    public let protocolVersion: Int
    public let socketPath: String
    public let dbPath: String
    public let schemaVersion: Int
    /// Row census only — MUST NOT be used as an event cursor; use
    /// `lastEventId` for that.
    public let tableCounts: [TableCount]
    /// The real event-log horizon: highest daemon_event.id at status time.
    public let lastEventId: Int64
    public let startedAt: String
    public let uptimeSeconds: Int

    public init(
        daemonPid: Int32,
        protocolVersion: Int,
        socketPath: String,
        dbPath: String,
        schemaVersion: Int,
        tableCounts: [TableCount],
        lastEventId: Int64,
        startedAt: String,
        uptimeSeconds: Int
    ) {
        self.daemonPid = daemonPid
        self.protocolVersion = protocolVersion
        self.socketPath = socketPath
        self.dbPath = dbPath
        self.schemaVersion = schemaVersion
        self.tableCounts = tableCounts
        self.lastEventId = lastEventId
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - SHUTDOWN

public struct ShutdownRequest: Codable, Hashable, Sendable {
    public init() {}
}

public struct ShutdownResponse: Codable, Hashable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

// MARK: - SUBSCRIBE / EVENT

public struct Subscribe: Codable, Hashable, Sendable {
    /// Replay cursor: daemon_event.id of the last event the subscriber has
    /// seen. Events with id > since_id are replayed before live streaming
    /// begins. nil = live-only from now.
    public let sinceId: Int64?

    public init(sinceId: Int64? = nil) {
        self.sinceId = sinceId
    }
}

public struct SubscribeAck: Codable, Hashable, Sendable {
    /// The replay horizon: highest daemon_event.id at subscribe time. Replayed
    /// EVENT lines (ids ≤ this) follow the ack, then live events stream.
    public let lastEventId: Int64
    public let replayCount: Int

    public init(lastEventId: Int64, replayCount: Int) {
        self.lastEventId = lastEventId
        self.replayCount = replayCount
    }
}

/// Unsolicited daemon → subscriber notification mirroring a daemon_event row.
/// `id` is the durable reconnect cursor (created_at is seconds-precision and
/// ties — display/coarse filter only, never a cursor). `kind` is a raw string
/// so rows with kinds added later never break older clients.
public struct EventNotification: Codable, Hashable, Sendable {
    public let id: Int64
    public let kind: String
    public let subjectUuid: String?
    public let payload: String?
    public let createdAt: String

    public var eventKind: DaemonEventKind? { DaemonEventKind(rawValue: kind) }

    public init(id: Int64, kind: String, subjectUuid: String? = nil, payload: String? = nil, createdAt: String) {
        self.id = id
        self.kind = kind
        self.subjectUuid = subjectUuid
        self.payload = payload
        self.createdAt = createdAt
    }
}

// MARK: - BACKUP

public struct BackupRequest: Codable, Hashable, Sendable {
    public init() {}
}

public struct BackupResponse: Codable, Hashable, Sendable {
    public let backupPath: String
    public let sizeBytes: Int64

    public init(backupPath: String, sizeBytes: Int64) {
        self.backupPath = backupPath
        self.sizeBytes = sizeBytes
    }
}

// MARK: - Context blocks

/// Context blocks let the daemon lazily ensure the project → instance →
/// session chain exists. Where the ckfs already carries a uuid, the caller
/// passes it so the db row reuses it (trivial db ↔ ckfs joins). Optional
/// kbite_codes seed that level's active-kbite registry at CREATE time only —
/// mirroring gmcc_session_startup.sh's inherit_kbite (existing rows are never
/// re-seeded; a child created without codes copies its parent's junctions).

public struct ProjectContext: Codable, Hashable, Sendable {
    public let gitRepoName: String
    public let code: String
    public let name: String
    public let ckfsRelativeStoragePath: String
    public let uuid: String?
    public let kbiteCodes: [String]?

    public init(
        gitRepoName: String,
        code: String,
        name: String,
        ckfsRelativeStoragePath: String,
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.gitRepoName = gitRepoName
        self.code = code
        self.name = name
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

public struct InstanceContext: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let absoluteFileSystemPath: String
    public let ckfsRelativeStoragePath: String
    public let uuid: String?
    public let kbiteCodes: [String]?

    public init(
        code: String,
        name: String,
        absoluteFileSystemPath: String,
        ckfsRelativeStoragePath: String,
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.code = code
        self.name = name
        self.absoluteFileSystemPath = absoluteFileSystemPath
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

public struct SessionContext: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let backstory: String
    public let goal: String
    public let ckfsRelativeStoragePath: String
    public let uuid: String?
    public let kbiteCodes: [String]?

    public init(
        code: String,
        name: String,
        backstory: String = "",
        goal: String = "",
        ckfsRelativeStoragePath: String,
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

// MARK: - CONTEXT_ENSURE / CONTEXT_GET

public struct ContextEnsureRequest: Codable, Hashable, Sendable {
    public let project: ProjectContext
    public let instance: InstanceContext
    public let session: SessionContext
    /// Claude Code's conversation uuid, from the SessionStart payload. When
    /// present the daemon pins it to the ensured session in
    /// claude_session_binding — the binding every hook write resolves
    /// through.
    ///
    /// IT RIDES THIS MESSAGE ON PURPOSE, rather than getting a verb of its
    /// own: SessionStart already calls `gm context ensure`, so the binding
    /// costs no second process and cannot be forgotten independently of the
    /// call that creates the session it points at. The insert is
    /// INSERT OR IGNORE against a UNIQUE index, so re-running is a no-op and
    /// pin-once is a schema fact rather than a branch a caller can skip.
    public let claudeSessionId: String?

    public init(
        project: ProjectContext,
        instance: InstanceContext,
        session: SessionContext,
        claudeSessionId: String? = nil
    ) {
        self.project = project
        self.instance = instance
        self.session = session
        self.claudeSessionId = claudeSessionId
    }
}

public struct ContextEnsureResponse: Codable, Hashable, Sendable {
    public let projectUuid: String
    public let instanceUuid: String
    public let sessionUuid: String
    public let createdProject: Bool
    public let createdInstance: Bool
    public let createdSession: Bool
    /// How many `claude_session_binding` rows exist for this session.
    ///
    /// CAPTURE HEALTH, AND THE ONLY WAY THE MCP CAN SEE IT. Zero means no Claude
    /// conversation is bound to this gmcc session, so the PostToolUse hook has
    /// nothing to attribute against and file-change capture is silently OFF. A
    /// stdio MCP server is handed only CLAUDE_PROJECT_DIR — it cannot read
    /// `claude_session_id` for itself — so without this count it cannot tell a
    /// healthy session from a dead one, and the failure stays invisible exactly
    /// the way it did before.
    ///
    /// OPTIONAL BY CONSTRUCTION: an additive optional field on an existing
    /// message does not bump `GMCCWireProtocol.version`, so an older client
    /// decodes this response unchanged and GMVibes' pinned kit keeps working.
    public let claudeSessionBindingCount: Int?

    public init(
        projectUuid: String,
        instanceUuid: String,
        sessionUuid: String,
        createdProject: Bool,
        createdInstance: Bool,
        createdSession: Bool,
        claudeSessionBindingCount: Int? = nil
    ) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.createdProject = createdProject
        self.createdInstance = createdInstance
        self.createdSession = createdSession
        self.claudeSessionBindingCount = claudeSessionBindingCount
    }
}

/// Read-only resolution of the current gmcc environment — never creates rows.
public struct ContextGetRequest: Codable, Hashable, Sendable {
    public let projectCode: String
    public let instanceName: String
    public let sessionCode: String

    public init(projectCode: String, instanceName: String, sessionCode: String) {
        self.projectCode = projectCode
        self.instanceName = instanceName
        self.sessionCode = sessionCode
    }
}

public struct ContextGetResponse: Codable, Hashable, Sendable {
    public let projectUuid: String?
    public let instanceUuid: String?
    public let sessionUuid: String?
    /// Session-level active kbite codes, resolved from the junction table.
    public let kbiteCodes: [String]

    public init(projectUuid: String?, instanceUuid: String?, sessionUuid: String?, kbiteCodes: [String]) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.kbiteCodes = kbiteCodes
    }
}

// MARK: - PROJECT_LIST / INSTANCE_LIST / SESSION_LIST

/// Enumerate all projects — the entry point of the Landing browse chain.
public struct ProjectListRequest: Codable, Hashable, Sendable {
    public init() {}
}

public struct ProjectListResponse: Codable, Hashable, Sendable {
    public let projects: [ProjectRow]

    public init(projects: [ProjectRow]) {
        self.projects = projects
    }
}

/// PROJECT_UPDATE — the only project-level mutation. `primaryProjectBranch`
/// is Optional so the request shape can grow more settable fields without a
/// wire bump; an all-nil request is EMPTY_UPDATE, never a silent no-op.
public struct ProjectUpdateRequest: Codable, Hashable, Sendable {
    public let projectUuid: String
    public let expectedVersion: Int64
    public let primaryProjectBranch: String?

    public init(
        projectUuid: String,
        expectedVersion: Int64,
        primaryProjectBranch: String? = nil
    ) {
        self.projectUuid = projectUuid
        self.expectedVersion = expectedVersion
        self.primaryProjectBranch = primaryProjectBranch
    }
}

/// The refreshed row, so a caller never re-reads to learn the new version.
public struct ProjectResponse: Codable, Hashable, Sendable {
    public let project: ProjectRow

    public init(project: ProjectRow) {
        self.project = project
    }
}

/// Enumerate instances. `projectUuid` is an optional filter — nil lists every
/// instance (rows carry their parent uuid); a supplied-but-unknown uuid is
/// NOT_FOUND, never a silent empty list.
public struct InstanceListRequest: Codable, Hashable, Sendable {
    public let projectUuid: String?

    public init(projectUuid: String? = nil) {
        self.projectUuid = projectUuid
    }
}

public struct InstanceListResponse: Codable, Hashable, Sendable {
    public let instances: [InstanceRow]

    public init(instances: [InstanceRow]) {
        self.instances = instances
    }
}

/// Enumerate sessions. Same optional-filter contract as INSTANCE_LIST.
public struct SessionListRequest: Codable, Hashable, Sendable {
    public let instanceUuid: String?

    public init(instanceUuid: String? = nil) {
        self.instanceUuid = instanceUuid
    }
}

public struct SessionListResponse: Codable, Hashable, Sendable {
    public let sessions: [SessionStub]

    public init(sessions: [SessionStub]) {
        self.sessions = sessions
    }
}

// MARK: - SESSION_GET / SESSION_UPDATE

public struct SessionGetRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String

    public init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

public struct SessionGetResponse: Codable, Hashable, Sendable {
    public let session: SessionRow
    public let prompts: [PromptStub]
    public let changeSummary: ChangeSummary
    /// Per-prompt change summaries (promptUuid nil = unattributed changes).
    /// Empty until file changes carry prompt attribution — run context is
    /// deferred from MVP, so entries may only appear via --prompt-uuid.
    public let promptChanges: [PromptChangeSummary]

    public init(
        session: SessionRow,
        prompts: [PromptStub],
        changeSummary: ChangeSummary,
        promptChanges: [PromptChangeSummary]
    ) {
        self.session = session
        self.prompts = prompts
        self.changeSummary = changeSummary
        self.promptChanges = promptChanges
    }
}

/// Optimistic-concurrency guarded partial update of session-owned scalars.
/// nil fields are left unchanged.
public struct SessionUpdateRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    public let expectedVersion: Int64
    public let name: String?
    public let backstory: String?
    public let goal: String?
    /// v21-era additive OPTIONAL fields (no bump needed): manual override of
    /// the activation claim that PROMPT_SET_STATUS normally maintains for the
    /// calling Claude instance. activePromptUuid claims for clientKey;
    /// clearActivePrompt releases clientKey's claim. Exactly one of the pair.
    public let activePromptUuid: String?
    public let clearActivePrompt: Bool?
    /// The calling instance's identity (gm resolves it from process
    /// ancestry); required when either activation field is set.
    public let clientKey: String?

    public init(
        sessionUuid: String,
        expectedVersion: Int64,
        name: String? = nil,
        backstory: String? = nil,
        goal: String? = nil,
        activePromptUuid: String? = nil,
        clearActivePrompt: Bool? = nil,
        clientKey: String? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.expectedVersion = expectedVersion
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.activePromptUuid = activePromptUuid
        self.clearActivePrompt = clearActivePrompt
        self.clientKey = clientKey
    }
}

// MARK: - PROMPT_CREATE / PROMPT_LIST / PROMPT_GET

public struct PromptCreateRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    /// Optional ckfs uuid pass-through (db ↔ ckfs join bridge).
    public let uuid: String?
    /// Defaults to "p{seq}" when nil.
    public let code: String?
    public let name: String
    public let backstory: String
    public let goal: String
    public let detail: String
    public let command: String?
    public let ckfsRelativeStoragePath: String?

    public init(
        sessionUuid: String,
        uuid: String? = nil,
        code: String? = nil,
        name: String,
        backstory: String = "",
        goal: String = "",
        detail: String = "",
        command: String? = nil,
        ckfsRelativeStoragePath: String? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.uuid = uuid
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.detail = detail
        self.command = command
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
    }
}

/// `sessionUuid` is an optional filter (same contract as INSTANCE_LIST /
/// SESSION_LIST): nil lists every prompt in the db (stubs carry their parent
/// session uuid); a supplied-but-unknown uuid is NOT_FOUND, never a silent
/// empty list.
public struct PromptListRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String?
    /// When true each stub carries its `reports` enrichment block (one call
    /// replaces the per-prompt CLARIFY_GET/ARCH_GET fan-out). Optional so a
    /// v8 client omitting it decodes as false.
    public let withReports: Bool?

    public init(sessionUuid: String? = nil, withReports: Bool? = nil) {
        self.sessionUuid = sessionUuid
        self.withReports = withReports
    }
}

public struct PromptListResponse: Codable, Hashable, Sendable {
    public let prompts: [PromptStub]

    public init(prompts: [PromptStub]) {
        self.prompts = prompts
    }
}

public struct PromptGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

public struct PromptGetResponse: Codable, Hashable, Sendable {
    public let prompt: PromptRow
    public let artifacts: [ArtifactRow]
    public let kbiteCodes: [String]
    public let changeSummary: ChangeSummary

    public init(prompt: PromptRow, artifacts: [ArtifactRow], kbiteCodes: [String], changeSummary: ChangeSummary) {
        self.prompt = prompt
        self.artifacts = artifacts
        self.kbiteCodes = kbiteCodes
        self.changeSummary = changeSummary
    }
}

// MARK: - PROMPT_UPDATE_CONTENT / PROMPT_SET_STATUS

/// Draft-only edit of exactly the STAY TRUE triple (backstory/goal/detail).
/// The daemon rejects with CONTENT_LOCKED once the prompt leaves draft.
public struct PromptUpdateContentRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let expectedVersion: Int64
    public let backstory: String?
    public let goal: String?
    public let detail: String?

    public init(
        promptUuid: String,
        expectedVersion: Int64,
        backstory: String? = nil,
        goal: String? = nil,
        detail: String? = nil
    ) {
        self.promptUuid = promptUuid
        self.expectedVersion = expectedVersion
        self.backstory = backstory
        self.goal = goal
        self.detail = detail
    }
}

public struct PromptSetStatusRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let expectedVersion: Int64
    public let status: PromptStatus
    /// v21-era additive OPTIONAL (no bump): the calling Claude instance's
    /// identity, resolved from process ancestry by gm. Entering implementing
    /// claims an activation for this key; done releases the prompt's claim.
    public let clientKey: String?

    public init(
        promptUuid: String,
        expectedVersion: Int64,
        status: PromptStatus,
        clientKey: String? = nil
    ) {
        self.promptUuid = promptUuid
        self.expectedVersion = expectedVersion
        self.status = status
        self.clientKey = clientKey
    }
}

// MARK: - ARTIFACT_ADD / ARTIFACT_LIST

/// Register a file pointer for a bot-phase memory/ file. Content stays in the
/// file; the daemon stores only the pointer.
public struct ArtifactAddRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let filePath: String
    public let note: String?

    public init(promptUuid: String, filePath: String, note: String? = nil) {
        self.promptUuid = promptUuid
        self.filePath = filePath
        self.note = note
    }
}

public struct ArtifactListRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

public struct ArtifactListResponse: Codable, Hashable, Sendable {
    public let artifacts: [ArtifactRow]

    public init(artifacts: [ArtifactRow]) {
        self.artifacts = artifacts
    }
}

// MARK: - PROMPT_DIAGRAM_QUALIFY / _GET / _LIST

/// A prompt's standing reading of one rendered diagram.
///
/// The three render columns are the staleness evidence. `renderFingerprint`
/// is a serialized `DiagramRenderFingerprint` carried as opaque JSON text:
/// the wire never re-shapes it, so a reader compares it against the sidecar
/// beside a current PNG byte-for-byte and learns whether this qualification
/// still describes the picture it was written about.
public struct PromptQualifiedDiagramRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let promptUuid: String
    public let diagramUuid: String
    public let renderedPath: String
    public let renderedRevision: Int64
    public let renderFingerprint: String
    public let qualification: String
    public let version: Int64
    public let createdAt: String
    public let updatedAt: String

    public init(uuid: String, promptUuid: String, diagramUuid: String,
                renderedPath: String, renderedRevision: Int64,
                renderFingerprint: String, qualification: String,
                version: Int64, createdAt: String, updatedAt: String) {
        self.uuid = uuid
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
        self.renderedPath = renderedPath
        self.renderedRevision = renderedRevision
        self.renderFingerprint = renderFingerprint
        self.qualification = qualification
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Record (or replace) what this prompt makes of this diagram. UPSERT on
/// (prompt, diagram): no expected_version, because the pair is the identity
/// and the newer reading is by definition the one that stands.
public struct PromptDiagramQualifyRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let diagramUuid: String
    public let renderedPath: String
    public let renderedRevision: Int64
    public let renderFingerprint: String
    public let qualification: String

    public init(promptUuid: String, diagramUuid: String, renderedPath: String,
                renderedRevision: Int64, renderFingerprint: String,
                qualification: String) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
        self.renderedPath = renderedPath
        self.renderedRevision = renderedRevision
        self.renderFingerprint = renderFingerprint
        self.qualification = qualification
    }
}

/// One qualification. With `diagramUuid` it is the pair; without, it is the
/// prompt's only qualification — and an ambiguous ask (several exist) is a
/// badRequest pointing at the list verb rather than an arbitrary pick.
public struct PromptDiagramGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let diagramUuid: String?

    public init(promptUuid: String, diagramUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
    }
}

public struct PromptDiagramListRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

public struct PromptDiagramListResponse: Codable, Hashable, Sendable {
    public let qualifications: [PromptQualifiedDiagramRow]

    public init(qualifications: [PromptQualifiedDiagramRow]) {
        self.qualifications = qualifications
    }
}

// MARK: - FILE_CHANGE_ADD

public struct ChangeRange: Codable, Hashable, Sendable {
    public let lineStart: Int
    public let lineEnd: Int
    public let changedContent: String?

    public init(lineStart: Int, lineEnd: Int, changedContent: String? = nil) {
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.changedContent = changedContent
    }
}

/// The primary high-frequency message. Carries full context blocks so the
/// ensure chain can run lazily — deliberately NOT slimmed to uuid addressing
/// this prompt (no call-order coupling for gm; revisit when the yamls and
/// their context source go away in prompt 2).
/// The `file_change.origin` vocabulary — ONE declaration, four consumers:
/// the server-side guard in FileChangeRepository.add, the gm writers that
/// stamp it, this message's documentation, and the
/// `agentics.enums.file_change_origin` dope entity that mirrors it.
///
/// The column is `TEXT NOT NULL DEFAULT 'hook'` with NO CHECK constraint, so
/// THIS LIST IS THE CONSTRAINT: extending the dope enum without extending
/// this list makes every write of the new value throw, and a caller that
/// swallows errors records nothing at all. Extend both together.
///
/// The column having no CHECK is also what lets the list SHRINK: rows written
/// under a wider vocabulary keep their stored value and still read back, while
/// a value absent here can no longer be written.
public enum FileChangeOrigin {
    /// PostToolUse Edit|Write|NotebookEdit — exact paths and exact
    /// structuredPatch ranges, straight off the payload.
    public static let hook = "hook"
    /// Recorded by hand through `gm file-change add` or the pen tool.
    public static let manual = "manual"
    /// INFERRED from the paths a Bash command NAMED (the write allowlist).
    /// Its own member rather than a `hook` row with tool_name=Bash: an
    /// inference must never be indistinguishable from an exact
    /// structuredPatch row, and every consumer can filter on it.
    public static let command = "command"

    /// The accepted set, in documentation order. The guard's error detail is
    /// generated from this — never hand-written.
    public static let all: [String] = [hook, manual, command]

    /// `hook|manual|command` — for help text and error details.
    public static var vocabulary: String { all.joined(separator: "|") }
}

public struct FileChangeAdd: Codable, Hashable, Sendable {
    public let project: ProjectContext
    public let instance: InstanceContext
    public let session: SessionContext
    public let promptUuid: String?
    public let relativePath: String
    public let changeKind: ChangeKind
    public let ranges: [ChangeRange]
    /// When autoAttribute is true and promptUuid is nil, the daemon resolves
    /// the prompt itself. OPT-IN so the long-standing "omitted prompt means
    /// deliberately session-scoped" semantic stays intact for every other
    /// caller; the PostToolUse bookkeeping hook is the intended caller.
    ///
    /// THERE IS NO clientKey ON THIS MESSAGE, and its absence is the design.
    /// A hook-origin write must resolve through the claude_session_binding,
    /// never through the ClientKey activation ladder — process ancestry
    /// cannot tell one sibling subagent from another, which is what made hook
    /// attribution wrong. Removing the field rather than agreeing not to send
    /// it makes that split STRUCTURAL: no field remains through which a hook
    /// write could reach the ladder.
    public let autoAttribute: Bool?
    /// Agent identity is SELF-REPORTED (nothing on the transport can
    /// distinguish sibling subagents); origin is one of `FileChangeOrigin.all`
    /// (nil → hook, the db default); workflow_phase is NEVER taken from the
    /// caller — the daemon stamps it from the attributed prompt's active
    /// bot_workflow.
    public let agentId: String?
    public let agentName: String?
    public let origin: String?
    /// The PostToolUse payload, one field per column rather than a blob so
    /// every axis stays queryable. All OPTIONAL: the manual path carries none
    /// of them, and a row with no tool call behind it has no tool_use_id.
    ///
    /// claudeTurnId is THE naming trap here. The payload field is called
    /// `prompt_id`, but it is Claude Code's TURN id and has nothing to do
    /// with a gmcc prompt uuid — hence the name it carries on this message.
    ///
    /// toolUseId is the idempotency key, paired server-side with the resolved
    /// session_file: one `sed -i a b c` is one tool_use_id and three rows, so
    /// the unit is (tool call, file). A replay returns the EXISTING row with
    /// `deduplicated` set rather than writing a second one.
    public let claudeSessionId: String?
    public let claudeTurnId: String?
    public let toolUseId: String?
    public let toolName: String?
    public let agentType: String?
    public let permissionMode: String?
    public let durationMs: Int?
    public let transcriptPath: String?

    public init(
        project: ProjectContext,
        instance: InstanceContext,
        session: SessionContext,
        promptUuid: String? = nil,
        relativePath: String,
        changeKind: ChangeKind,
        ranges: [ChangeRange],
        autoAttribute: Bool? = nil,
        agentId: String? = nil,
        agentName: String? = nil,
        origin: String? = nil,
        claudeSessionId: String? = nil,
        claudeTurnId: String? = nil,
        toolUseId: String? = nil,
        toolName: String? = nil,
        agentType: String? = nil,
        permissionMode: String? = nil,
        durationMs: Int? = nil,
        transcriptPath: String? = nil
    ) {
        self.project = project
        self.instance = instance
        self.session = session
        self.promptUuid = promptUuid
        self.relativePath = relativePath
        self.changeKind = changeKind
        self.ranges = ranges
        self.autoAttribute = autoAttribute
        self.agentId = agentId
        self.agentName = agentName
        self.origin = origin
        self.claudeSessionId = claudeSessionId
        self.claudeTurnId = claudeTurnId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.agentType = agentType
        self.permissionMode = permissionMode
        self.durationMs = durationMs
        self.transcriptPath = transcriptPath
    }
}

public struct FileChangeAddResponse: Codable, Hashable, Sendable {
    public let sessionFileUuid: String
    public let fileChangeUuid: String
    public let rangeUuids: [String]
    /// Set when this (tool_use_id, file) pair was ALREADY recorded: the uuids
    /// above are the existing row's, no event was appended and the session
    /// was not touched. An explicit already-recorded SUCCESS, so a replayed
    /// payload is never an error to the hook and never a second edit to a
    /// subscriber. Absent means a row was written.
    public let deduplicated: Bool?

    public init(
        sessionFileUuid: String,
        fileChangeUuid: String,
        rangeUuids: [String],
        deduplicated: Bool? = nil
    ) {
        self.sessionFileUuid = sessionFileUuid
        self.fileChangeUuid = fileChangeUuid
        self.rangeUuids = rangeUuids
        self.deduplicated = deduplicated
    }
}

// MARK: - FILE_CHANGE_LIST

public struct FileChangeListRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String?
    public let promptUuid: String?
    public let relativePath: String?
    public let limit: Int?

    public init(sessionUuid: String? = nil, promptUuid: String? = nil, relativePath: String? = nil, limit: Int? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.relativePath = relativePath
        self.limit = limit
    }
}

public struct FileChangeListResponse: Codable, Hashable, Sendable {
    public let changes: [FileChangeRow]

    public init(changes: [FileChangeRow]) {
        self.changes = changes
    }
}

// MARK: - KBITE_LIST / KBITE_ADD / KBITE_REMOVE

/// Registered kbites at a scope, resolved through the inheritance chain at
/// READ time (owner's own junction plus every ancestor's) — correct even for
/// kbites added after the child row was created. `all: true` ignores scope
/// and returns every kbite row in the db (the cleanup drift-check listing).
public struct KbiteListRequest: Codable, Hashable, Sendable {
    public let scope: KbiteScope
    public let ownerUuid: String
    public let all: Bool?

    public init(scope: KbiteScope, ownerUuid: String, all: Bool? = nil) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.all = all
    }
}

public struct KbiteListResponse: Codable, Hashable, Sendable {
    public let kbites: [KbiteRef]

    public init(kbites: [KbiteRef]) {
        self.kbites = kbites
    }
}

/// Explicit-only registration (v11 inheritance model — never auto-added).
/// Db-only — the db is the sole kbite registry.
/// Idempotent; `added` is false when the junction already existed.
public struct KbiteAddRequest: Codable, Hashable, Sendable {
    public let scope: KbiteScope
    public let ownerUuid: String
    public let code: String

    public init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

public struct KbiteAddResponse: Codable, Hashable, Sendable {
    public let kbiteUuid: String
    public let code: String
    public let added: Bool

    public init(kbiteUuid: String, code: String, added: Bool) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.added = added
    }
}

public struct KbiteRemoveRequest: Codable, Hashable, Sendable {
    public let scope: KbiteScope
    public let ownerUuid: String
    public let code: String

    public init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

public struct KbiteRemoveResponse: Codable, Hashable, Sendable {
    public let removed: Bool

    public init(removed: Bool) {
        self.removed = removed
    }
}

// MARK: - KBITE_MAW_OPEN

/// Filesystem skeleton only — no db rows (maws are not tracked in the db).
/// The client resolves $GMCC_KBITE_OPEN and passes the absolute maw path; the
/// daemon never reads ckfs environment variables.
public struct KbiteMawOpenRequest: Codable, Hashable, Sendable {
    public let kbiteName: String
    public let mawPath: String

    public init(kbiteName: String, mawPath: String) {
        self.kbiteName = kbiteName
        self.mawPath = mawPath
    }
}

public struct KbiteMawOpenResponse: Codable, Hashable, Sendable {
    public let mawPath: String
    public let createdDirs: [String]
    public let createdIndex: Bool

    public init(mawPath: String, createdDirs: [String], createdIndex: Bool) {
        self.mawPath = mawPath
        self.createdDirs = createdDirs
        self.createdIndex = createdIndex
    }
}

// MARK: - KBITE_DIGEST

/// The one-step import: parse chewed artifacts under the open maw, write
/// kbite_resource / kbite_resource_file / keyword rows (db becomes canonical
/// for digested text), then delete the temporary chewed files — raw sources
/// stay on disk for re-chewing.
public struct KbiteDigestRequest: Codable, Hashable, Sendable {
    public let code: String
    public let kbiteOpenPath: String

    public init(code: String, kbiteOpenPath: String) {
        self.code = code
        self.kbiteOpenPath = kbiteOpenPath
    }
}

public struct KbiteDigestResponse: Codable, Hashable, Sendable {
    public let kbiteUuid: String
    public let resourceCount: Int
    public let fileCount: Int
    public let keywordCount: Int
    public let deletedChewedFiles: [String]

    public init(
        kbiteUuid: String,
        resourceCount: Int,
        fileCount: Int,
        keywordCount: Int,
        deletedChewedFiles: [String]
    ) {
        self.kbiteUuid = kbiteUuid
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.keywordCount = keywordCount
        self.deletedChewedFiles = deletedChewedFiles
    }
}

// MARK: - KBITE_GET / KBITE_FILE_GET

public struct KbiteGetRequest: Codable, Hashable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

/// One kbite with its resources, file STUBS (names + summaries, never
/// content), and kbite-level keywords. Content loads go through
/// KBITE_FILE_GET one file at a time.
public struct KbiteGetResponse: Codable, Hashable, Sendable {
    public let kbite: KbiteRow
    public let resources: [KbiteResourceRow]
    public let keywords: [String]

    public init(kbite: KbiteRow, resources: [KbiteResourceRow], keywords: [String]) {
        self.kbite = kbite
        self.resources = resources
        self.keywords = keywords
    }
}

public struct KbiteFileGetRequest: Codable, Hashable, Sendable {
    public let fileUuid: String

    public init(fileUuid: String) {
        self.fileUuid = fileUuid
    }
}

public struct KbiteFileGetResponse: Codable, Hashable, Sendable {
    public let file: KbiteResourceFileRow

    public init(file: KbiteResourceFileRow) {
        self.file = file
    }
}

// MARK: - KBITE_SEARCH

/// FTS5 full-text query across kbite resource files; ranked stubs, never
/// content. Empty/nil kbite_uuids searches everything.
public struct KbiteSearchRequest: Codable, Hashable, Sendable {
    public let query: String
    public let kbiteUuids: [String]?
    public let limit: Int?

    public init(query: String, kbiteUuids: [String]? = nil, limit: Int? = nil) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

public struct KbiteSearchResponse: Codable, Hashable, Sendable {
    public let hits: [KbiteSearchHit]

    public init(hits: [KbiteSearchHit]) {
        self.hits = hits
    }
}

// MARK: - SEARCH

/// The searchable row kinds. Raw values match the source table names.
/// (v9 added the five exploration/review kinds — discharging m0003's
/// explore.md/review.md deferral note.)
public enum SearchKind: String, Codable, Hashable, CaseIterable, Sendable {
    case prompt
    /// m0025: the clarification split's searchable rows. clarification /
    /// clarification_summary / exploration_key_file are RETIRED with their
    /// tables (the summary lost its text columns; key files are
    /// kind='key_file' rows inside exploration_finding).
    case clarificationQuestion = "clarification_question"
    case clarificationNote = "clarification_note"
    case architectureSummary = "architecture_summary"
    case architectureGeneralChange = "architecture_general_change"
    case architecturePersistenceChange = "architecture_persistence_change"
    case explorationSummary = "exploration_summary"
    case explorationFinding = "exploration_finding"
    case reviewSummary = "review_summary"
    case reviewFinding = "review_finding"
}

/// FTS5 full-text search over prompt/clarification/architecture text —
/// ranked stubs with prompt lineage, never full content (the SEARCH
/// counterpart of KBITE_SEARCH). nil sessionUuid = whole db; a
/// supplied-but-unknown uuid is NOT_FOUND, never a silent empty list.
/// A query with no searchable tokens is BAD_REQUEST.
public struct SearchRequest: Codable, Hashable, Sendable {
    public let query: String
    public let sessionUuid: String?
    /// nil/empty = every kind.
    public let kinds: [SearchKind]?
    /// Clamped 1…500, default 50.
    public let limit: Int?

    public init(query: String, sessionUuid: String? = nil, kinds: [SearchKind]? = nil, limit: Int? = nil) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.kinds = kinds
        self.limit = limit
    }
}

public struct SearchResponse: Codable, Hashable, Sendable {
    public let hits: [SearchHit]

    public init(hits: [SearchHit]) {
        self.hits = hits
    }
}

// MARK: - CATALOG_SEARCH

/// Tokenized OR name/code search across instances + sessions, optionally
/// scoped to one project. Returns matched sessions plus every parent
/// instance needed to group them; the client orders by created/updated.
public struct CatalogSearchRequest: Codable, Hashable, Sendable {
    public let query: String
    public let projectUuid: String?
    public let limit: Int?

    public init(query: String, projectUuid: String? = nil, limit: Int? = nil) {
        self.query = query
        self.projectUuid = projectUuid
        self.limit = limit
    }
}

public struct CatalogSearchResponse: Codable, Hashable, Sendable {
    public let instances: [InstanceRow]
    public let sessions: [SessionStub]

    public init(instances: [InstanceRow], sessions: [SessionStub]) {
        self.instances = instances
        self.sessions = sessions
    }
}

// MARK: - KBITE_KEYWORD_TAG

/// Attach or detach normalized keywords at kbite level or resource-file
/// level. Keywords are upserted into the shared vocabulary on attach.
public struct KbiteKeywordTagRequest: Codable, Hashable, Sendable {
    public let level: KeywordTagLevel
    public let targetUuid: String
    public let keywords: [String]
    public let detach: Bool

    public init(level: KeywordTagLevel, targetUuid: String, keywords: [String], detach: Bool = false) {
        self.level = level
        self.targetUuid = targetUuid
        self.keywords = keywords
        self.detach = detach
    }
}

public struct KbiteKeywordTagResponse: Codable, Hashable, Sendable {
    public let attached: Int
    public let detached: Int

    public init(attached: Int, detached: Int) {
        self.attached = attached
        self.detached = detached
    }
}

// MARK: - KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE

// The portable-kbite family (v22). Bulk data NEVER rides the wire — the 10MB
// inbound line cap forbids it. The gm CLI resolves absolute staging paths
// client-side and the daemon reads/writes db_export.json at those paths
// (the KBITE_DIGEST idiom); zip assembly, source-tree copies, and
// cold-storage moves are all CLI-side.

/// Daemon writes the scrubbed db_export.json at `dbExportPath`. `anonymize`
/// carries the CLI-resolved machine roots as prefix→placeholder rules — the
/// daemon never learns gmcc env vars exist.
public struct KbiteExportRequest: Codable, Hashable, Sendable {
    public let code: String
    public let dbExportPath: String
    public let anonymize: [KbitePrefixRule]

    public init(code: String, dbExportPath: String, anonymize: [KbitePrefixRule]) {
        self.code = code
        self.dbExportPath = dbExportPath
        self.anonymize = anonymize
    }
}

public struct KbiteExportResponse: Codable, Hashable, Sendable {
    public let kbiteUuid: String
    public let code: String
    public let resourceCount: Int
    public let fileCount: Int
    public let kbiteKeywordCount: Int
    public let fileKeywordCount: Int
    public let dbExportPath: String

    public init(
        kbiteUuid: String,
        code: String,
        resourceCount: Int,
        fileCount: Int,
        kbiteKeywordCount: Int,
        fileKeywordCount: Int,
        dbExportPath: String
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.kbiteKeywordCount = kbiteKeywordCount
        self.fileKeywordCount = fileKeywordCount
        self.dbExportPath = dbExportPath
    }
}

/// Collision policy when the archive's code already exists in the db.
/// `skip` (the CLI default) leaves the existing kbite untouched; `overwrite`
/// replaces content under the EXISTING kbite uuid so every `*_active_kbite`
/// registration survives.
public enum KbiteImportCollision: String, Codable, Hashable, CaseIterable, Sendable {
    case skip
    case overwrite
}

/// Daemon reads db_export.json at `dbExportPath`, rehydrates placeholder
/// paths via `rehydrate`, and writes rows in one transaction. Never creates
/// registration rows — `gm kbite add` stays the only registration door.
public struct KbiteImportRequest: Codable, Hashable, Sendable {
    public let dbExportPath: String
    public let onCollision: KbiteImportCollision
    public let rehydrate: [KbitePrefixRule]

    public init(dbExportPath: String, onCollision: KbiteImportCollision, rehydrate: [KbitePrefixRule]) {
        self.dbExportPath = dbExportPath
        self.onCollision = onCollision
        self.rehydrate = rehydrate
    }
}

public struct KbiteImportResponse: Codable, Hashable, Sendable {
    /// Never nil — the skip branch reports the existing kbite's uuid, the
    /// import branch the ensured one. Kept non-optional from birth:
    /// loosening a v22 field later is free, tightening never is.
    public let kbiteUuid: String
    public let code: String
    public let imported: Bool
    public let skippedExisting: Bool
    public let resourceCount: Int
    public let fileCount: Int
    public let keywordCount: Int

    public init(
        kbiteUuid: String,
        code: String,
        imported: Bool,
        skippedExisting: Bool,
        resourceCount: Int,
        fileCount: Int,
        keywordCount: Int
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.imported = imported
        self.skippedExisting = skippedExisting
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.keywordCount = keywordCount
    }
}

/// One cascading delete: resources, files, junctions, and every scope
/// registration go with the kbite row (that unregistration is the desired
/// behavior here, unlike overwrite). Orphaned shared-vocabulary keywords are
/// garbage-collected in the same transaction. daemon_event history survives.
public struct KbiteDeleteRequest: Codable, Hashable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct KbiteDeleteResponse: Codable, Hashable, Sendable {
    public let kbiteUuid: String
    public let code: String
    public let deletedResources: Int
    public let deletedFiles: Int
    public let deletedRegistrations: Int
    public let gcKeywordCount: Int

    public init(
        kbiteUuid: String,
        code: String,
        deletedResources: Int,
        deletedFiles: Int,
        deletedRegistrations: Int,
        gcKeywordCount: Int
    ) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.deletedResources = deletedResources
        self.deletedFiles = deletedFiles
        self.deletedRegistrations = deletedRegistrations
        self.gcKeywordCount = gcKeywordCount
    }
}

// MARK: - EVENT_LIST

public struct EventListRequest: Codable, Hashable, Sendable {
    /// Raw kind string (forward compat — filters on the TEXT column).
    public let kind: String?
    public let subjectUuid: String?
    public let sinceId: Int64?
    /// ISO-8601 seconds-precision Z bounds; lexicographic comparison.
    public let sinceTime: String?
    public let untilTime: String?
    public let limit: Int?

    public init(
        kind: String? = nil,
        subjectUuid: String? = nil,
        sinceId: Int64? = nil,
        sinceTime: String? = nil,
        untilTime: String? = nil,
        limit: Int? = nil
    ) {
        self.kind = kind
        self.subjectUuid = subjectUuid
        self.sinceId = sinceId
        self.sinceTime = sinceTime
        self.untilTime = untilTime
        self.limit = limit
    }
}

public struct EventListResponse: Codable, Hashable, Sendable {
    public let events: [EventNotification]

    public init(events: [EventNotification]) {
        self.events = events
    }
}

// MARK: - CLARIFY_* (v7)

public struct ClarifyOpenRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Shared response for clarify verbs that return the summary row. `created`
/// is true only when OPEN made the row (open is idempotent create-or-return
/// and never transitions the prompt).
public struct ClarifySummaryResponse: Codable, Hashable, Sendable {
    public let summary: ClarificationSummaryRow
    public let created: Bool

    public init(summary: ClarificationSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Insert a user-facing question while the summary is `building` (m0025).
/// `options` become option child rows in order; the user answers by
/// selection (junction rows) and/or typed text.
public struct ClarifyQuestionAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let question: String
    public let options: [String]?
    public let agentName: String?
    public let agentId: String?

    public init(
        summaryUuid: String,
        question: String,
        options: [String]? = nil,
        agentName: String? = nil,
        agentId: String? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.question = question
        self.options = options
        self.agentName = agentName
        self.agentId = agentId
    }
}

public struct ClarifyQuestionRowResponse: Codable, Hashable, Sendable {
    public let question: ClarificationQuestionRow

    public init(question: ClarificationQuestionRow) {
        self.question = question
    }
}

/// Insert an internal clarification note (m0025): the agent's own record of
/// what confused exploration or itself. weight uses the finding_rating
/// polarity (0 = critical). questionUuid attaches the note to an answered
/// user question after the fact.
public struct ClarifyNoteAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let body: String
    public let confusedEntityUuid: String?
    public let confusedEntityType: String?
    public let weight: Int?
    public let questionUuid: String?
    public let agentName: String?
    public let agentId: String?

    public init(
        summaryUuid: String,
        body: String,
        confusedEntityUuid: String? = nil,
        confusedEntityType: String? = nil,
        weight: Int? = nil,
        questionUuid: String? = nil,
        agentName: String? = nil,
        agentId: String? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.body = body
        self.confusedEntityUuid = confusedEntityUuid
        self.confusedEntityType = confusedEntityType
        self.weight = weight
        self.questionUuid = questionUuid
        self.agentName = agentName
        self.agentId = agentId
    }
}

public struct ClarifyNoteRowResponse: Codable, Hashable, Sendable {
    public let note: ClarificationNoteRow

    public init(note: ClarificationNoteRow) {
        self.note = note
    }
}

/// building → answering: locks the question list.
public struct ClarifySealRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Answer one question (summary must be `answering`). Revives a skipped
/// row. Pure row update — never touches the summary's version.
/// expectedVersion targets the QUESTION row. skip=true marks the row
/// skipped instead of answered. selectedOptionUuids replace the question's
/// junction rows wholesale; answerText carries a typed answer — either or
/// both satisfy "answered".
public struct ClarifyAnswerRequest: Codable, Hashable, Sendable {
    public let questionUuid: String
    public let expectedVersion: Int64
    public let answerText: String?
    public let selectedOptionUuids: [String]?
    public let skip: Bool

    public init(
        questionUuid: String,
        expectedVersion: Int64,
        answerText: String? = nil,
        selectedOptionUuids: [String]? = nil,
        skip: Bool = false
    ) {
        self.questionUuid = questionUuid
        self.expectedVersion = expectedVersion
        self.answerText = answerText
        self.selectedOptionUuids = selectedOptionUuids
        self.skip = skip
    }
}

/// complete → answering: the revision edge, as its own verb so `answer` stays
/// a pure row update (its expected_version targets a child row, not the summary).
public struct ClarifyReopenRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// answering → complete. A PURE GATE since m0025: requires every question
/// answered or skipped, validates the care package where one exists (ready,
/// non-empty intent), and writes NOTHING to the prompt row — the old
/// refined_goal→prompt.goal copy is retired; ZERO bot write doors to prompt
/// content remain (backstory/goal/detail are human input only).
public struct ClarifyFinalizeRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

public struct ClarifyFinalizeResponse: Codable, Hashable, Sendable {
    public let summary: ClarificationSummaryRow

    public init(summary: ClarificationSummaryRow) {
        self.summary = summary
    }
}

/// Same additive-optional narrowing contract as ArchGetRequest: nil means
/// "what CLARIFY_GET has always returned", so an unnarrowed request is
/// byte-identical and no wire bump is owed. Two things here grow without
/// bound — the embedded care package (its clarified intent plus N curated
/// exploration COPIES) and the note bodies — and each has its own switch.
/// Questions are NOT windowed: a question plus its pre-authored options is
/// bounded by what a human can answer, and the count is small by design.
public struct ClarifyGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    /// nil/true = the package rides along (the historical response). false
    /// replaces it with `carePackageStub`, because the whole package is
    /// separately readable through CARE_PACKAGE_GET and duplicating it here
    /// is the single largest avoidable weight in this response.
    public let includeCarePackage: Bool?
    /// Weight window over the notes, mirroring the rating windows: a note at
    /// or below this weight stays a full row, the rest drop to `noteStubs`.
    /// Notes with NO weight are ALWAYS full — the same "unranked is the work
    /// queue" rule EXPLORE_GET applies to unranked findings. nil = every note
    /// full.
    public let noteWeightMax: Int?

    public init(promptUuid: String, includeCarePackage: Bool? = nil, noteWeightMax: Int? = nil) {
        self.promptUuid = promptUuid
        self.includeCarePackage = includeCarePackage
        self.noteWeightMax = noteWeightMax
    }

    public var isNarrowed: Bool { includeCarePackage != nil || noteWeightMax != nil }
}

/// A note with its body replaced by a leading excerpt and its true length.
/// A note has no title, so a body-less stub would be unreadable — the excerpt
/// is what makes "is this one worth widening for" answerable.
public struct ClarificationNoteStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let weight: Int?
    public let agentName: String?
    public let questionUuid: String?
    public let bodyExcerpt: String
    public let bodyChars: Int
    public let bodyTruncated: Bool

    public init(
        uuid: String,
        weight: Int?,
        agentName: String?,
        questionUuid: String?,
        bodyExcerpt: String,
        bodyChars: Int,
        bodyTruncated: Bool
    ) {
        self.uuid = uuid
        self.weight = weight
        self.agentName = agentName
        self.questionUuid = questionUuid
        self.bodyExcerpt = bodyExcerpt
        self.bodyChars = bodyChars
        self.bodyTruncated = bodyTruncated
    }
}

/// The care package as counts — enough to know it EXISTS, what state it is
/// in, and how big it is, without carrying a byte of its content. Emitted in
/// `carePackage`'s place when CLARIFY_GET narrowed it away, so nil-package
/// and narrowed-away-package stay distinguishable (both-nil means the prompt
/// genuinely has no package).
public struct CarePackageStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let status: String
    public let clarifiedIntentChars: Int
    public let dopeRefCount: Int
    public let kbiteRefCount: Int
    public let explorationRefCount: Int
    public let dopeScopeUuid: String?
    public let dopeScopeRevision: Int64?

    public init(
        uuid: String,
        version: Int64,
        status: String,
        clarifiedIntentChars: Int,
        dopeRefCount: Int,
        kbiteRefCount: Int,
        explorationRefCount: Int,
        dopeScopeUuid: String?,
        dopeScopeRevision: Int64?
    ) {
        self.uuid = uuid
        self.version = version
        self.status = status
        self.clarifiedIntentChars = clarifiedIntentChars
        self.dopeRefCount = dopeRefCount
        self.kbiteRefCount = kbiteRefCount
        self.explorationRefCount = explorationRefCount
        self.dopeScopeUuid = dopeScopeUuid
        self.dopeScopeRevision = dopeScopeRevision
    }

    public init(package: CarePackageRow) {
        self.init(
            uuid: package.uuid,
            version: package.version,
            status: package.status,
            clarifiedIntentChars: package.clarifiedIntent.count,
            dopeRefCount: package.dopeRefs.count,
            kbiteRefCount: package.kbiteRefs.count,
            explorationRefCount: package.explorationRefs.count,
            dopeScopeUuid: package.dopeScopeUuid,
            dopeScopeRevision: package.dopeScopeRevision)
    }
}

/// The care package's read-time dope drift report — the same shape
/// BriefingStaleness carries, computed by the same
/// `DopeRepository.scopeStaleness`. Computed at read, never stored.
public struct CarePackageStaleness: Codable, Hashable, Sendable {
    public let stampedRevision: Int64?
    public let currentRevision: Int64?
    public let drifted: Bool
    public let ghostDotPaths: [String]

    public init(
        stampedRevision: Int64?,
        currentRevision: Int64?,
        drifted: Bool,
        ghostDotPaths: [String]
    ) {
        self.stampedRevision = stampedRevision
        self.currentRevision = currentRevision
        self.drifted = drifted
        self.ghostDotPaths = ghostDotPaths
    }
}

/// Shape shared by BriefingStaleness and CarePackageStaleness so clients render
/// ONE badge. An additive protocol on existing Codable types — the JSON is
/// byte-identical, so this is NOT a wire change.
public protocol DopeScopeStalenessReporting {
    var stampedRevision: Int64? { get }
    var currentRevision: Int64? { get }
    var drifted: Bool { get }
    var ghostDotPaths: [String] { get }
}

extension BriefingStaleness: DopeScopeStalenessReporting {}
extension CarePackageStaleness: DopeScopeStalenessReporting {}

public struct ClarifyGetResponse: Codable, Hashable, Sendable {
    public let summary: ClarificationSummaryRow
    public let questions: [ClarificationQuestionRow]
    public let notes: [ClarificationNoteRow]
    /// nil until package-open (bot-variant flows never create one).
    public let carePackage: CarePackageRow?
    /// ADDITIVE OPTIONAL (no wire bump — decodes as nil on a stale peer).
    /// INVARIANT: non-nil IFF `carePackage` is non-nil.
    public let carePackageStaleness: CarePackageStaleness?
    /// ADDITIVE OPTIONAL (no wire bump). Non-nil ONLY when
    /// `includeCarePackage: false` narrowed a package that DOES exist —
    /// so `carePackage == nil && carePackageStub == nil` still means, as it
    /// always has, that no package was ever opened.
    public let carePackageStub: CarePackageStub?
    /// ADDITIVE OPTIONAL. Non-nil ONLY when a weight window was applied:
    /// the notes outside it, as excerpts.
    public let noteStubs: [ClarificationNoteStub]?

    public init(
        summary: ClarificationSummaryRow,
        questions: [ClarificationQuestionRow],
        notes: [ClarificationNoteRow],
        carePackage: CarePackageRow?,
        carePackageStaleness: CarePackageStaleness? = nil,
        carePackageStub: CarePackageStub? = nil,
        noteStubs: [ClarificationNoteStub]? = nil
    ) {
        self.summary = summary
        self.questions = questions
        self.notes = notes
        self.carePackage = carePackage
        self.carePackageStaleness = carePackageStaleness
        self.carePackageStub = carePackageStub
        self.noteStubs = noteStubs
    }
}

// MARK: - CARE_PACKAGE_* (m0025)

/// Open (or return) the care package on a clarification summary. Multi-agent
/// flows only by convention — the schema is variant-agnostic.
public struct CarePackageOpenRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String

    public init(summaryUuid: String) {
        self.summaryUuid = summaryUuid
    }
}

public struct CarePackageResponse: Codable, Hashable, Sendable {
    public let package: CarePackageRow
    public let created: Bool
    /// ADDITIVE OPTIONAL (no wire bump). Non-nil ONLY when CARE_PACKAGE_GET
    /// narrowed the curated exploration COPIES away: `package.explorationRefs`
    /// then holds just the refs whose bodies were asked for, and this holds
    /// the complete roster as excerpts. NARROWING EMPTIES AN ARRAY AND NAMES
    /// WHAT LEFT IT — it never rewrites a row's fields, so no value inside a
    /// CarePackageRow is ever a truncated lie.
    public let explorationRefStubs: [CarePackageExplorationRefStub]?

    public init(
        package: CarePackageRow,
        created: Bool = false,
        explorationRefStubs: [CarePackageExplorationRefStub]? = nil
    ) {
        self.package = package
        self.created = created
        self.explorationRefStubs = explorationRefStubs
    }
}

/// A curated exploration COPY with its body replaced by a leading excerpt.
public struct CarePackageExplorationRefStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let curatedTitle: String
    public let filePath: String?
    public let sourceFindingUuid: String?
    public let seq: Int
    public let curatedBodyExcerpt: String
    public let curatedBodyChars: Int
    public let curatedBodyTruncated: Bool

    public init(
        uuid: String,
        curatedTitle: String,
        filePath: String?,
        sourceFindingUuid: String?,
        seq: Int,
        curatedBodyExcerpt: String,
        curatedBodyChars: Int,
        curatedBodyTruncated: Bool
    ) {
        self.uuid = uuid
        self.curatedTitle = curatedTitle
        self.filePath = filePath
        self.sourceFindingUuid = sourceFindingUuid
        self.seq = seq
        self.curatedBodyExcerpt = curatedBodyExcerpt
        self.curatedBodyChars = curatedBodyChars
        self.curatedBodyTruncated = curatedBodyTruncated
    }
}

/// The ref kind vocabulary for CARE_REF_ADD.
public enum CarePackageRefKind: String, Codable, Hashable, CaseIterable, Sendable {
    case dope
    case kbite
    case exploration
}

/// Add one ref child while the package is `building`. Exactly the fields for
/// the kind: dope → dopeCode (+note); kbite → kbiteFileUuid; exploration →
/// curatedTitle + curatedBody (+filePath, +sourceFindingUuid) — a COPY,
/// never a re-exploration.
public struct CarePackageRefAddRequest: Codable, Hashable, Sendable {
    public let packageUuid: String
    public let kind: CarePackageRefKind
    public let dopeCode: String?
    public let note: String?
    public let kbiteFileUuid: String?
    public let curatedTitle: String?
    public let curatedBody: String?
    public let filePath: String?
    public let sourceFindingUuid: String?

    public init(
        packageUuid: String,
        kind: CarePackageRefKind,
        dopeCode: String? = nil,
        note: String? = nil,
        kbiteFileUuid: String? = nil,
        curatedTitle: String? = nil,
        curatedBody: String? = nil,
        filePath: String? = nil,
        sourceFindingUuid: String? = nil
    ) {
        self.packageUuid = packageUuid
        self.kind = kind
        self.dopeCode = dopeCode
        self.note = note
        self.kbiteFileUuid = kbiteFileUuid
        self.curatedTitle = curatedTitle
        self.curatedBody = curatedBody
        self.filePath = filePath
        self.sourceFindingUuid = sourceFindingUuid
    }
}

/// building → ready. `clarifiedIntent` is carried ONLY here (its one write
/// path — the overview-at-complete idiom). The daemon stamps the dope scope
/// revision itself, exactly like briefing complete.
public struct CarePackageCompleteRequest: Codable, Hashable, Sendable {
    public let packageUuid: String
    public let expectedVersion: Int64
    public let clarifiedIntent: String

    public init(packageUuid: String, expectedVersion: Int64, clarifiedIntent: String) {
        self.packageUuid = packageUuid
        self.expectedVersion = expectedVersion
        self.clarifiedIntent = clarifiedIntent
    }
}

/// Additive-optional narrowing, same contract as the other two: nil = the
/// historical full package.
///
/// `clarifiedIntent` is deliberately NOT narrowable. It is ONE blob written
/// by ONE agent and it is the entire reason downstream agents read this
/// package; a package whose intent had to be fetched in a second round trip
/// would just be read twice. The curated exploration COPIES are the part that
/// scales with agent count, so they are the part with a switch.
public struct CarePackageGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    /// nil/true = curated exploration bodies inline (the historical
    /// response). false moves the roster to `explorationRefStubs`.
    public let includeRefBodies: Bool?
    /// Return exactly this exploration ref's curated body in full.
    public let refUuid: String?

    public init(promptUuid: String, includeRefBodies: Bool? = nil, refUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.includeRefBodies = includeRefBodies
        self.refUuid = refUuid
    }

    public var isNarrowed: Bool { includeRefBodies != nil || refUuid != nil }
}

// MARK: - ARCH_* (v7)

public struct ArchOpenRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

public struct ArchSummaryResponse: Codable, Hashable, Sendable {
    public let summary: ArchitectureSummaryRow
    public let created: Bool

    public init(summary: ArchitectureSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Set the concept-level body (approach, components, data flow, tradeoffs —
/// never specific file changes; those are the normalized change rows).
public struct ArchSummarizeRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64
    public let body: String

    public init(summaryUuid: String, expectedVersion: Int64, body: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.body = body
    }
}

public struct ArchPersistAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let className: String
    public let filePath: String
    public let reasonBrief: String
    /// m0025: add|modify|rename|delete (defaults to modify at write).
    public let changeKind: String?
    /// m0025: domain.entity dot-path CODE, ghost-legal.
    public let dopeRef: String?

    public init(
        summaryUuid: String,
        className: String,
        filePath: String,
        reasonBrief: String,
        changeKind: String? = nil,
        dopeRef: String? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.className = className
        self.filePath = filePath
        self.reasonBrief = reasonBrief
        self.changeKind = changeKind
        self.dopeRef = dopeRef
    }
}

public struct ArchPersistAddResponse: Codable, Hashable, Sendable {
    public let change: ArchPersistenceChangeRow

    public init(change: ArchPersistenceChangeRow) {
        self.change = change
    }
}

public struct ArchFieldAddRequest: Codable, Hashable, Sendable {
    public let persistenceChangeUuid: String
    public let fieldName: String
    public let dataType: String
    public let changeReason: String
    public let changePurpose: String
    public let nullable: Bool
    public let isForeignKey: Bool
    public let fkTarget: String?
    public let isIndexed: Bool
    /// m0025: add|modify|rename|delete (defaults to add at write).
    public let changeKind: String?
    /// m0025: old field name when changeKind == rename.
    public let renamedFrom: String?
    /// m0025: domain.entity.property dot-path CODE, ghost-legal.
    public let dopePropertyRef: String?

    public init(
        persistenceChangeUuid: String,
        fieldName: String,
        dataType: String,
        changeReason: String,
        changePurpose: String,
        nullable: Bool,
        isForeignKey: Bool = false,
        fkTarget: String? = nil,
        isIndexed: Bool = false,
        changeKind: String? = nil,
        renamedFrom: String? = nil,
        dopePropertyRef: String? = nil
    ) {
        self.persistenceChangeUuid = persistenceChangeUuid
        self.fieldName = fieldName
        self.dataType = dataType
        self.changeReason = changeReason
        self.changePurpose = changePurpose
        self.nullable = nullable
        self.isForeignKey = isForeignKey
        self.fkTarget = fkTarget
        self.isIndexed = isIndexed
        self.changeKind = changeKind
        self.renamedFrom = renamedFrom
        self.dopePropertyRef = dopePropertyRef
    }
}

public struct ArchFieldAddResponse: Codable, Hashable, Sendable {
    public let field: ArchPersistenceFieldChangeRow

    public init(field: ArchPersistenceFieldChangeRow) {
        self.field = field
    }
}

public struct ArchGeneralAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let filePath: String
    public let className: String?
    public let reasonBrief: String
    public let changeDepth: ChangeDepth
    public let changeCode: String

    public init(
        summaryUuid: String,
        filePath: String,
        className: String? = nil,
        reasonBrief: String,
        changeDepth: ChangeDepth,
        changeCode: String
    ) {
        self.summaryUuid = summaryUuid
        self.filePath = filePath
        self.className = className
        self.reasonBrief = reasonBrief
        self.changeDepth = changeDepth
        self.changeCode = changeCode
    }
}

public struct ArchGeneralAddResponse: Codable, Hashable, Sendable {
    public let change: ArchGeneralChangeRow

    public init(change: ArchGeneralChangeRow) {
        self.change = change
    }
}

/// drafting → proposed (seals change rows for review).
public struct ArchProposeRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// proposed → approved (terminal; unlocks architecting → implementing).
public struct ArchApproveRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// proposed → drafting (the revision edge).
public struct ArchReviseRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Structurally-partitioned read — the ARCH analogue of the rating windows
/// on EXPLORE_GET / REVIEW_GET. Architecture rows carry no rating, so the
/// window is STRUCTURAL rather than numeric: option bodies, change_code, and
/// a page over the general change rows.
///
/// THE WIRE DEFAULT IS UNCHANGED BY CONSTRUCTION. Every field below is an
/// additive OPTIONAL whose nil means "what ARCH_GET has always returned":
/// full option bodies, verbatim change_code, every row, and none of the new
/// response keys emitted at all. A caller that ships no new field — GMVibes'
/// local package build, any older peer — gets a byte-identical response,
/// which is exactly why this does NOT bump GMCCWireProtocol.version.
///
/// THE NARROWING IS APPLIED BY THE PEN, NOT THE DAEMON. gmcc_mcp's `arch_get`
/// passes includeOptions=false / full=false / limit by DEFAULT and exposes
/// include_options / option_uuid / full / change_uuid / limit / cursor in its
/// tool schema so an agent can widen. The agent harness — not the daemon — is
/// where an 80 KB result gets refused, so the client that feeds the harness
/// is the client that narrows.
///
/// persistenceChanges are NEVER narrowed and NEVER paged. They are the
/// persistence-first contract, and they were the silent casualty of the
/// unwindowed response: sorted-key JSON puts "options" before
/// "persistence_changes", so a clip mid-array ate the whole persistence set
/// without saying so.
public struct ArchGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    /// nil/true = option BODIES inline (the historical response). false drops
    /// the bodies to `optionStubs` — the option ROSTER never disappears, so
    /// narrowing can hide content but never existence. nil with an
    /// `optionUuid` set means "only that one body".
    public let includeOptions: Bool?
    /// Return exactly this option's body in full. In team flows the options
    /// are four architect essays and this is how you read one.
    public let optionUuid: String?
    /// nil/true = general change_code verbatim (the store caps it at 2 MB
    /// EACH, which is the other half of the weight). false drops every
    /// general row to `generalChangeStubs` — leading excerpt + true length.
    /// nil with a `changeUuid` set means "only that one body".
    public let full: Bool?
    /// Return exactly this general change's change_code in full. Pins one
    /// row, so it ignores limit/cursor.
    public let changeUuid: String?
    /// Page size over the GENERAL change rows (nil = every row).
    public let limit: Int?
    /// Opaque continuation token — the `changePage.nextCursor` of the
    /// previous page, never constructed by hand.
    public let cursor: String?

    public init(
        promptUuid: String,
        includeOptions: Bool? = nil,
        optionUuid: String? = nil,
        full: Bool? = nil,
        changeUuid: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) {
        self.promptUuid = promptUuid
        self.includeOptions = includeOptions
        self.optionUuid = optionUuid
        self.full = full
        self.changeUuid = changeUuid
        self.limit = limit
        self.cursor = cursor
    }

    /// True when the caller asked for ANY narrowing. Drives the
    /// byte-identical-default guarantee: false ⇒ none of the additive
    /// response keys is emitted.
    public var isNarrowed: Bool {
        includeOptions != nil || optionUuid != nil || full != nil
            || changeUuid != nil || limit != nil || cursor != nil
    }
}

/// An option with its BODY replaced by a length. Carries everything needed to
/// decide whether to fetch the body (`ArchGetRequest.optionUuid`) — including
/// which one won. The decision RATIONALE is not duplicated here: it lives on
/// `ArchitectureSummaryRow.decisionRationale`, which every form of the
/// response carries in full.
public struct ArchitectureOptionStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let agentName: String
    public let agentId: String?
    public let status: String
    public let selected: Bool
    public let bodyChars: Int

    public init(
        uuid: String,
        agentName: String,
        agentId: String?,
        status: String,
        selected: Bool,
        bodyChars: Int
    ) {
        self.uuid = uuid
        self.agentName = agentName
        self.agentId = agentId
        self.status = status
        self.selected = selected
        self.bodyChars = bodyChars
    }
}

/// A general change row with change_code replaced by a leading excerpt and
/// its true length. Every OTHER field — path, reason, depth, and the derived
/// implementation state — stays verbatim, because those are what an
/// implementation audit actually reads.
public struct ArchGeneralChangeStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let seq: Int64
    public let filePath: String
    public let className: String?
    public let reasonBrief: String
    public let changeDepth: String
    public let changeCodeExcerpt: String
    public let changeCodeChars: Int
    public let changeCodeTruncated: Bool
    public let implementation: ChangeImplementationState

    public init(
        uuid: String,
        seq: Int64,
        filePath: String,
        className: String?,
        reasonBrief: String,
        changeDepth: String,
        changeCodeExcerpt: String,
        changeCodeChars: Int,
        changeCodeTruncated: Bool,
        implementation: ChangeImplementationState
    ) {
        self.uuid = uuid
        self.seq = seq
        self.filePath = filePath
        self.className = className
        self.reasonBrief = reasonBrief
        self.changeDepth = changeDepth
        self.changeCodeExcerpt = changeCodeExcerpt
        self.changeCodeChars = changeCodeChars
        self.changeCodeTruncated = changeCodeTruncated
        self.implementation = implementation
    }
}

/// Where the general-change page sits in the whole ordered set. `total` is
/// the unpaged count, so a caller always knows what it has NOT seen.
public struct ArchChangePage: Codable, Hashable, Sendable {
    public let limit: Int?
    public let returned: Int
    public let totalGeneralChanges: Int
    /// nil = this is the last page.
    public let nextCursor: String?

    public init(limit: Int?, returned: Int, totalGeneralChanges: Int, nextCursor: String?) {
        self.limit = limit
        self.returned = returned
        self.totalGeneralChanges = totalGeneralChanges
        self.nextCursor = nextCursor
    }
}

/// The architecture with derived implementation state: persistence changes
/// always ordered before general changes (the persistence-first contract),
/// each decorated with its file_change join; unplanned_changes is the touched-
/// but-not-planned set. ordering_respected audits persistence-first execution
/// (nil when either side is empty or untouched). Join is path-level on
/// daemon-normalized repo-relative paths; file changes without a prompt_uuid
/// are invisible to it — always pass --prompt-uuid when recording.
public struct ArchGetResponse: Codable, Hashable, Sendable {
    public let summary: ArchitectureSummaryRow
    /// m0025: the persisted methodology options (empty outside team flows).
    public let options: [ArchitectureOptionRow]
    public let persistenceChanges: [ArchPersistenceChangeRow]
    public let generalChanges: [ArchGeneralChangeRow]
    public let unplannedChanges: [UnplannedChangeRow]
    public let orderingRespected: Bool?
    /// ADDITIVE OPTIONAL (no wire bump — absent on every unnarrowed read and
    /// on any stale peer). Non-nil ONLY when the request narrowed options:
    /// the complete roster, so a dropped body is never a dropped option.
    public let optionStubs: [ArchitectureOptionStub]?
    /// ADDITIVE OPTIONAL. Non-nil ONLY when the request narrowed change_code
    /// or paged: the stub form of the general rows in this page.
    public let generalChangeStubs: [ArchGeneralChangeStub]?
    /// ADDITIVE OPTIONAL. Non-nil ONLY on a narrowed read — where the page
    /// sits in the whole set.
    public let changePage: ArchChangePage?

    public init(
        summary: ArchitectureSummaryRow,
        options: [ArchitectureOptionRow] = [],
        persistenceChanges: [ArchPersistenceChangeRow],
        generalChanges: [ArchGeneralChangeRow],
        unplannedChanges: [UnplannedChangeRow],
        orderingRespected: Bool?,
        optionStubs: [ArchitectureOptionStub]? = nil,
        generalChangeStubs: [ArchGeneralChangeStub]? = nil,
        changePage: ArchChangePage? = nil
    ) {
        self.summary = summary
        self.options = options
        self.persistenceChanges = persistenceChanges
        self.generalChanges = generalChanges
        self.unplannedChanges = unplannedChanges
        self.orderingRespected = orderingRespected
        self.optionStubs = optionStubs
        self.generalChangeStubs = generalChangeStubs
        self.changePage = changePage
    }
}

// MARK: - ARCH_OPTION_* (v24: the architect pen inversion)

/// One methodology's proposal written by the architect agent ITSELF — the
/// first architect pen verb. Options are team-only by convention; zero
/// options = the direct persist/field/general expansion stays legal.
public struct ArchOptionAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let agentName: String
    public let agentId: String?
    public let body: String

    public init(summaryUuid: String, agentName: String, agentId: String? = nil, body: String) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.agentId = agentId
        self.body = body
    }
}

public struct ArchOptionRowResponse: Codable, Hashable, Sendable {
    public let option: ArchitectureOptionRow

    public init(option: ArchitectureOptionRow) {
        self.option = option
    }
}

/// Atomically select one option (rejecting its siblings) and record the
/// decision rationale on the summary. Only after a decision may the selected
/// option expand into persistence/field/general change rows — enforced as a
/// store guard, not a CHECK (the m0016 cross-table rule).
public struct ArchDecideRequest: Codable, Hashable, Sendable {
    public let optionUuid: String
    public let expectedVersion: Int64
    public let rationale: String

    public init(optionUuid: String, expectedVersion: Int64, rationale: String) {
        self.optionUuid = optionUuid
        self.expectedVersion = expectedVersion
        self.rationale = rationale
    }
}

public struct ArchDecideResponse: Codable, Hashable, Sendable {
    public let summary: ArchitectureSummaryRow
    public let options: [ArchitectureOptionRow]

    public init(summary: ArchitectureSummaryRow, options: [ArchitectureOptionRow]) {
        self.summary = summary
        self.options = options
    }
}

// MARK: - BOT_* (v24: the daemon-held workflow state machine)

/// Workflow variants. `task` is deliberately ABSENT from the machine — its
/// write-nothing contract means no workflow row; the registry lists it only
/// so errors can name it.
public enum BotVariant: String, Codable, Hashable, CaseIterable, Sendable {
    case bot
    case rpi
    case team
}

/// Enter the machine from `draft`: creates the workflow row and claims it
/// for the calling instance. Deliberately NO status change — briefing and
/// exploration run while the prompt is still draft, exactly as the manual
/// flow always has; gm prompt set-status stays the only door.
public struct PromptStartRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let variant: BotVariant
    public let clientKey: String?

    public init(promptUuid: String, variant: BotVariant, clientKey: String? = nil) {
        self.promptUuid = promptUuid
        self.variant = variant
        self.clientKey = clientKey
    }
}

/// Adopt whatever evidence exists: fetch-or-create the workflow row,
/// re-stamp the client key, change no status. Phase is recomputed at every
/// NEXT — resume IS the first-run code path.
public struct PromptResumeRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    /// Required when resume must CREATE the row (a pre-machine prompt).
    public let variant: BotVariant?
    public let clientKey: String?

    public init(promptUuid: String, variant: BotVariant? = nil, clientKey: String? = nil) {
        self.promptUuid = promptUuid
        self.variant = variant
        self.clientKey = clientKey
    }
}

public struct BotWorkflowResponse: Codable, Hashable, Sendable {
    public let workflow: BotWorkflowRow
    public let created: Bool

    public init(workflow: BotWorkflowRow, created: Bool = false) {
        self.workflow = workflow
        self.created = created
    }
}

/// Zero-uuid form: promptUuid nil resolves through the activation registry
/// (caller's own claim → session's single claim), exactly like briefing get.
public struct BotNextRequest: Codable, Hashable, Sendable {
    public let promptUuid: String?
    public let clientKey: String?
    public let sessionUuid: String?

    public init(promptUuid: String? = nil, clientKey: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.clientKey = clientKey
        self.sessionUuid = sessionUuid
    }
}

/// The uuid bundle NEXT serves alongside the instruction text — everything
/// the phase needs, computed from db state at read (nothing stored).
public struct BotPhaseUuids: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let sessionUuid: String
    public let briefingUuid: String?
    public let clarificationSummaryUuid: String?
    public let carePackageUuid: String?
    public let architectureSummaryUuid: String?
    public let reviewSummaryUuid: String?
    /// (agent_type → summary uuid) for the prompt's exploration rows.
    public let explorationSummaryUuids: [String: String]

    public init(
        promptUuid: String,
        sessionUuid: String,
        briefingUuid: String?,
        clarificationSummaryUuid: String?,
        carePackageUuid: String?,
        architectureSummaryUuid: String?,
        reviewSummaryUuid: String?,
        explorationSummaryUuids: [String: String]
    ) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.briefingUuid = briefingUuid
        self.clarificationSummaryUuid = clarificationSummaryUuid
        self.carePackageUuid = carePackageUuid
        self.architectureSummaryUuid = architectureSummaryUuid
        self.reviewSummaryUuid = reviewSummaryUuid
        self.explorationSummaryUuids = explorationSummaryUuids
    }
}

public struct BotNextResponse: Codable, Hashable, Sendable {
    public let workflow: BotWorkflowRow
    /// The furthest phase whose entry gate is satisfied.
    public let phase: String
    /// Compiled-in instruction text for (variant, phase) — the Cheatsheet
    /// precedent; drift-guarded by WorkflowSpecTests.
    public let instructions: String
    /// What still blocks the NEXT phase (empty when the phase's own work is
    /// simply not done yet).
    public let gateBlockers: [String]
    public let uuids: BotPhaseUuids

    public init(
        workflow: BotWorkflowRow,
        phase: String,
        instructions: String,
        gateBlockers: [String],
        uuids: BotPhaseUuids
    ) {
        self.workflow = workflow
        self.phase = phase
        self.instructions = instructions
        self.gateBlockers = gateBlockers
        self.uuids = uuids
    }
}

/// The raw workflow row (zero-uuid resolved like NEXT).
public struct BotGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String?
    public let clientKey: String?
    public let sessionUuid: String?

    public init(promptUuid: String? = nil, clientKey: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.clientKey = clientKey
        self.sessionUuid = sessionUuid
    }
}

// MARK: - AGENT_REGISTER

/// Who agent X is — one row per agent_id, written by two parties that never
/// coordinate.
///
/// TWO WRITERS, ONE ROW, keyed on agent_id alone:
///
/// - `gm hook subagent-start` writes the IDENTITY half (agent_type and the
///   Claude ids) because that half is universal — every spawn shape fires
///   SubagentStart carrying agent_id, and the hook beats the agent to any
///   write. The gmcc session and prompt are NOT on this message: the daemon
///   resolves them from `claudeSessionId` through the binding, which is the
///   same single resolution path a file_change takes.
/// - `gm agent register` writes the AUTHORITY half (role, methodology,
///   phase), because no spawn shape delivers a role or a methodology and four
///   identical personas differ by agent_id alone — for a bare workflow agent
///   the role exists nowhere but the spawning script.
///
/// Fields are MERGED, never overwritten: an omitted field leaves whatever the
/// row already holds, so neither writer can erase the other's half. ORDERING
/// IS NOT A CONSTRAINT — the join happens at READ time, so a spawner that
/// only learns agent ids when a dynamic workflow reports back may register
/// long after the agent's rows are written and still explain them.
public struct AgentRegisterRequest: Codable, Hashable, Sendable {
    /// Opaque and NEVER parsed. Its shape varies by spawn kind, and reading
    /// structure into it would make the registry wrong for whichever shape
    /// ships next.
    public let agentId: String
    public let role: String?
    public let methodology: String?
    /// The phase the spawner spawned this agent FOR — the spawner's claim,
    /// distinct from the workflow phase the daemon derives and stamps onto a
    /// file_change.
    public let workflowPhase: String?
    /// The identity half, off the SubagentStart payload.
    ///
    /// `agentType` is a LABEL and never authoritative: it carries the
    /// subagent_type for a plain subagent, the literal `workflow-subagent`
    /// for a bare workflow agent, and the NAME for a named teammate. The role
    /// that means something arrives on the authority half instead.
    ///
    /// `claudeTurnId` is the naming trap — the payload calls it `prompt_id`
    /// and it is Claude Code's TURN id, not a gmcc prompt uuid.
    public let agentType: String?
    public let claudeSessionId: String?
    public let claudeTurnId: String?

    public init(
        agentId: String,
        role: String? = nil,
        methodology: String? = nil,
        workflowPhase: String? = nil,
        agentType: String? = nil,
        claudeSessionId: String? = nil,
        claudeTurnId: String? = nil
    ) {
        self.agentId = agentId
        self.role = role
        self.methodology = methodology
        self.workflowPhase = workflowPhase
        self.agentType = agentType
        self.claudeSessionId = claudeSessionId
        self.claudeTurnId = claudeTurnId
    }
}

public struct AgentRegisterResponse: Codable, Hashable, Sendable {
    public let registration: AgentRegistrationRow
    /// True when this call created the row — i.e. the spawner got there
    /// before the SubagentStart hook, and the identity half is still empty.
    public let created: Bool

    public init(registration: AgentRegistrationRow, created: Bool) {
        self.registration = registration
        self.created = created
    }
}

// MARK: - EXPLORE_* (v24: literal per-agent summaries)

/// Open (or return) the summary for (prompt, agentType). agentType defaults
/// to 'general'; 'synthesis' is the prompt-level seal/synthesis row the
/// primary completes last.
public struct ExploreOpenRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let agentType: String?
    public let agentId: String?

    public init(promptUuid: String, agentType: String? = nil, agentId: String? = nil) {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
    }
}

/// Shared response for explore verbs that return the summary row. `created`
/// is true only when OPEN made the row (open is idempotent create-or-return;
/// it is EXPLICIT-only — never wired into prompt status transitions, since
/// exploration runs while the prompt is still `draft`).
public struct ExploreSummaryResponse: Codable, Hashable, Sendable {
    public let summary: ExplorationSummaryRow
    public let created: Bool

    public init(summary: ExplorationSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Add one key file (summary must be `exploring`). Key files are a shared
/// deduped set: a duplicate path is an idempotent upsert-ignore returning the
/// existing row with created=false, never an error.
public struct ExploreKeyFileAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let filePath: String

    public init(summaryUuid: String, filePath: String) {
        self.summaryUuid = summaryUuid
        self.filePath = filePath
    }
}

public struct ExploreKeyFileAddResponse: Codable, Hashable, Sendable {
    public let keyFile: ExplorationKeyFileRow
    public let created: Bool

    public init(keyFile: ExplorationKeyFileRow, created: Bool) {
        self.keyFile = keyFile
        self.created = created
    }
}

/// Insert a finding while the summary is `exploring`. `rating` is optional at
/// insert — NULL marks the finding unranked (work-in-progress); COMPLETE
/// refuses while any finding is unranked.
public struct ExploreFindingAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let kind: ExplorationFindingKind
    public let title: String
    public let body: String
    /// m0025: the merged key-file half of the finding/file pair.
    public let filePath: String?
    public let agentName: String
    public let agentId: String?
    public let rating: Int?

    public init(
        summaryUuid: String,
        kind: ExplorationFindingKind,
        title: String,
        body: String,
        filePath: String? = nil,
        agentName: String,
        agentId: String? = nil,
        rating: Int? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.agentName = agentName
        self.agentId = agentId
        self.rating = rating
    }
}

public struct ExploreFindingRowResponse: Codable, Hashable, Sendable {
    public let finding: ExplorationFindingRow

    public init(finding: ExplorationFindingRow) {
        self.finding = finding
    }
}

/// Batch-rank findings (summary must be `exploring` — ranking a sealed set
/// would shift the sub-100 contract; reopen first). The whole batch validates
/// before any write and applies atomically: one bad pair (out-of-range,
/// duplicate, or a finding not belonging to this summary) rejects everything.
/// Deliberately version-less: the team re-ranker blind-overwrites ratings it
/// never read — that IS the specified semantic — and the single-writer
/// DatabaseQueue serializes competing batches. Re-rank = same verb again.
public struct ExploreRankRequest: Codable, Hashable, Sendable {
    /// m0025: the batch is PROMPT-scoped — one atomic calibrated batch across
    /// every summary of the prompt (cross-persona tombstoning preserved,
    /// re-keyed from summary to prompt).
    public let promptUuid: String
    public let ratings: [FindingRating]

    public init(promptUuid: String, ratings: [FindingRating]) {
        self.promptUuid = promptUuid
        self.ratings = ratings
    }
}

public struct ExploreRankResponse: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let updatedCount: Int
    /// 0 ⇒ the synthesis COMPLETE (seal) will pass its rank gate.
    public let unrankedCount: Int

    public init(promptUuid: String, updatedCount: Int, unrankedCount: Int) {
        self.promptUuid = promptUuid
        self.updatedCount = updatedCount
        self.unrankedCount = unrankedCount
    }
}

/// exploring → complete. Refuses while any finding is unranked. `overview` is
/// carried ONLY here — there is no earlier write path, so the narrative is
/// structurally written by the primary agent after the ranked findings exist.
public struct ExploreCompleteRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64
    public let overview: String

    public init(summaryUuid: String, expectedVersion: Int64, overview: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
    }
}

/// complete → exploring: the revision edge. Preserves everything (findings,
/// ratings, key files, overview) — the next COMPLETE must re-carry the
/// overview, so staleness cannot survive a re-seal.
public struct ExploreReopenRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Threshold-partitioned read. Default window is ratings under 100; findings
/// inside the window (or unranked — NULL-rated rows are ALWAYS full, they are
/// the resume work-queue) come back as full rows, the rest as stubs.
/// full=true returns everything full; ratingMax/ratingMin shift the window.
public struct ExploreGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    /// Optional filter to one agent's summary; nil returns all of them.
    public let agentType: String?
    public let full: Bool
    public let ratingMin: Int?
    public let ratingMax: Int?

    public init(
        promptUuid: String,
        agentType: String? = nil,
        full: Bool = false,
        ratingMin: Int? = nil,
        ratingMax: Int? = nil
    ) {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.full = full
        self.ratingMin = ratingMin
        self.ratingMax = ratingMax
    }
}

public struct ExploreGetResponse: Codable, Hashable, Sendable {
    /// m0025: every summary row of the prompt (or the agentType filter's
    /// one), synthesis first, then alphabetical by agent_type.
    public let summaries: [ExplorationSummaryRow]
    /// COMPUTED view: findings of kind 'key_file' across those summaries —
    /// kept as a wire array so consumers keep a stable key-file surface.
    public let keyFiles: [ExplorationKeyFileRow]
    /// Full rows: rating inside the window OR unranked, ordered unranked
    /// first, then by rating ascending.
    public let findings: [ExplorationFindingRow]
    /// Lightweight stubs for everything outside the window.
    public let findingStubs: [ExplorationFindingStub]

    public init(
        summaries: [ExplorationSummaryRow],
        keyFiles: [ExplorationKeyFileRow],
        findings: [ExplorationFindingRow],
        findingStubs: [ExplorationFindingStub]
    ) {
        self.summaries = summaries
        self.keyFiles = keyFiles
        self.findings = findings
        self.findingStubs = findingStubs
    }
}

// MARK: - REVIEW_* (v9)

public struct ReviewOpenRequest: Codable, Hashable, Sendable {
    public let promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Same contract as ExploreSummaryResponse: open is idempotent and EXPLICIT-
/// only — prompt status transitions never create or gate on this summary
/// (skip-to-done stays legal).
public struct ReviewSummaryResponse: Codable, Hashable, Sendable {
    public let summary: ReviewSummaryRow
    public let created: Bool

    public init(summary: ReviewSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Insert a finding while the summary is `reviewing`. filePath is nil for
/// cross-cutting findings; lineEnd requires lineStart.
public struct ReviewFindingAddRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let kind: ReviewFindingKind
    public let title: String
    public let body: String
    public let filePath: String?
    public let lineStart: Int?
    public let lineEnd: Int?
    public let agentName: String
    /// m0025 agent_id sweep (additive optional).
    public let agentId: String?
    public let rating: Int?

    public init(
        summaryUuid: String,
        kind: ReviewFindingKind,
        title: String,
        body: String,
        filePath: String? = nil,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        agentName: String,
        agentId: String? = nil,
        rating: Int? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.agentName = agentName
        self.agentId = agentId
        self.rating = rating
    }
}

public struct ReviewFindingRowResponse: Codable, Hashable, Sendable {
    public let finding: ReviewFindingRow

    public init(finding: ReviewFindingRow) {
        self.finding = finding
    }
}

/// Batch rank — same contract and rationale as ExploreRankRequest.
public struct ReviewRankRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let ratings: [FindingRating]

    public init(summaryUuid: String, ratings: [FindingRating]) {
        self.summaryUuid = summaryUuid
        self.ratings = ratings
    }
}

public struct ReviewRankResponse: Codable, Hashable, Sendable {
    public let summary: ReviewSummaryRow
    public let updatedCount: Int
    public let unrankedCount: Int

    public init(summary: ReviewSummaryRow, updatedCount: Int, unrankedCount: Int) {
        self.summary = summary
        self.updatedCount = updatedCount
        self.unrankedCount = unrankedCount
    }
}

/// Record one finding's resolution. Pure child-row update, expectedVersion
/// targets the FINDING. Deliberately UNGATED on summary status — the fix loop
/// runs after COMPLETE, and a reopen mid-loop must not strand in-flight
/// resolves (the inversion of the clarify child-lock, by design).
public struct ReviewResolveRequest: Codable, Hashable, Sendable {
    public let findingUuid: String
    public let expectedVersion: Int64
    public let status: ReviewFindingStatus

    public init(findingUuid: String, expectedVersion: Int64, status: ReviewFindingStatus) {
        self.findingUuid = findingUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

/// reviewing → complete. Refuses while any finding is unranked; requires a
/// verdict. overview + verdict are carried ONLY here (primary-agent-only by
/// write-path shape).
public struct ReviewCompleteRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64
    public let overview: String
    public let verdict: ReviewVerdict

    public init(summaryUuid: String, expectedVersion: Int64, overview: String, verdict: ReviewVerdict) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
        self.verdict = verdict
    }
}

/// complete → reviewing: the revision edge (same preservation contract as
/// ExploreReopenRequest; the persisted verdict survives until re-complete).
public struct ReviewReopenRequest: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let expectedVersion: Int64

    public init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

public struct ReviewGetRequest: Codable, Hashable, Sendable {
    public let promptUuid: String
    public let full: Bool
    public let ratingMin: Int?
    public let ratingMax: Int?

    public init(promptUuid: String, full: Bool = false, ratingMin: Int? = nil, ratingMax: Int? = nil) {
        self.promptUuid = promptUuid
        self.full = full
        self.ratingMin = ratingMin
        self.ratingMax = ratingMax
    }
}

public struct ReviewGetResponse: Codable, Hashable, Sendable {
    public let summary: ReviewSummaryRow
    public let findings: [ReviewFindingRow]
    public let findingStubs: [ReviewFindingStub]

    public init(
        summary: ReviewSummaryRow,
        findings: [ReviewFindingRow],
        findingStubs: [ReviewFindingStub]
    ) {
        self.summary = summary
        self.findings = findings
        self.findingStubs = findingStubs
    }
}

// MARK: - SESSION_RESOLVE / INSTANCE_CURRENT_SESSION (v7)

/// Git-derived checked-out state for one session. head_state is one of
/// "branch", "detached", "unavailable" (missing/unreadable instance path —
/// tolerated, never an error).
public struct SessionResolveRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String

    public init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

public struct SessionResolveResponse: Codable, Hashable, Sendable {
    public let session: SessionRow
    public let checkedOut: Bool
    public let headState: String
    /// The slugged code of whatever IS checked out (nil when detached or
    /// unavailable). Slugging is forward-only: branch / → __, never unslugged.
    public let currentSessionCode: String?
    /// The RAW branch name (nil whenever head_state != "branch"). The code
    /// stays slugged; the two are never interconverted client-side.
    public let currentBranch: String?

    public init(session: SessionRow, checkedOut: Bool, headState: String, currentSessionCode: String?, currentBranch: String?) {
        self.session = session
        self.checkedOut = checkedOut
        self.headState = headState
        self.currentSessionCode = currentSessionCode
        self.currentBranch = currentBranch
    }
}

public struct InstanceCurrentSessionRequest: Codable, Hashable, Sendable {
    public let instanceUuid: String

    public init(instanceUuid: String) {
        self.instanceUuid = instanceUuid
    }
}

/// session is nil when detached, unavailable, or the checked-out branch has
/// no session row yet.
public struct InstanceCurrentSessionResponse: Codable, Hashable, Sendable {
    public let session: SessionStub?
    public let headState: String
    public let currentSessionCode: String?
    /// The RAW branch name (nil whenever head_state != "branch").
    public let currentBranch: String?

    public init(session: SessionStub?, headState: String, currentSessionCode: String?, currentBranch: String?) {
        self.session = session
        self.headState = headState
        self.currentSessionCode = currentSessionCode
        self.currentBranch = currentBranch
    }
}

// MARK: - PATHS_GET / CONFIG_SET (v7)

public struct PathsGetRequest: Codable, Hashable, Sendable {
    public init() {}
}

/// Typed roots (never a map — dictionary keys and coder key strategies don't
/// mix). gmcc/db/socket/backups come from Paths; the ckfs and kbite roots
/// from daemon_config (seeded defaults, settable via CONFIG_SET). Retires
/// client-side ~/.zshrc scraping.
public struct PathsGetResponse: Codable, Hashable, Sendable {
    public let gmccRoot: String
    public let dbPath: String
    public let socketPath: String
    public let backupsRoot: String
    public let ckfsRoot: String
    public let kbiteRoot: String
    public let kbiteOpenRoot: String
    public let kbiteDigestedRoot: String

    public init(
        gmccRoot: String,
        dbPath: String,
        socketPath: String,
        backupsRoot: String,
        ckfsRoot: String,
        kbiteRoot: String,
        kbiteOpenRoot: String,
        kbiteDigestedRoot: String
    ) {
        self.gmccRoot = gmccRoot
        self.dbPath = dbPath
        self.socketPath = socketPath
        self.backupsRoot = backupsRoot
        self.ckfsRoot = ckfsRoot
        self.kbiteRoot = kbiteRoot
        self.kbiteOpenRoot = kbiteOpenRoot
        self.kbiteDigestedRoot = kbiteDigestedRoot
    }
}

public struct ConfigSetRequest: Codable, Hashable, Sendable {
    public let key: ConfigKey
    public let value: String

    public init(key: ConfigKey, value: String) {
        self.key = key
        self.value = value
    }
}

public struct ConfigSetResponse: Codable, Hashable, Sendable {
    public let key: ConfigKey
    public let value: String

    public init(key: ConfigKey, value: String) {
        self.key = key
        self.value = value
    }
}

// MARK: - BRIEFING_* (v21)

/// Reserve (or reset) the briefing row for one (owner, step) pair. Exactly
/// one owner may be supplied: promptUuid for bot-workflow briefings, or
/// sessionUuid alone for /gm_task-owned ones. The daemon derives session_uuid
/// from the prompt's owner chain when prompt-owned, so the two can never
/// disagree. OPEN on an existing pair RESETS the row to `building` (version
/// bump, content kept for wholesale replacement at complete) — a step's
/// briefing is always its CURRENT briefing, never a pile of drafts.
public struct BriefingOpenRequest: Codable, Hashable, Sendable {
    public let promptUuid: String?
    public let sessionUuid: String?
    public let briefingForStep: String
    /// The calling instance's identity. A prompt-owned open ALSO claims the
    /// activation for this key: briefings are consumed during explore
    /// (prompt still draft) and architect phases — long before set-status
    /// implementing would claim — and opening a briefing IS declaring "this
    /// instance works this prompt". Without it the zero-uuid resolution
    /// ladder had no path to success in the documented flows.
    public let clientKey: String?

    public init(
        promptUuid: String? = nil,
        sessionUuid: String? = nil,
        briefingForStep: String,
        clientKey: String? = nil
    ) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.briefingForStep = briefingForStep
        self.clientKey = clientKey
    }
}

public struct BriefingRowResponse: Codable, Hashable, Sendable {
    public let briefing: AgentBriefingRow
    public let created: Bool
    /// Well-formed dope dot-paths the briefing asked for that resolve to
    /// NOTHING in the dope tree. Reported back in the tool result so a doper
    /// sees its own unresolvable refs instead of discovering them as silence.
    /// Additive OPTIONAL field (nil = this build did not compute it), so it
    /// decodes safely in both directions — no wire bump.
    public let unresolvedDopeRefs: [String]?

    public init(
        briefing: AgentBriefingRow,
        created: Bool = false,
        unresolvedDopeRefs: [String]? = nil
    ) {
        self.briefing = briefing
        self.created = created
        self.unresolvedDopeRefs = unresolvedDopeRefs
    }
}

/// building → ready. The daemon stamps dope_scope_uuid + dope_scope_revision
/// ITSELF from the session's SESSION_INSTANCE scope (the writing agent cannot
/// mis-stamp), and denormalizes each kbite ref's brief by joining the kbite
/// tables — the doper passes file uuids only.
public struct BriefingCompleteRequest: Codable, Hashable, Sendable {
    public let briefingUuid: String
    public let expectedVersion: Int64
    /// DOT-PATH strings (domain.entity.property style), never uuids.
    /// m0025: written as agent_briefing_dope_persistence child rows.
    public let dopeRefs: [String]?
    /// KBite file uuids; the daemon resolves each brief at write time.
    public let kbiteRefs: [String]?
    /// file_change uuids (agent_session_file_change children).
    public let fileChangeRefs: [String]?
    /// Doper self-report for dedup/tracking.
    public let agentId: String?

    public init(
        briefingUuid: String,
        expectedVersion: Int64,
        dopeRefs: [String]? = nil,
        kbiteRefs: [String]? = nil,
        fileChangeRefs: [String]? = nil,
        agentId: String? = nil
    ) {
        self.briefingUuid = briefingUuid
        self.expectedVersion = expectedVersion
        self.dopeRefs = dopeRefs
        self.kbiteRefs = kbiteRefs
        self.fileChangeRefs = fileChangeRefs
        self.agentId = agentId
    }
}

/// Fetch one briefing: by uuid, by (prompt, step), or by (session, step) —
/// the ACTIVE resolution: the caller's own activation claim (clientKey) →
/// the session's single claim when unambiguous → the session-owned task row.
/// This is what makes the lookup DETERMINISTIC for spawned agents: gm
/// resolves session (cwd) and clientKey (process ancestry) itself, so no
/// uuid ever has to survive a spawn prompt or an agent's echo. A real owner
/// with no rows is SUMMARY_ABSENT, never an empty fabrication.
public struct BriefingGetRequest: Codable, Hashable, Sendable {
    public let briefingUuid: String?
    public let promptUuid: String?
    public let sessionUuid: String?
    public let step: String?
    public let clientKey: String?

    public init(
        briefingUuid: String? = nil,
        promptUuid: String? = nil,
        sessionUuid: String? = nil,
        step: String? = nil,
        clientKey: String? = nil
    ) {
        self.briefingUuid = briefingUuid
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.step = step
        self.clientKey = clientKey
    }
}

/// Staleness is COMPUTED at every read, never trusted from the row alone:
/// the stored scope revision is compared against the live scope, and each
/// dope ref dot-path is re-resolved — dangling paths come back as ghosts
/// (a legal state, diagram-binding precedent). Warn, never block.
public struct BriefingStaleness: Codable, Hashable, Sendable {
    public let stampedRevision: Int64?
    public let currentRevision: Int64?
    public let drifted: Bool
    public let ghostDotPaths: [String]

    public init(
        stampedRevision: Int64?,
        currentRevision: Int64?,
        drifted: Bool,
        ghostDotPaths: [String]
    ) {
        self.stampedRevision = stampedRevision
        self.currentRevision = currentRevision
        self.drifted = drifted
        self.ghostDotPaths = ghostDotPaths
    }
}

public struct BriefingGetResponse: Codable, Hashable, Sendable {
    public let briefing: AgentBriefingRow
    public let staleness: BriefingStaleness

    public init(briefing: AgentBriefingRow, staleness: BriefingStaleness) {
        self.briefing = briefing
        self.staleness = staleness
    }
}

public struct BriefingListRequest: Codable, Hashable, Sendable {
    public let promptUuid: String?
    public let sessionUuid: String?

    public init(promptUuid: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
    }
}

public struct BriefingListResponse: Codable, Hashable, Sendable {
    public let briefings: [AgentBriefingRow]

    public init(briefings: [AgentBriefingRow]) {
        self.briefings = briefings
    }
}

/// The SubagentStart hook's one call. The daemon resolves cwd → instance →
/// current session → active_prompt_uuid, maps the agent role to its step via
/// BriefingStepSpec, and composes a compact plain-text stub (uuids, one-line
/// summary, staleness flag, and the exact `gm briefing get` pull command).
/// Roles without a step — and sessions with nothing applicable — yield an
/// EMPTY stub with ok=true: the hook must never wedge a spawn.
public struct BriefingStubRequest: Codable, Hashable, Sendable {
    public let agentType: String?
    /// Client-resolved session (the gm CLI resolves cwd context; the daemon
    /// does not see the caller's working directory).
    public let sessionUuid: String?
    /// Client-resolved instance identity (process ancestry) — scopes the
    /// stub to the SPAWNING Claude instance's activation, so concurrent
    /// prompts on one session each hand their agents the right briefing.
    public let clientKey: String?

    public init(agentType: String? = nil, sessionUuid: String? = nil, clientKey: String? = nil) {
        self.agentType = agentType
        self.sessionUuid = sessionUuid
        self.clientKey = clientKey
    }
}

public struct BriefingStubResponse: Codable, Hashable, Sendable {
    /// Plain text, ≤2KB by construction; empty when nothing applies.
    public let stub: String

    public init(stub: String) {
        self.stub = stub
    }
}

// MARK: - DOPE_* (v11)

/// Create-or-return a dope scope (idempotent, the archOpen precedent).
/// scope_type is derived: PROMPT when promptUuid is present, else
/// SESSION_INSTANCE. `cloneFromSessionBase` forks the session's
/// SESSION_INSTANCE tree of the same code into a freshly created PROMPT scope.
public struct DopeInitRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    public let promptUuid: String?
    public let code: String
    public let name: String
    public let description: String?
    public let cloneFromSessionBase: Bool?

    public init(
        sessionUuid: String,
        promptUuid: String? = nil,
        code: String,
        name: String,
        description: String? = nil,
        cloneFromSessionBase: Bool? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.cloneFromSessionBase = cloneFromSessionBase
    }
}

public struct DopeScopeResponse: Codable, Hashable, Sendable {
    public let scope: DopeScopeRow
    public let created: Bool

    public init(scope: DopeScopeRow, created: Bool) {
        self.scope = scope
        self.created = created
    }
}

/// Scope enumeration for pickers (v12). Without promptUuid: the session's
/// SESSION_INSTANCE scopes. With it: ONLY that prompt's PROMPT scopes — never a
/// union, so a GUI never string-parses dopeGet's "several dope scopes match"
/// BAD_REQUEST. Unknown session/prompt uuid is NOT_FOUND; a real target with
/// no scopes is a normal empty list, never SUMMARY_ABSENT. No code filter:
/// enumerating IS the point and every row carries its own code.
public struct DopeListRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    public let promptUuid: String?

    public init(sessionUuid: String, promptUuid: String? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
    }
}

public struct DopeListResponse: Codable, Hashable, Sendable {
    /// ORDER BY code — the SAME order dopeGet's candidate list prints, so a
    /// picker's rows and the disambiguator message can never disagree.
    public let scopes: [DopeScopeRow]

    public init(scopes: [DopeScopeRow]) {
        self.scopes = scopes
    }
}

/// Tree read. With promptUuid set, the PROMPT scope is preferred and the
/// SESSION_INSTANCE tree is the fallback (resolvedVia reports which). With
/// several scopes matching and no code, the store answers BAD_REQUEST
/// naming the candidate codes.
public struct DopeGetRequest: Codable, Hashable, Sendable {
    /// Empty ONLY when addressing by `projectUuid` instead.
    ///
    /// Kept non-optional so every existing caller and every older peer's
    /// payload still decodes unchanged — a project-tier read passes "" here
    /// and fills `projectUuid`. Making it Optional would have been a
    /// breaking shape change on an existing message for no gain.
    public let sessionUuid: String
    public let promptUuid: String?
    public let code: String?
    /// PROJECT-tier addressing: reads the PROJECT_ITEM overlay, else the
    /// BASE_PROJECT scope that `gm dope promote` maintains.
    ///
    /// Additive OPTIONAL, so no wire bump: an older peer omits it and gets
    /// exactly today's session-only behavior.
    public let projectUuid: String?
    /// Merge the masking overlay over its base and return the resolved tree.
    /// OPT-IN, and deliberately so: without it every existing caller — the
    /// CLI, GMVibes, gm diagram from-dope, the screenshot path — keeps its
    /// exact single-layer semantics. Additive OPTIONAL, so an older peer that
    /// omits it means "unresolved", which is today's behavior.
    public let resolved: Bool?

    public init(sessionUuid: String, promptUuid: String? = nil, code: String? = nil,
                resolved: Bool? = nil, projectUuid: String? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    /// PROJECT-tier convenience: reads a project's own scope ladder.
    public init(projectUuid: String, code: String? = nil, resolved: Bool? = nil) {
        self.sessionUuid = ""
        self.promptUuid = nil
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, code, resolved, projectUuid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid) ?? ""
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved)
        projectUuid = try c.decodeIfPresent(String.self, forKey: .projectUuid)
    }
}

public struct DopeGetResponse: Codable, Hashable, Sendable {
    public let tree: DopeScopeTree
    /// Which scope supplied the tree: "prompt" | "session_base", or
    /// "<overlay_tier>_over_<base_tier>" when --resolved merged two layers.
    public let resolvedVia: String
    /// Present only for a resolved read: dot-path -> provenance.
    public let resolutions: [DopeOverlay.Resolution]?
    /// Dot-paths a whiteout masked away.
    public let hidden: [String]?
    /// Non-fatal observations (orphaned masks). Never an error.
    public let warnings: [String]?
    /// Per-area content counters ("persistence", "cogs"). A client compares
    /// one number to decide whether that subtree needs refetching, which is
    /// what makes dope sub-LOADABLE. These sit BESIDE tree.revision, which
    /// remains the whole-tree counter and the sole CAS gate.
    public let areaVersions: [String: Int64]?

    public init(tree: DopeScopeTree, resolvedVia: String,
                resolutions: [DopeOverlay.Resolution]? = nil,
                hidden: [String]? = nil, warnings: [String]? = nil,
                areaVersions: [String: Int64]? = nil) {
        self.tree = tree
        self.resolvedVia = resolvedVia
        self.resolutions = resolutions
        self.hidden = hidden
        self.warnings = warnings
        self.areaVersions = areaVersions
    }
}

// MARK: - DOPE_SEARCH

/// The three search scopes, in the prompt's own vocabulary.
public enum DopeSearchScope: String, Codable, Hashable, CaseIterable, Sendable {
    case prompt, session, project
}

/// One UNION arm per source table.
public enum DopeSearchSource: String, Codable, Hashable, CaseIterable, Sendable {
    case scope, persistence, entity, property, enumeration, option, cog, cogElement
}

public struct DopeSearchRequest: Codable, Hashable, Sendable {
    public let query: String
    public let scope: DopeSearchScope
    public let sessionUuid: String?
    public let promptUuid: String?
    public let projectUuid: String?
    /// Keep only hits whose dot-path came from the overlay rather than the
    /// base. A post-filter over resolver provenance, so the FTS query is the
    /// same shape with and without it.
    public let onlyMasks: Bool?
    public let limit: Int?

    public init(query: String, scope: DopeSearchScope, sessionUuid: String? = nil,
                promptUuid: String? = nil, projectUuid: String? = nil,
                onlyMasks: Bool? = nil, limit: Int? = nil) {
        self.query = query; self.scope = scope; self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid; self.projectUuid = projectUuid
        self.onlyMasks = onlyMasks; self.limit = limit
    }
}

public struct DopeSearchHit: Codable, Hashable, Sendable {
    public let kind: String
    public let subjectUuid: String
    public let scopeUuid: String
    public let scopeCode: String
    public let scopeType: String
    /// The dot-path — the same identity the resolver merges on.
    public let path: String
    public let title: String
    public let excerpt: String
    public let score: Double
    /// Resolver provenance; present only for an --only-masks search.
    public let origin: String?

    public init(kind: String, subjectUuid: String, scopeUuid: String, scopeCode: String,
                scopeType: String, path: String, title: String, excerpt: String,
                score: Double, origin: String?) {
        self.kind = kind; self.subjectUuid = subjectUuid; self.scopeUuid = scopeUuid
        self.scopeCode = scopeCode; self.scopeType = scopeType; self.path = path
        self.title = title; self.excerpt = excerpt; self.score = score; self.origin = origin
    }
}

public struct DopeSearchResponse: Codable, Hashable, Sendable {
    public let hits: [DopeSearchHit]
    public init(hits: [DopeSearchHit]) { self.hits = hits }
}

// MARK: - COGS

public struct DopeCogElementNode: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let elementType: String
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    public let parentElementUuid: String?
    /// Ghost-tolerant CODE reference to a dope scope, resolved at read time —
    /// never a uuid FK (ingest re-mints uuids, and scope delete is not
    /// offered, so there is no ON DELETE answer to give).
    public let dopeScopeCode: String?
    /// From the type's subtype table. Hull only.
    public let primaryPath: String?
    /// From the type's subtype table. PersistenceOwner only: the CODE of the
    /// persistence domain this element's parent Hull owns. Additive and
    /// OPTIONAL, so it decodes safely in both directions.
    public let dopePersistenceCode: String?
    public let deletedOn: String?

    public init(uuid: String, version: Int64, elementType: String, code: String, name: String,
                description: String, sortOrder: Int, parentElementUuid: String?,
                dopeScopeCode: String?, primaryPath: String?,
                dopePersistenceCode: String? = nil, deletedOn: String?) {
        self.uuid = uuid
        self.version = version
        self.elementType = elementType
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.parentElementUuid = parentElementUuid
        self.dopeScopeCode = dopeScopeCode
        self.primaryPath = primaryPath
        self.dopePersistenceCode = dopePersistenceCode
        self.deletedOn = deletedOn
    }
}

public struct DopeCogNode: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    public let deletedOn: String?
    public let elements: [DopeCogElementNode]

    public init(uuid: String, version: Int64, code: String, name: String, description: String,
                sortOrder: Int, deletedOn: String?, elements: [DopeCogElementNode]) {
        self.uuid = uuid
        self.version = version
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.deletedOn = deletedOn
        self.elements = elements
    }
}

public struct DopeCogAddRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    public let code: String
    public let name: String
    public let description: String?
    public let sortOrder: Int?
    public init(scopeUuid: String, code: String, name: String,
                description: String? = nil, sortOrder: Int? = nil) {
        self.scopeUuid = scopeUuid; self.code = code; self.name = name
        self.description = description; self.sortOrder = sortOrder
    }
}

public struct DopeCogUpdateRequest: Codable, Hashable, Sendable {
    public let uuid: String
    public let expectedVersion: Int64
    public let code: String?
    public let name: String?
    public let description: String?
    public let sortOrder: Int?
    public init(uuid: String, expectedVersion: Int64, code: String? = nil, name: String? = nil,
                description: String? = nil, sortOrder: Int? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
    }
}

public struct DopeCogDeleteRequest: Codable, Hashable, Sendable {
    public let uuid: String
    public let expectedVersion: Int64
    public let soft: Bool?
    public init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

public struct DopeCogElementAddRequest: Codable, Hashable, Sendable {
    public let cogUuid: String
    public let elementType: String
    public let code: String
    public let name: String
    public let description: String?
    public let sortOrder: Int?
    public let parentElementUuid: String?
    public let dopeScopeCode: String?
    public let primaryPath: String?
    /// PersistenceOwner's owned domain CODE. Additive and OPTIONAL, so it
    /// decodes safely in both directions per the wire convention.
    public let dopePersistenceCode: String?
    public init(cogUuid: String, elementType: String, code: String, name: String,
                description: String? = nil, sortOrder: Int? = nil,
                parentElementUuid: String? = nil, dopeScopeCode: String? = nil,
                primaryPath: String? = nil, dopePersistenceCode: String? = nil) {
        self.cogUuid = cogUuid; self.elementType = elementType; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.parentElementUuid = parentElementUuid; self.dopeScopeCode = dopeScopeCode
        self.primaryPath = primaryPath; self.dopePersistenceCode = dopePersistenceCode
    }
}

public struct DopeCogElementUpdateRequest: Codable, Hashable, Sendable {
    public let uuid: String
    public let expectedVersion: Int64
    public let code: String?
    public let name: String?
    public let description: String?
    public let sortOrder: Int?
    public let dopeScopeCode: String?
    public let clearDopeScopeCode: Bool?
    public let primaryPath: String?
    public init(uuid: String, expectedVersion: Int64, code: String? = nil, name: String? = nil,
                description: String? = nil, sortOrder: Int? = nil, dopeScopeCode: String? = nil,
                clearDopeScopeCode: Bool? = nil, primaryPath: String? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.dopeScopeCode = dopeScopeCode; self.clearDopeScopeCode = clearDopeScopeCode
        self.primaryPath = primaryPath
    }
}

public struct DopeCogElementDeleteRequest: Codable, Hashable, Sendable {
    public let uuid: String
    public let expectedVersion: Int64
    public let soft: Bool?
    public init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

public struct DopeCogGetRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    public let code: String?
    public init(scopeUuid: String, code: String? = nil) {
        self.scopeUuid = scopeUuid; self.code = code
    }
}

public struct DopeCogResponse: Codable, Hashable, Sendable {
    public let cog: DopeCogNode
    public let revision: Int64
    public init(cog: DopeCogNode, revision: Int64) { self.cog = cog; self.revision = revision }
}

public struct DopeCogElementResponse: Codable, Hashable, Sendable {
    public let element: DopeCogElementNode
    public let revision: Int64
    public init(element: DopeCogElementNode, revision: Int64) {
        self.element = element; self.revision = revision
    }
}

public struct DopeCogDeleteResponse: Codable, Hashable, Sendable {
    public let deletedUuid: String
    public let cascadedElements: Int
    public let scopeUuid: String
    public let revision: Int64
    public init(deletedUuid: String, cascadedElements: Int, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid; self.cascadedElements = cascadedElements
        self.scopeUuid = scopeUuid; self.revision = revision
    }
}

public struct DopeCogGetResponse: Codable, Hashable, Sendable {
    public let cogs: [DopeCogNode]
    public init(cogs: [DopeCogNode]) { self.cogs = cogs }
}

/// DOPE_PROMOTE — publish a session's SESSION_INSTANCE tree into the
/// project's BASE_PROJECT scope. Runs automatically at boot behind
/// DopeBootSync, and manually via `gm dope promote` (a non-throwing boot path
/// that silently does nothing is undebuggable, so the verb exists too).
public struct DopePromoteRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    public let code: String?
    /// Compute the decision and write NOTHING. This is what makes
    /// "why didn't it promote?" answerable, and it is what gm doctor uses to
    /// report a stale BASE_PROJECT without ever publishing as a side effect.
    public let dryRun: Bool?

    public init(sessionUuid: String, code: String? = nil, dryRun: Bool? = nil) {
        self.sessionUuid = sessionUuid
        self.code = code
        self.dryRun = dryRun
    }
}

public struct DopePromotedScope: Codable, Hashable, Sendable {
    public let code: String
    public let baseScopeUuid: String
    /// The high-water the base carried before this promotion.
    public let fromRevision: Int64
    /// The source revision now recorded as the high-water.
    public let toRevision: Int64
    public let counts: DopeTreeCounts

    public init(code: String, baseScopeUuid: String, fromRevision: Int64,
                toRevision: Int64, counts: DopeTreeCounts) {
        self.code = code
        self.baseScopeUuid = baseScopeUuid
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.counts = counts
    }
}

public struct DopePromoteResponse: Codable, Hashable, Sendable {
    /// On a dry run these are what WOULD be published, and nothing was
    /// written.
    public let promoted: [DopePromotedScope]
    /// "branch_mismatch" | "no_session_scope" | "up_to_date" | nil
    public let skipped: String?
    public let detail: String?

    public init(promoted: [DopePromotedScope], skipped: String? = nil, detail: String? = nil) {
        self.promoted = promoted
        self.skipped = skipped
        self.detail = detail
    }
}

/// The generic node-mutation payload. nil = leave alone; the clear* flags
/// mean "set NULL" — a distinction plain optionals cannot express. Which
/// fields a level owns is DopeLevelSpec's ownedFields; a misdirected field
/// is a precise BAD_REQUEST.
public struct DopeNodeFields: Codable, Hashable, Sendable {
    public let code: String?
    public let name: String?
    public let description: String?
    public let sortOrder: Int?
    public let entityType: DopeEntityType?
    public let repoRepresentativeFile: String?
    public let baseComposableUuid: String?
    public let dataType: DopePropertyDataType?
    public let nullable: Bool?
    public let isUnique: Bool?
    public let autoIncrement: Bool?
    public let textCharLimit: Int?
    public let enumUuid: String?
    public let relationshipTargetUuid: String?
    public let baseOriginPropertyUuid: String?
    public let clearRepoRepresentativeFile: Bool?
    public let clearBaseComposable: Bool?
    public let clearBaseOrigin: Bool?
    public let clearAutoIncrement: Bool?
    public let clearTextCharLimit: Bool?
    public let clearEnum: Bool?
    public let clearRelationshipTarget: Bool?

    public init(
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        entityType: DopeEntityType? = nil,
        repoRepresentativeFile: String? = nil,
        baseComposableUuid: String? = nil,
        dataType: DopePropertyDataType? = nil,
        nullable: Bool? = nil,
        isUnique: Bool? = nil,
        autoIncrement: Bool? = nil,
        textCharLimit: Int? = nil,
        enumUuid: String? = nil,
        relationshipTargetUuid: String? = nil,
        baseOriginPropertyUuid: String? = nil,
        clearRepoRepresentativeFile: Bool? = nil,
        clearBaseComposable: Bool? = nil,
        clearBaseOrigin: Bool? = nil,
        clearAutoIncrement: Bool? = nil,
        clearTextCharLimit: Bool? = nil,
        clearEnum: Bool? = nil,
        clearRelationshipTarget: Bool? = nil
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.entityType = entityType
        self.repoRepresentativeFile = repoRepresentativeFile
        self.baseComposableUuid = baseComposableUuid
        self.dataType = dataType
        self.nullable = nullable
        self.isUnique = isUnique
        self.autoIncrement = autoIncrement
        self.textCharLimit = textCharLimit
        self.enumUuid = enumUuid
        self.relationshipTargetUuid = relationshipTargetUuid
        self.baseOriginPropertyUuid = baseOriginPropertyUuid
        self.clearRepoRepresentativeFile = clearRepoRepresentativeFile
        self.clearBaseComposable = clearBaseComposable
        self.clearBaseOrigin = clearBaseOrigin
        self.clearAutoIncrement = clearAutoIncrement
        self.clearTextCharLimit = clearTextCharLimit
        self.clearEnum = clearEnum
        self.clearRelationshipTarget = clearRelationshipTarget
    }
}

public struct DopeNodeAddRequest: Codable, Hashable, Sendable {
    public let level: DopeLevel
    public let parentUuid: String
    public let fields: DopeNodeFields

    public init(level: DopeLevel, parentUuid: String, fields: DopeNodeFields) {
        self.level = level
        self.parentUuid = parentUuid
        self.fields = fields
    }
}

public struct DopeNodeUpdateRequest: Codable, Hashable, Sendable {
    public let level: DopeLevel
    public let nodeUuid: String
    public let expectedVersion: Int64
    public let fields: DopeNodeFields

    public init(level: DopeLevel, nodeUuid: String, expectedVersion: Int64, fields: DopeNodeFields) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.fields = fields
    }
}

public struct DopeNodeDeleteRequest: Codable, Hashable, Sendable {
    public let level: DopeLevel
    public let nodeUuid: String
    public let expectedVersion: Int64
    /// Soft delete: stamp `deleted_on` instead of removing the row. The node
    /// stays visible to every read (that IS the feature — it communicates an
    /// intended delete), keeps satisfying every FK, and in an overlay tree
    /// acts as the resolver's whiteout over the base node at that dot-path.
    ///
    /// Additive OPTIONAL, so a peer that omits it still means "hard delete".
    public let soft: Bool?

    public init(
        level: DopeLevel, nodeUuid: String, expectedVersion: Int64, soft: Bool? = nil
    ) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.soft = soft
    }
}

public struct DopeNodeResponse: Codable, Hashable, Sendable {
    public let level: DopeLevel
    public let uuid: String
    public let version: Int64
    public let scopeUuid: String
    /// The scope's whole-tree content counter after this mutation.
    public let revision: Int64

    public init(level: DopeLevel, uuid: String, version: Int64, scopeUuid: String, revision: Int64) {
        self.level = level
        self.uuid = uuid
        self.version = version
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

public struct DopeNodeDeleteResponse: Codable, Hashable, Sendable {
    public let deletedUuid: String
    public let cascaded: DopeTreeCounts
    public let scopeUuid: String
    public let revision: Int64

    public init(deletedUuid: String, cascaded: DopeTreeCounts, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascaded = cascaded
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

/// Parse + validate the on-disk tree. Never writes. Exactly one of scopeUuid
/// (resolve the scope's own instance root) or dirPath (an explicit instance
/// root — read-only, still required to be a git checkout) must be present.
public struct DopeReadRepoRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String?
    public let dirPath: String?

    public init(scopeUuid: String? = nil, dirPath: String? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
    }
}

public struct DopeReadRepoResponse: Codable, Hashable, Sendable {
    public let bundle: DopeDocumentBundle
    public let onDiskRevision: Int64
    public let dbRevision: Int64?
    public let drift: Bool?
    public let warnings: [String]

    public init(
        bundle: DopeDocumentBundle,
        onDiskRevision: Int64,
        dbRevision: Int64?,
        drift: Bool?,
        warnings: [String]
    ) {
        self.bundle = bundle
        self.onDiskRevision = onDiskRevision
        self.dbRevision = dbRevision
        self.drift = drift
        self.warnings = warnings
    }
}

/// db → files. Refuses when the on-disk version is AHEAD of the db revision
/// (the files hold edits never ingested) unless force. Does not modify the
/// db beyond the audit event; does not bump revision (a projection, so a
/// repeat run is byte-idempotent).
public struct DopeWriteRepoRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    public let force: Bool?

    public init(scopeUuid: String, force: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.force = force
    }
}

public struct DopeWriteRepoResponse: Codable, Hashable, Sendable {
    public let dopeRoot: String
    public let filesWritten: [String]
    public let filesPruned: [String]
    public let revision: Int64

    public init(dopeRoot: String, filesWritten: [String], filesPruned: [String], revision: Int64) {
        self.dopeRoot = dopeRoot
        self.filesWritten = filesWritten
        self.filesPruned = filesPruned
        self.revision = revision
    }
}

/// files → db, whole-tree overwrite (no smart diff): the on-disk version
/// must equal db revision + 1 exactly. Every child uuid changes on every
/// ingest — the locked consequence of uuid-free JSON.
public struct DopeIngestRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    /// Explicit instance root to read from; nil = the scope's own.
    public let dirPath: String?
    /// Files-are-authoritative mode (boot sync only): permits any strictly
    /// FORWARD move (on-disk version > db revision), including seeding a
    /// virgin scope at revision 0 from a tree at any version. Never moves
    /// backward. Additive optional — absent means the strict +1 gate.
    public let adopt: Bool?

    public init(scopeUuid: String, dirPath: String? = nil, adopt: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
        self.adopt = adopt
    }
}

public struct DopeIngestResponse: Codable, Hashable, Sendable {
    public let scope: DopeScopeRow
    public let counts: DopeTreeCounts
    /// Revision the scope held before this ingest (additive optional).
    public let previousRevision: Int64?
    /// Revisions skipped beyond the strict +1 step (adopt only, additive).
    public let gapCrossed: Int64?

    public init(
        scope: DopeScopeRow, counts: DopeTreeCounts,
        previousRevision: Int64? = nil, gapCrossed: Int64? = nil
    ) {
        self.scope = scope
        self.counts = counts
        self.previousRevision = previousRevision
        self.gapCrossed = gapCrossed
    }
}

// MARK: - DIAGRAM_* (v15)

/// Create-or-return a diagram (idempotent per (tier owner, code) — the
/// dopeInit precedent). Exactly ONE owner uuid picks the tier; the store
/// derives and persists the full ancestor chain by joins (chain-non-null
/// ladder). gmccDiagramPath is refused at PROJECT tier (no instance root to
/// resolve it against).
public struct DiagramInitRequest: Codable, Hashable, Sendable {
    public let projectUuid: String?
    public let instanceUuid: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    public let code: String
    public let name: String
    public let description: String?
    public let gmccDiagramPath: String?
    /// The dope scope this whole diagram reads/writes through. Restricted to
    /// the masking tiers (PROJECT_ITEM / SESSION_INSTANCE_ITEM) so a canvas
    /// always edits a personal overlay rather than shared truth.
    public let dopeScopeCode: String?

    public init(
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        code: String,
        name: String,
        description: String? = nil,
        gmccDiagramPath: String? = nil,
        dopeScopeCode: String? = nil
    ) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.gmccDiagramPath = gmccDiagramPath
        self.dopeScopeCode = dopeScopeCode
    }
}

public struct DiagramResponse: Codable, Hashable, Sendable {
    public let diagram: DiagramRow
    public let created: Bool

    public init(diagram: DiagramRow, created: Bool) {
        self.diagram = diagram
        self.created = created
    }
}

/// Picker enumeration — the v12 dopeList contract verbatim: exactly one
/// owner uuid, exactly that tier's rows for that owner, never a union or a
/// cross-tier ladder, ORDER BY code. Unknown owner is NOT_FOUND; a real
/// owner with no diagrams is a normal empty list.
public struct DiagramListRequest: Codable, Hashable, Sendable {
    public let projectUuid: String?
    public let instanceUuid: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    /// v23, additive: server-side visibility filter (PRIVATE|PUBLIC).
    /// Absent = both. Still single-owner single-tier — never a union.
    public let visibility: String?

    public init(
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        visibility: String? = nil
    ) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.visibility = visibility
    }

}

public struct DiagramListResponse: Codable, Hashable, Sendable {
    public let diagrams: [DiagramRow]

    public init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// Full-tree read: by diagramUuid, or by exactly one owner uuid + optional
/// code. Deliberately NO cross-tier fallback ladder (tiers are explicit
/// workspaces — the ladder belongs to dope binding resolution INSIDE the
/// diagram). Several owner matches without a code → BAD_REQUEST naming the
/// candidate codes; a real owner with none → SUMMARY_ABSENT (diagramAbsent).
/// The response does NOT embed dope trees — clients pair it with DOPE_GET.
public struct DiagramGetRequest: Codable, Hashable, Sendable {
    public let diagramUuid: String?
    public let projectUuid: String?
    public let instanceUuid: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    public let code: String?

    public init(
        diagramUuid: String? = nil,
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        code: String? = nil
    ) {
        self.diagramUuid = diagramUuid
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
    }
}

public struct DiagramGetResponse: Codable, Hashable, Sendable {
    public let tree: DiagramTree
    /// One row per dope_scope binding element (resolvedVia nil = ghost).
    public let bindings: [DiagramBindingResolution]
    /// The OWNER's `ckfs_relative_storage_path` — the root a rendered
    /// screenshot lands under, whichever tier owns the diagram.
    ///
    /// ADDITIVE OPTIONAL on an existing message, so it does not bump the
    /// wire version (CLAUDE.md's rule) and an older peer simply ignores it.
    /// It lives here rather than being fetched separately because the
    /// alternative is three extra round trips — PROJECT_LIST / SESSION_GET /
    /// PROMPT_GET — to learn something the daemon already had in hand while
    /// resolving the owner.
    public let ownerStoragePath: String?

    public init(tree: DiagramTree, bindings: [DiagramBindingResolution],
                ownerStoragePath: String? = nil) {
        self.tree = tree
        self.bindings = bindings
        self.ownerStoragePath = ownerStoragePath
    }

    private enum CodingKeys: String, CodingKey {
        case tree, bindings, ownerStoragePath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tree = try c.decode(DiagramTree.self, forKey: .tree)
        bindings = try c.decode([DiagramBindingResolution].self, forKey: .bindings)
        // decodeIfPresent: a peer built before this field existed omits it.
        ownerStoragePath = try c.decodeIfPresent(String.self, forKey: .ownerStoragePath)
    }
}

/// Granular element verbs — each is a one-mutation batch over the SAME
/// store body as DIAGRAM_BATCH_APPLY, so granular and batch semantics
/// cannot drift. Diagram-row updates (rename/promotion) ride batch-apply's
/// diagramUpdate mutation.
public struct DiagramNodeAddRequest: Codable, Hashable, Sendable {
    public let diagramUuid: String
    public let add: DiagramElementAdd

    public init(diagramUuid: String, add: DiagramElementAdd) {
        self.diagramUuid = diagramUuid
        self.add = add
    }
}

public struct DiagramNodeUpdateRequest: Codable, Hashable, Sendable {
    public let update: DiagramElementUpdate

    public init(update: DiagramElementUpdate) {
        self.update = update
    }
}

public struct DiagramNodeDeleteRequest: Codable, Hashable, Sendable {
    public let delete: DiagramElementDelete

    public init(delete: DiagramElementDelete) {
        self.delete = delete
    }
}

/// Every mutation response carries diagramUuid + revision so clients update
/// without a refetch (the DopeNodeResponse contract).
public struct DiagramNodeResponse: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let diagramUuid: String
    public let revision: Int64

    public init(uuid: String, version: Int64, diagramUuid: String, revision: Int64) {
        self.uuid = uuid
        self.version = version
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

public struct DiagramNodeDeleteResponse: Codable, Hashable, Sendable {
    public let deletedUuid: String
    /// Element rows removed, including the target itself.
    public let cascadedElements: Int
    public let diagramUuid: String
    public let revision: Int64

    public init(deletedUuid: String, cascadedElements: Int, diagramUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascadedElements = cascadedElements
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

/// THE interactive write: many typed mutations, one transaction, ONE
/// revision bump, ONE DIAGRAM_CHANGE event. Mutations apply strictly in
/// array order; elementAdd clientRefs are resolvable by later mutations in
/// the same batch. expectedRevision non-nil is a whole-diagram CAS gate
/// (VERSION_CONFLICT on mismatch — gesture-end concurrency for GMVibes).
public struct DiagramBatchApplyRequest: Codable, Hashable, Sendable {
    public let diagramUuid: String
    public let expectedRevision: Int64?
    public let mutations: [DiagramMutation]

    public init(diagramUuid: String, expectedRevision: Int64? = nil, mutations: [DiagramMutation]) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
        self.mutations = mutations
    }
}

public struct DiagramBatchApplyResponse: Codable, Hashable, Sendable {
    public let diagramUuid: String
    public let revision: Int64
    /// Index-aligned with the request's mutations array.
    public let results: [DiagramMutationResult]

    public init(diagramUuid: String, revision: Int64, results: [DiagramMutationResult]) {
        self.diagramUuid = diagramUuid
        self.revision = revision
        self.results = results
    }
}

// MARK: - Diagram Studio (v23)

/// DIAGRAM_SEARCH — the cross-tier browse AND search surface backing the
/// GMVibes galleries. Deliberately a SEPARATE message from DIAGRAM_LIST,
/// whose single-owner no-union picker contract stays untouched.
///
/// Two modes in one message: a nil/empty `query` is a plain filtered SELECT
/// of the project's diagrams across tiers ordered by updated_at DESC (the
/// gallery grid); a non-empty query is a bm25-ranked FTS5 MATCH over
/// diagram_fts (the gallery search box). `sessionUuid` narrows to one
/// session's SESSION+PROMPT rows; `visibility` filters the axis.
public struct DiagramSearchRequest: Codable, Hashable, Sendable {
    public let projectUuid: String
    public let sessionUuid: String?
    public let query: String?
    public let visibility: String?
    public let limit: Int?

    public init(projectUuid: String, sessionUuid: String? = nil,
                query: String? = nil, visibility: String? = nil,
                limit: Int? = nil) {
        self.projectUuid = projectUuid
        self.sessionUuid = sessionUuid
        self.query = query
        self.visibility = visibility
        self.limit = limit
    }
}

/// Rows in rank order (bm25 when a query ran, updated_at DESC otherwise).
/// DiagramRow already carries tier/visibility/owner uuids/revision — the
/// whole card surface — so hits are plain rows, not a parallel shape.
public struct DiagramSearchResponse: Codable, Hashable, Sendable {
    public let diagrams: [DiagramRow]

    public init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// DIAGRAM_DELETE — row delete with an optional whole-diagram CAS gate.
/// Elements and subtype rows cascade via FKs, the FTS mirror via its
/// delete trigger, and prompt-qualified readings via m0022's CASCADE. A
/// durable DIAGRAM_CHANGE (action "deleted") is recorded BEFORE the row
/// drops so live galleries/editors close cleanly. Screenshot cleanup is
/// the CLIENT's (ckfs is gm territory, exactly like rendering).
public struct DiagramDeleteRequest: Codable, Hashable, Sendable {
    public let diagramUuid: String
    public let expectedRevision: Int64?

    public init(diagramUuid: String, expectedRevision: Int64? = nil) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
    }
}

public struct DiagramDeleteResponse: Codable, Hashable, Sendable {
    public let deletedUuid: String
    public let code: String
    /// Element rows removed with the diagram.
    public let cascadedElements: Int
    /// The owner storage path a screenshot may exist under (client cleanup).
    public let ownerStoragePath: String?
    /// The row's screenshot directory override — the client must clean the
    /// SAME path gm render wrote, not a guessed default.
    public let gmccDiagramPath: String?

    public init(deletedUuid: String, code: String, cascadedElements: Int,
                ownerStoragePath: String? = nil, gmccDiagramPath: String? = nil) {
        self.deletedUuid = deletedUuid
        self.code = code
        self.cascadedElements = cascadedElements
        self.ownerStoragePath = ownerStoragePath
        self.gmccDiagramPath = gmccDiagramPath
    }
}

/// DIAGRAM_WRITE_REPO — serialize the session's PUBLIC SESSION-tier
/// diagrams into the repo's committed .gmcc tree, through the session's
/// instance root (the dope write-repo gate and 4-phase orchestration,
/// applied verbatim). Explicit only: setting PUBLIC never writes files.
public struct DiagramWriteRepoRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String
    /// Overwrite files stamped AHEAD of the db (the dope --force contract).
    public let force: Bool

    public init(sessionUuid: String, force: Bool = false) {
        self.sessionUuid = sessionUuid
        self.force = force
    }
}

public struct DiagramWriteRepoResponse: Codable, Hashable, Sendable {
    /// Diagram codes written this pass.
    public let written: [String]
    /// Files pruned because their diagram was demoted or deleted.
    public let pruned: [String]
    /// The absolute .gmcc/diagrams directory written under.
    public let root: String

    public init(written: [String], pruned: [String], root: String) {
        self.written = written
        self.pruned = pruned
        self.root = root
    }
}

/// DIAGRAM_INGEST — files→db, strictly forward-only (the dope ingest gate):
/// a file version must be STRICTLY greater than the db revision to land.
/// Code-keyed upsert into the calling session's SESSION tier as PUBLIC;
/// connector code-path targets re-resolve, unresolvable → ghost.
public struct DiagramIngestRequest: Codable, Hashable, Sendable {
    public let sessionUuid: String

    public init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

public struct DiagramIngestResponse: Codable, Hashable, Sendable {
    /// Codes created or updated from files.
    public let ingested: [String]
    /// Codes skipped (db at or ahead of the file, or a PRIVATE collision).
    public let skipped: [String]
    /// Per-file problems (corrupt JSON, name/code mismatch, refused
    /// content). One bad file must never abort the family's sync — and the
    /// boot path must have something to PRINT, or the failure is silent.
    public let warnings: [String]
    /// The absolute .gmcc/diagrams directory read from.
    public let root: String

    public init(ingested: [String], skipped: [String], warnings: [String] = [],
                root: String) {
        self.ingested = ingested
        self.skipped = skipped
        self.warnings = warnings
        self.root = root
    }
}


// MARK: - Dope merge / resolve

/// DOPE_MERGE_PLAN — the per-element boundary plan for one scope. Read-only.
public struct DopeMergePlanRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    public init(scopeUuid: String) { self.scopeUuid = scopeUuid }
}

public struct DopeMergeOutcomeRow: Codable, Hashable, Sendable {
    public let dotPath: String
    public let kind: String
    public let decision: String
    public init(dotPath: String, kind: String, decision: String) {
        self.dotPath = dotPath
        self.kind = kind
        self.decision = decision
    }
}

public struct DopeMergePlanResponse: Codable, Hashable, Sendable {
    public let outcomes: [DopeMergeOutcomeRow]
    public let conflictCount: Int
    public init(outcomes: [DopeMergeOutcomeRow], conflictCount: Int) {
        self.outcomes = outcomes
        self.conflictCount = conflictCount
    }
}

/// DOPE_RESOLVE — settle conflicting dot-paths in one direction.
public struct DopeResolveRequest: Codable, Hashable, Sendable {
    public let scopeUuid: String
    /// nil = every unresolved conflict.
    public let dotPath: String?
    /// true keeps the db side, false takes the file side.
    public let takeOurs: Bool
    public init(scopeUuid: String, dotPath: String? = nil, takeOurs: Bool) {
        self.scopeUuid = scopeUuid
        self.dotPath = dotPath
        self.takeOurs = takeOurs
    }
}

public struct DopeResolveResponse: Codable, Hashable, Sendable {
    public let resolved: [String]
    public let takeOurs: Bool
    public init(resolved: [String], takeOurs: Bool) {
        self.resolved = resolved
        self.takeOurs = takeOurs
    }
}

// MARK: - Pen result budget (the generic oversize guard)

/// Excerpting policy shared by every stub in this file. One constant, so a
/// stub is the same size wherever it comes from.
public enum PenExcerpt {
    /// Long enough to recognize what a body is about; short enough that a
    /// hundred stubs still fit inside the result budget below.
    public static let chars = 400

    /// (excerpt, true length, whether anything was dropped). Character-based,
    /// never byte-based: an excerpt is shown to a reader, and clipping a
    /// grapheme in half would put mojibake in the record.
    public static func take(_ body: String, chars limit: Int = PenExcerpt.chars)
        -> (excerpt: String, chars: Int, truncated: Bool)
    {
        let total = body.count
        guard total > limit else { return (body, total, false) }
        return (String(body.prefix(limit)), total, true)
    }
}

/// What a pen read tool can be told to make itself smaller. Data, not prose,
/// so the guard below can quote it back to the caller in a form the caller
/// can act on without reading English.
public struct PenNarrowing: Codable, Hashable, Sendable {
    /// The tool's own argument names, in the order worth trying.
    public let parameters: [String]
    /// The exact next call to make.
    public let retryWith: String

    public init(parameters: [String], retryWith: String) {
        self.parameters = parameters
        self.retryWith = retryWith
    }
}

/// The machine-readable header stamped on an over-budget result. NEVER a
/// prose apology and NEVER a clipped JSON body: the failure mode being fixed
/// is a caller hand-parsing truncated JSON, so an over-budget read returns a
/// well-formed envelope that names the parameter which narrows THIS tool.
public struct PenOversizeNote: Codable, Hashable, Sendable {
    public let tool: String
    /// "degraded" = a narrowed payload rides along under `result`.
    /// "withheld" = even the narrowed form did not fit; there is no payload.
    /// "completed_degraded" / "completed_withheld" are the same two
    /// outcomes for a WRITE, and the prefix is load-bearing: the write landed,
    /// so the caller must read the result back rather than retry the call.
    public let outcome: String
    /// Size of the response the tool actually produced.
    public let bytes: Int
    /// Size of what is being returned instead (nil when withheld).
    public let degradedBytes: Int?
    public let budgetBytes: Int
    public let parameters: [String]
    public let retryWith: String

    public init(
        tool: String,
        outcome: String,
        bytes: Int,
        degradedBytes: Int?,
        budgetBytes: Int,
        parameters: [String],
        retryWith: String
    ) {
        self.tool = tool
        self.outcome = outcome
        self.bytes = bytes
        self.degradedBytes = degradedBytes
        self.budgetBytes = budgetBytes
        self.parameters = parameters
        self.retryWith = retryWith
    }
}

/// THE GENERIC RESPONSE-SIZE GUARD. Every pen read passes through here before
/// it is handed to the harness, because arch_get is merely the one that got
/// caught: a 79,598-character ARCH_GET was REFUSED for exceeding max tokens,
/// spilled to a file, and had to be hand-parsed from a body that had been cut
/// mid-array — so `persistence_changes` (which sorts after `options`) vanished
/// silently.
///
/// THRESHOLD. `maxBytes` is 45,000. The refusal ceiling is measured, not
/// guessed: 79,598 characters was refused, so the real per-result cap sits
/// below that. Taking the harness's 25,000-token result cap and a pessimistic
/// 2.5 bytes/token for pretty-printed JSON carrying escaped source code
/// (`\"`, `\n`, and identifiers that tokenize badly), 45,000 bytes is ~18,000
/// tokens — comfortably inside the cap with headroom for the MCP envelope,
/// and a little over half the size that actually got refused. Typical JSON
/// runs nearer 3.5 bytes/token, so the common case is ~13,000 tokens.
public enum PenResultBudget {
    public static let maxBytes = 45_000

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Render a tool result under the budget.
    ///
    /// 1. Fits → the payload verbatim, exactly as before.
    /// 2. Over → re-run `degrade` (the tool's own narrowed call) and return
    ///    `{"gmcc_oversize": <note>, "result": <narrowed payload>}`.
    /// 3. Still over, or nothing to degrade to → the note ALONE. A caller
    ///    that gets no `result` key knows it got no data, which is a fact it
    ///    can act on; a truncated body is a fact it cannot.
    public static func render(
        tool: String,
        narrowing: PenNarrowing?,
        value: any Encodable,
        isWrite: Bool = false,
        degrade: (() throws -> any Encodable)? = nil
    ) throws -> String {
        let encoder = encoder()
        let data = try encoder.encode(AnyEncodable(value))
        guard data.count > maxBytes else {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let parameters = narrowing?.parameters ?? []
        // A WRITE THAT REACHED HERE HAS ALREADY LANDED. `run` completed before
        // the result was rendered, so the row is in the db — which makes the
        // read-shaped advice ("call it again, narrower") the single thing the
        // caller must NOT do: these verbs append, so a retry writes a second
        // row. That is not hypothetical; this architecture's own record carries
        // a duplicate persistence row created exactly that way. So a write says
        // COMPLETED in its outcome and points at the read that shows the result.
        let retryWith: String
        if isWrite {
            let readBack = narrowing?.retryWith ?? "the matching get tool"
            retryWith = "the write COMPLETED and is recorded — do NOT retry it, "
                + "these verbs append and a second call writes a second row. "
                + "Read the result back with \(readBack)."
        } else {
            retryWith = narrowing?.retryWith
                ?? "this tool has no narrowing parameter — its result is one indivisible record; read it through a different tool or a narrower subject"
        }
        func stamp(_ base: String) -> String { isWrite ? "completed_\(base)" : base }

        if let degrade {
            let narrowed = try encoder.encode(AnyEncodable(try degrade()))
            if narrowed.count <= maxBytes {
                let note = PenOversizeNote(
                    tool: tool, outcome: stamp("degraded"), bytes: data.count,
                    degradedBytes: narrowed.count, budgetBytes: maxBytes,
                    parameters: parameters, retryWith: retryWith)
                return try envelope(note: note, payload: narrowed, encoder: encoder)
            }
            let note = PenOversizeNote(
                tool: tool, outcome: stamp("withheld"), bytes: data.count,
                degradedBytes: narrowed.count, budgetBytes: maxBytes,
                parameters: parameters, retryWith: retryWith)
            return try envelope(note: note, payload: nil, encoder: encoder)
        }
        let note = PenOversizeNote(
            tool: tool, outcome: stamp("withheld"), bytes: data.count,
            degradedBytes: nil, budgetBytes: maxBytes,
            parameters: parameters, retryWith: retryWith)
        return try envelope(note: note, payload: nil, encoder: encoder)
    }

    /// Compose note + optional payload into ONE well-formed JSON document.
    /// The payload is spliced as already-encoded bytes rather than re-encoded
    /// through JSONSerialization, so nothing in it can be reshaped on the way
    /// out.
    static func envelope(
        note: PenOversizeNote, payload: Data?, encoder: JSONEncoder
    ) throws -> String {
        let noteText = String(data: try encoder.encode(note), encoding: .utf8) ?? "{}"
        guard let payload, let payloadText = String(data: payload, encoding: .utf8) else {
            return "{\n  \"gmcc_oversize\" : \(noteText)\n}"
        }
        return "{\n  \"gmcc_oversize\" : \(noteText),\n  \"result\" : \(payloadText)\n}"
    }
}

/// Type-erasing shim so `any Encodable` can be handed to JSONEncoder.
struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeTo = { encoder in try wrapped.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}
