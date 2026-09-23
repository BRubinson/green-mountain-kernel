import Foundation

// Codable wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from
// WireCodec's key strategies — types declare NO CodingKeys (the two
// intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

// MARK: - Identity

/// The identity block wrapped into every domain table.
///
/// Defined once here; GRDB records declare these five columns flat because
/// GRDB flattens only top-level Codable properties into columns.
struct BaseEntity: Codable, Hashable, Sendable {
    /// Serial rowid — internal to the db, nil before insert.
    let id: Int64?
    /// v4 lowercase — the external join key shared with gmfs yamls and the wire.
    let uuid: String
    /// Incremented by the daemon on every write (optimistic concurrency —
    /// guarded updates require the caller's expected_version to match).
    let version: Int64
    let createdAt: String
    let updatedAt: String

    /// Creates an identity block with uuid, version, and timestamps.
    /// - Parameters:
    ///   - uuid: The external join key, v4 lowercase.
    ///   - version: The write counter; nil before first insert.
    ///   - createdAt: The row creation timestamp.
    ///   - updatedAt: The row last-write timestamp.
    ///   - id: The serial rowid, nil before insert.
    init(uuid: String, version: Int64, createdAt: String, updatedAt: String, id: Int64? = nil) {
        self.id = id
        self.uuid = uuid
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Kinds of rows in the append-only daemon_event table.
///
/// Stored as free text in the db; this enum is the write-path enforcement. On
/// the wire (events, EVENT_LIST) kind travels as a raw string so old clients
/// survive new kinds.
enum DaemonEventKind: String, Codable, Hashable, CaseIterable, Sendable {
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
    /// v29 — durable rows: the agent test mutex. Every claim, release and
    /// reclaim events, including a LAZY RECLAIM of a lock whose holder died.
    /// That last one is the reason this kind exists rather than the state
    /// living only in the mutable cell: a lock that silently changed hands
    /// because a process was SIGKILLed is exactly the history someone will
    /// need when two agents disagree about who was running what.
    case testLockChange = "TEST_LOCK_CHANGE"
}

/// The four registry levels a kbite can be activated at. rawValue drives the
/// `{scope}_active_kbite` / `{scope}_uuid` table and column names — the only
/// way dynamic SQL identifiers are ever built (enum-bound, no injection).
enum KbiteScope: String, Codable, Hashable, CaseIterable, Sendable {
    case project
    case instance
    case session
    case prompt
}

/// Where a KBITE_KEYWORD_TAG attach/detach lands: the kbite-level vocabulary
/// junction or the per-resource-file junction.
enum KeywordTagLevel: String, Codable, Hashable, CaseIterable, Sendable {
    case kbite
    case file
}

enum ChangeKind: String, Codable, Hashable, CaseIterable, Sendable {
    case edit
    case create
    case delete
    case rename
}

/// The prompt lifecycle: THREE states, a cycle rather than a ladder.
///
///     draft ⇄ initiated → done   (done → draft is the edit edge)
///
/// No gating on status; phase from db evidence at BOT_NEXT. Architecture
/// approval gates implementation. `done` IS NOT TERMINAL—done→draft reopens;
/// summary tables carry no per-prompt UNIQUE constraint: second run needs
/// second summary.
enum PromptStatus: String, Codable, Hashable, CaseIterable, Sendable {
    /// Not started, or sent back for editing.
    case draft
    /// The single working state. Stamped by BRIEFING_OPEN, not by an agent —
    /// whatever phase the prompt is in, the row says only that it is running.
    case initiated
    /// Finished. Releases the activation claim and closes the workflow row.
    case done

    /// The legal next states as an explicit set.
    ///
    /// Unlike v2 this graph is NOT forward-only: `done` returns to `draft`.
    /// Nothing else here gates — backing-summary requirements were removed from
    /// PromptRepository.setStatus with m0028, and summaries are now created by
    /// explicit opens (CLARIFY_OPEN, ARCH_OPTION_ADD, REVIEW_OPEN) rather than
    /// as a side effect of walking this enum.
    var allowedNext: Set<PromptStatus> {
        switch self {
        case .draft: return [.initiated]
        case .initiated: return [.done]
        case .done: return [.draft]
        }
    }
}

/// Clarification summary lifecycle: building → answering → complete, with one
/// backward revision edge (complete → answering, the `reopen` verb) so an
/// answer discovered wrong during architecting stays fixable db-natively.
enum ClarificationStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case building
    case answering
    case complete

    var allowedNext: Set<ClarificationStatus> {
        switch self {
        case .building: return [.answering]
        case .answering: return [.complete]
        case .complete: return [.answering]
        }
    }
}

/// One clarification row's answer state.
enum ClarificationRowStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case open
    case answered
    case skipped
}

/// Architecture summary lifecycle: drafting → proposed → approved, with one
/// backward revision edge (proposed → drafting, the `revise` verb). approved
/// is terminal and unlocks the prompt's architecting → implementing gate.
enum ArchitectureStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case drafting
    case proposed
    case approved

    var allowedNext: Set<ArchitectureStatus> {
        switch self {
        case .drafting: return [.proposed]
        case .proposed: return [.approved, .drafting]
        case .approved: return []
        }
    }
}

/// Fidelity of an architecture_general_change's change_code: sketch-level
/// pseudo code, near-code draft, or drop-in actual code.
enum ChangeDepth: String, Codable, Hashable, CaseIterable, Sendable {
    case pseudo
    case draft
    case actual
}

/// The daemon_config key space is enum-bound — an unknown key is BAD_REQUEST,
/// keeping config a typed subsystem rather than a free-form bag.
enum ConfigKey: String, Codable, Hashable, CaseIterable, Sendable {
    case gmFsRoot = "gmfs_root"
    case kbiteRoot = "kbite_root"
    case kbiteOpenRoot = "kbite_open_root"
    case kbiteDigestedRoot = "kbite_digested_root"
}

/// Column-only since v7: session.status was retired from the wire (every live
/// row read 'active' forever; checked-out state is git-derived via
/// SESSION_RESOLVE).
///
/// The enum documents the column's legal values.
enum SessionStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case active
    case closed
}

/// Exploration report lifecycle: exploring → complete, with one backward
/// revision edge (complete → exploring, the `reopen` verb) — explore is the
/// most re-run report (resume, team fallback), so re-runs update the same
/// summary db-natively (last-run-wins, like the file world it replaces).
enum ExplorationStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case exploring
    case complete

    var allowedNext: Set<ExplorationStatus> {
        switch self {
        case .exploring: return [.complete]
        case .complete: return [.exploring]
        }
    }
}

/// Review report lifecycle: reviewing → complete, with the same backward
/// revision edge as ExplorationStatus.
///
/// Named ReviewSummaryStatus so it can't be confused with ReviewFindingStatus
/// (the per-finding resolution machine).
enum ReviewSummaryStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case reviewing
    case complete

    var allowedNext: Set<ReviewSummaryStatus> {
        switch self {
        case .reviewing: return [.complete]
        case .complete: return [.reviewing]
        }
    }
}

/// What an exploration finding is about. `keyFile` (m0025) is the merged
/// exploration_key_file shape: a path-anchored finding with empty body.
enum ExplorationFindingKind: String, Codable, Hashable, CaseIterable, Sendable {
    case persistenceModel = "persistence_model"
    case implementationPattern = "implementation_pattern"
    case existingFunctionality = "existing_functionality"
    case scopeCreepRisk = "scope_creep_risk"
    case generalRelevantChange = "general_relevant_change"
    case keyFile = "key_file"
    case other
}

/// Per-agent exploration summary vocabulary (m0025).
///
/// The four methodology personas plus `general` (inline/rpi runs) and
/// `synthesis` — the prompt-level seal row the primary completes last (its
/// complete refuses while any finding across the prompt is unranked). CHECKless
/// in the db; this registry is the validity surface.
enum ExplorationAgentType: String, Codable, Hashable, CaseIterable, Sendable {
    case aggressive
    case conservative
    case pragmatic
    case alternative
    case general
    case synthesis
}

/// What a review finding is about.
enum ReviewFindingKind: String, Codable, Hashable, CaseIterable, Sendable {
    case correctnessBug = "correctness_bug"
    case specDeviation = "spec_deviation"
    case regressionRisk = "regression_risk"
    case security
    case simplification
    case other
}

/// The review's overall verdict, carried only by REVIEW_COMPLETE.
enum ReviewVerdict: String, Codable, Hashable, CaseIterable, Sendable {
    case approved
    case approvedWithNits = "approved_with_nits"
    case changesRequested = "changes_requested"
}

/// Per-finding resolution, recorded during the fix loop (which runs AFTER the
/// summary completes — the deliberate inversion of the clarify child-lock).
/// open → fixed | accepted | wont_fix, plus lateral correction edges among the
/// resolved values; never back to open.
enum ReviewFindingStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case open
    case fixed
    case accepted
    case wontFix = "wont_fix"

    var allowedNext: Set<ReviewFindingStatus> {
        switch self {
        case .open: return [.fixed, .accepted, .wontFix]
        case .fixed: return [.accepted, .wontFix]
        case .accepted: return [.fixed, .wontFix]
        case .wontFix: return [.fixed, .accepted]
        }
    }
}

/// One (finding, rating) pair of a batch rank.
///
/// Ratings run 0–999: 0 is an absolute critical finding, 999 an
/// always-false-positive tombstone; the consumption threshold sits at 100.
struct FindingRating: Codable, Hashable, Sendable {
    let findingUuid: String
    let rating: Int

    /// Creates a finding rating pair.
    /// - Parameters:
    ///   - findingUuid: The finding uuid being rated.
    ///   - rating: The rating, 0 to 999.
    init(findingUuid: String, rating: Int) {
        self.findingUuid = findingUuid
        self.rating = rating
    }
}

// MARK: - HELLO

struct Hello: Codable, Hashable, Sendable {
    let clientName: String
    let pid: Int32

    /// Creates a HELLO message.
    /// - Parameters:
    ///   - clientName: The name of the connecting client.
    ///   - pid: The process id of the client.
    init(clientName: String, pid: Int32) {
        self.clientName = clientName
        self.pid = pid
    }
}

struct HelloAck: Codable, Hashable, Sendable {
    let daemonPid: Int32
    let protocolVersion: Int

    /// Creates a HELLO acknowledgement.
    /// - Parameters:
    ///   - daemonPid: The process id of the daemon.
    ///   - protocolVersion: The protocol version the daemon speaks.
    init(daemonPid: Int32, protocolVersion: Int) {
        self.daemonPid = daemonPid
        self.protocolVersion = protocolVersion
    }
}

// MARK: - TX_BATCH

/// N inner request lines, executed in order inside ONE transaction.
///
/// The inner lines stay RAW NDJSON: a typed union over the ~230 dispatchable
/// requests would be a second vocabulary that could drift from `MessageType`,
/// and keeping them opaque means this verb needs no knowledge of what it
/// carries. Atomicity is the point — each verb is otherwise its own implicit
/// transaction, so twelve findings are twelve commits and a failure at the
/// seventh leaves six behind.
struct TxBatchRequest: Codable, Hashable, Sendable {
    /// Raw NDJSON request lines, executed in order.
    let requests: [String]

    /// Creates a batch request for transactional execution.
    /// - Parameter requests: The raw NDJSON request lines.
    init(requests: [String]) {
        self.requests = requests
    }
}

/// Result envelope for `TX_BATCH`.
///
/// Results are BUFFERED and emitted only after the commit, so a partial batch
/// is not expressible to an observer any more than it is to the database.
/// THERE IS NO `failedIndex` FIELD: a failure THROWS and a throw carries no
/// payload, so the failing index is named in the error MESSAGE instead.
struct TxBatchResponse: Codable, Hashable, Sendable {
    /// Raw NDJSON result lines, one per request, in request order.
    ///
    /// Present only on success, because a rolled-back batch throws.
    let results: [String]

    /// Creates a batch response with result lines.
    /// - Parameter results: The raw NDJSON result lines.
    init(results: [String]) {
        self.results = results
    }
}

// MARK: - PING

struct PingRequest: Codable, Hashable, Sendable {
    /// Creates a PING request.
    init() {}
}

struct PingResponse: Codable, Hashable, Sendable {
    let daemonPid: Int32
    let protocolVersion: Int
    let buildSha: String
    let buildDate: String
    let startedAt: String
    let uptimeSeconds: Int
    /// Resident footprint, from `task_info`/`TASK_VM_INFO` `phys_footprint`.
    ///
    /// The vitals ride the WIRE rather than being read in-process, and that is
    /// deliberate: a kernel that lost the ownership lock runs CLIENT-ONLY with
    /// no store of its own, and its menu bar still has to show the numbers. An
    /// in-process-only source would go blank in exactly the mode that most
    /// needs to explain itself.
    let residentMemoryBytes: UInt64?
    /// CPU percentage, from a `proc_pid_rusage` delta.
    let cpuPercent: Double?
    /// `"writer"` | `"client"` — which role the answering kernel holds.
    ///
    /// Client mode is the mitigation for a second app copy, chosen over a hard
    /// refusal because a refusal on the daily Xcode-debug path is a guard that
    /// gets deleted. A mitigation nobody can see is cosmetic, so the role is
    /// reportable.
    let writerRole: String?
    /// Bundle path of the instance actually holding the db lock, so a
    /// client-mode kernel can name BOTH bundles rather than only its own.
    let writerBundlePath: String?
    /// The filesystem root this kernel actually resolved.
    ///
    /// With several environments on a machine a client that cannot ask has to
    /// GUESS from its own environment, which is the guess that is wrong for a
    /// LaunchServices-launched app: it inherits no environment at all. An
    /// additive optional, so nil means the peer does not report its root.
    let gmfsRoot: String?

    /// Creates a PING response with daemon details and optional vitals.
    /// - Parameters:
    ///   - daemonPid: The process id of the daemon.
    ///   - protocolVersion: The protocol version the daemon speaks.
    ///   - buildSha: The build's git commit hash.
    ///   - buildDate: The date the daemon binary was built.
    ///   - startedAt: The timestamp when the daemon started.
    ///   - uptimeSeconds: The number of seconds the daemon has been running.
    ///   - residentMemoryBytes: The resident footprint from `task_info`; nil if not available.
    ///   - cpuPercent: The CPU percentage from `proc_pid_rusage` delta; nil if not available.
    ///   - writerRole: `"writer"` or `"client"` for the daemon's role; nil if not available.
    ///   - writerBundlePath: The bundle path of the instance holding the db lock; nil if not available.
    ///   - gmfsRoot: The filesystem root the kernel resolved; nil if not reported.
    init(
        daemonPid: Int32,
        protocolVersion: Int,
        buildSha: String,
        buildDate: String,
        startedAt: String,
        uptimeSeconds: Int,
        residentMemoryBytes: UInt64? = nil,
        cpuPercent: Double? = nil,
        writerRole: String? = nil,
        writerBundlePath: String? = nil,
        gmfsRoot: String? = nil
    ) {
        self.daemonPid = daemonPid
        self.protocolVersion = protocolVersion
        self.buildSha = buildSha
        self.buildDate = buildDate
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.residentMemoryBytes = residentMemoryBytes
        self.cpuPercent = cpuPercent
        self.writerRole = writerRole
        self.writerBundlePath = writerBundlePath
        self.gmfsRoot = gmfsRoot
    }
}

// MARK: - STATUS

struct StatusRequest: Codable, Hashable, Sendable {
    /// Creates a STATUS request.
    init() {}
}

/// One table's row count.
///
/// An array of pairs rather than [String: Int] because the coder key
/// strategies rewrite dictionary String keys ("prompt_artifact" would decode as
/// "promptArtifact"); an array is immune and stays sorted.
struct TableCount: Codable, Hashable, Sendable {
    let name: String
    let count: Int

    /// Creates a row count for one table.
    /// - Parameters:
    ///   - name: The table name.
    ///   - count: The number of rows in the table.
    init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

struct StatusResponse: Codable, Hashable, Sendable {
    let daemonPid: Int32
    let protocolVersion: Int
    let socketPath: String
    let dbPath: String
    let schemaVersion: Int
    /// Row census only — MUST NOT be used as an event cursor; use
    /// `lastEventId` for that.
    let tableCounts: [TableCount]
    /// The real event-log horizon: highest daemon_event.id at status time.
    let lastEventId: Int64
    let startedAt: String
    let uptimeSeconds: Int
    /// Vitals and role, in parity with `PingResponse` so the menu bar has ONE
    /// shape to read whichever verb it polls.
    ///
    /// All four are additive optionals and contribute no protocol bump — see the
    /// v28 note in `GmWireProtocol`.
    let residentMemoryBytes: UInt64?
    let cpuPercent: Double?
    let writerRole: String?
    let writerBundlePath: String?

    /// Creates a STATUS response with daemon status and database information.
    /// - Parameters:
    ///   - daemonPid: The process id of the daemon.
    ///   - protocolVersion: The protocol version the daemon speaks.
    ///   - socketPath: The path to the daemon's socket.
    ///   - dbPath: The path to the database file.
    ///   - schemaVersion: The current schema version.
    ///   - tableCounts: Row counts for each table.
    ///   - lastEventId: The highest daemon_event id at status time.
    ///   - startedAt: The timestamp when the daemon started.
    ///   - uptimeSeconds: The number of seconds the daemon has been running.
    ///   - residentMemoryBytes: The resident footprint; nil if not available.
    ///   - cpuPercent: The CPU percentage; nil if not available.
    ///   - writerRole: `"writer"` or `"client"` for the daemon's role; nil if not available.
    ///   - writerBundlePath: The bundle path of the instance holding the db lock; nil if not available.
    init(
        daemonPid: Int32,
        protocolVersion: Int,
        socketPath: String,
        dbPath: String,
        schemaVersion: Int,
        tableCounts: [TableCount],
        lastEventId: Int64,
        startedAt: String,
        uptimeSeconds: Int,
        residentMemoryBytes: UInt64? = nil,
        cpuPercent: Double? = nil,
        writerRole: String? = nil,
        writerBundlePath: String? = nil
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
        self.residentMemoryBytes = residentMemoryBytes
        self.cpuPercent = cpuPercent
        self.writerRole = writerRole
        self.writerBundlePath = writerBundlePath
    }
}

// MARK: - SHUTDOWN

struct ShutdownRequest: Codable, Hashable, Sendable {
    /// Creates a SHUTDOWN request.
    init() {}
}

struct ShutdownResponse: Codable, Hashable, Sendable {
    let message: String

    /// Creates a SHUTDOWN acknowledgement.
    /// - Parameter message: The shutdown confirmation message.
    init(message: String) {
        self.message = message
    }
}

// MARK: - SUBSCRIBE / EVENT

struct Subscribe: Codable, Hashable, Sendable {
    /// Replay cursor: daemon_event.id of the last event the subscriber has
    /// seen.
    ///
    /// Events with id > since_id are replayed before live streaming begins. nil
    /// = live-only from now.
    let sinceId: Int64?

    /// Creates a SUBSCRIBE message with optional event replay.
    /// - Parameter sinceId: The last event id seen; nil for live-only streaming.
    init(sinceId: Int64? = nil) {
        self.sinceId = sinceId
    }
}

struct SubscribeAck: Codable, Hashable, Sendable {
    /// The replay horizon: highest daemon_event.id at subscribe time.
    ///
    /// Replayed EVENT lines (ids ≤ this) follow the ack, then live events
    /// stream.
    let lastEventId: Int64
    let replayCount: Int

    /// Creates a SUBSCRIBE acknowledgement.
    /// - Parameters:
    ///   - lastEventId: The highest daemon_event id at subscribe time.
    ///   - replayCount: The number of events to be replayed.
    init(lastEventId: Int64, replayCount: Int) {
        self.lastEventId = lastEventId
        self.replayCount = replayCount
    }
}

/// Unsolicited daemon → subscriber notification mirroring a daemon_event row.
/// `id` is the durable reconnect cursor (created_at is seconds-precision and
/// ties — display/coarse filter only, never a cursor). `kind` is a raw string
/// so rows with kinds added later never break older clients.
struct EventNotification: Codable, Hashable, Sendable {
    let id: Int64
    let kind: String
    let subjectUuid: String?
    let payload: String?
    let createdAt: String

    var eventKind: DaemonEventKind? { DaemonEventKind(rawValue: kind) }

    /// Creates an event notification mirroring a daemon_event row.
    /// - Parameters:
    ///   - id: The event id, the durable reconnect cursor.
    ///   - kind: The event kind as a raw string.
    ///   - createdAt: The timestamp when the event was created.
    ///   - subjectUuid: The uuid of the affected entity; nil if not applicable.
    ///   - payload: The event payload as a raw string; nil if not applicable.
    init(id: Int64, kind: String, createdAt: String, subjectUuid: String? = nil, payload: String? = nil) {
        self.id = id
        self.kind = kind
        self.subjectUuid = subjectUuid
        self.payload = payload
        self.createdAt = createdAt
    }
}

// MARK: - BACKUP

struct BackupRequest: Codable, Hashable, Sendable {
    /// Creates a BACKUP request.
    init() {}
}

struct BackupResponse: Codable, Hashable, Sendable {
    let backupPath: String
    let sizeBytes: Int64

    /// Creates a BACKUP response.
    /// - Parameters:
    ///   - backupPath: The path to the backup file.
    ///   - sizeBytes: The size of the backup in bytes.
    init(backupPath: String, sizeBytes: Int64) {
        self.backupPath = backupPath
        self.sizeBytes = sizeBytes
    }
}

// MARK: - Context blocks

/// Context blocks let the daemon lazily ensure the project → instance →
/// session chain exists. Where the gmfs already carries a uuid, the caller
/// passes it so the db row reuses it (trivial db ↔ gmfs joins). Optional
/// kbite_codes seed that level's active-kbite registry at CREATE time only —
/// mirroring gm_session_startup.sh's inherit_kbite (existing rows are never
/// re-seeded; a child created without codes copies its parent's junctions).

struct ProjectContext: Codable, Hashable, Sendable {
    let gitRepoName: String
    let code: String
    let name: String
    let gmfsRelativeStoragePath: String
    let uuid: String?
    let kbiteCodes: [String]?

    /// Creates a project context for lazy chain initialization.
    /// - Parameters:
    ///   - gitRepoName: The git repository name.
    ///   - code: The project code.
    ///   - name: The project name.
    ///   - gmfsRelativeStoragePath: The relative path in gmfs.
    ///   - uuid: The gmfs uuid if known; nil to auto-generate.
    ///   - kbiteCodes: The kbite codes to activate; nil to skip seeding.
    init(
        gitRepoName: String,
        code: String,
        name: String,
        gmfsRelativeStoragePath: String,
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.gitRepoName = gitRepoName
        self.code = code
        self.name = name
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

struct InstanceContext: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let absoluteFileSystemPath: String
    let gmfsRelativeStoragePath: String
    let uuid: String?
    let kbiteCodes: [String]?

    /// Creates an instance context for lazy chain initialization.
    /// - Parameters:
    ///   - code: The instance code.
    ///   - name: The instance name.
    ///   - absoluteFileSystemPath: The absolute path to the repository.
    ///   - gmfsRelativeStoragePath: The relative path in gmfs.
    ///   - uuid: The gmfs uuid if known; nil to auto-generate.
    ///   - kbiteCodes: The kbite codes to activate; nil to skip seeding.
    init(
        code: String,
        name: String,
        absoluteFileSystemPath: String,
        gmfsRelativeStoragePath: String,
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.code = code
        self.name = name
        self.absoluteFileSystemPath = absoluteFileSystemPath
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

struct SessionContext: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let backstory: String
    let goal: String
    let gmfsRelativeStoragePath: String
    let uuid: String?
    let kbiteCodes: [String]?

    /// Creates a session context for lazy chain initialization.
    /// - Parameters:
    ///   - code: The session code.
    ///   - name: The session name.
    ///   - gmfsRelativeStoragePath: The relative path in gmfs.
    ///   - backstory: The session backstory; empty string by default.
    ///   - goal: The session goal; empty string by default.
    ///   - uuid: The gmfs uuid if known; nil to auto-generate.
    ///   - kbiteCodes: The kbite codes to activate; nil to skip seeding.
    init(
        code: String,
        name: String,
        gmfsRelativeStoragePath: String,
        backstory: String = "",
        goal: String = "",
        uuid: String? = nil,
        kbiteCodes: [String]? = nil
    ) {
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.uuid = uuid
        self.kbiteCodes = kbiteCodes
    }
}

// MARK: - CONTEXT_ENSURE / CONTEXT_GET

struct ContextEnsureRequest: Codable, Hashable, Sendable {
    let project: ProjectContext
    let instance: InstanceContext
    let session: SessionContext
    /// Claude Code's conversation uuid, from the SessionStart payload.
    ///
    /// When present the daemon pins it to the ensured session in
    /// claude_session_binding, the binding every hook write resolves through.
    /// IT RIDES THIS MESSAGE rather than taking a verb of its own, so the
    /// binding cannot be forgotten independently of the call that creates the
    /// session it points at. The insert is INSERT OR IGNORE against a UNIQUE
    /// index, so pin-once is a schema fact rather than a caller's branch.
    let claudeSessionId: String?

    /// Creates a CONTEXT_ENSURE request to lazily initialize the project-instance-session chain.
    /// - Parameters:
    ///   - project: The project context.
    ///   - instance: The instance context.
    ///   - session: The session context.
    ///   - claudeSessionId: The Claude Code conversation uuid to bind to the session; nil if not applicable.
    init(
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

struct ContextEnsureResponse: Codable, Hashable, Sendable {
    let projectUuid: String
    let instanceUuid: String
    let sessionUuid: String
    let createdProject: Bool
    let createdInstance: Bool
    let createdSession: Bool
    /// How many `claude_session_binding` rows exist for this session.
    ///
    /// Captures MCP health; only visibility here. Zero = no bound Claude
    /// conversation, so PostToolUse hook cannot attribute, file-change capture
    /// is silently OFF. Stdio MCP server gets only CLAUDE_PROJECT_DIR, cannot
    /// read `claude_session_id`, so this count is essential. Optional, so an
    /// older client decodes unchanged.
    let claudeSessionBindingCount: Int?

    /// Creates a CONTEXT_ENSURE response with created entities and binding count.
    /// - Parameters:
    ///   - projectUuid: The project uuid.
    ///   - instanceUuid: The instance uuid.
    ///   - sessionUuid: The session uuid.
    ///   - createdProject: True if the project row was created.
    ///   - createdInstance: True if the instance row was created.
    ///   - createdSession: True if the session row was created.
    ///   - claudeSessionBindingCount: The number of `claude_session_binding` rows; nil if not available.
    init(
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
struct ContextGetRequest: Codable, Hashable, Sendable {
    let projectCode: String
    let instanceName: String
    let sessionCode: String

    /// Creates a CONTEXT_GET request to resolve the current gmcc environment.
    /// - Parameters:
    ///   - projectCode: The project code.
    ///   - instanceName: The instance name.
    ///   - sessionCode: The session code.
    init(projectCode: String, instanceName: String, sessionCode: String) {
        self.projectCode = projectCode
        self.instanceName = instanceName
        self.sessionCode = sessionCode
    }
}

struct ContextGetResponse: Codable, Hashable, Sendable {
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    /// Session-level active kbite codes, resolved from the junction table.
    let kbiteCodes: [String]

    /// Creates a CONTEXT_GET response with resolved uuids and kbite codes.
    /// - Parameters:
    ///   - projectUuid: The project uuid; nil if not found.
    ///   - instanceUuid: The instance uuid; nil if not found.
    ///   - sessionUuid: The session uuid; nil if not found.
    ///   - kbiteCodes: The active kbite codes at the session level.
    init(projectUuid: String?, instanceUuid: String?, sessionUuid: String?, kbiteCodes: [String]) {
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.kbiteCodes = kbiteCodes
    }
}

// MARK: - PROJECT_LIST / INSTANCE_LIST / SESSION_LIST

/// Enumerate all projects — the entry point of the Landing browse chain.
struct ProjectListRequest: Codable, Hashable, Sendable {
    /// Creates a PROJECT_LIST request.
    init() {}
}

struct ProjectListResponse: Codable, Hashable, Sendable {
    let projects: [ProjectRow]

    /// Creates a PROJECT_LIST response.
    /// - Parameter projects: The list of project rows.
    init(projects: [ProjectRow]) {
        self.projects = projects
    }
}

/// PROJECT_UPDATE — the only project-level mutation. `primaryProjectBranch`
/// is Optional so the request shape can grow more settable fields without a
/// wire bump; an all-nil request is EMPTY_UPDATE, never a silent no-op.
struct ProjectUpdateRequest: Codable, Hashable, Sendable {
    let projectUuid: String
    let expectedVersion: Int64
    let primaryProjectBranch: String?

    /// Creates a PROJECT_UPDATE request to modify project settings.
    /// - Parameters:
    ///   - projectUuid: The project uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - primaryProjectBranch: The primary branch to set; nil to leave unchanged.
    init(
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
struct ProjectResponse: Codable, Hashable, Sendable {
    let project: ProjectRow

    /// Creates a project response with the refreshed row.
    /// - Parameter project: The updated project row.
    init(project: ProjectRow) {
        self.project = project
    }
}

/// Enumerate instances. `projectUuid` is an optional filter — nil lists every
/// instance (rows carry their parent uuid); a supplied-but-unknown uuid is
/// NOT_FOUND, never a silent empty list.
struct InstanceListRequest: Codable, Hashable, Sendable {
    let projectUuid: String?

    /// Creates an INSTANCE_LIST request.
    /// - Parameter projectUuid: The project to filter by; nil lists all instances.
    init(projectUuid: String? = nil) {
        self.projectUuid = projectUuid
    }
}

struct InstanceListResponse: Codable, Hashable, Sendable {
    let instances: [InstanceRow]

    /// Creates an INSTANCE_LIST response.
    /// - Parameter instances: The list of instance rows.
    init(instances: [InstanceRow]) {
        self.instances = instances
    }
}

/// Enumerate sessions.
///
/// Same optional-filter contract as INSTANCE_LIST.
struct SessionListRequest: Codable, Hashable, Sendable {
    let instanceUuid: String?

    /// Creates a SESSION_LIST request.
    /// - Parameter instanceUuid: The instance to filter by; nil lists all sessions.
    init(instanceUuid: String? = nil) {
        self.instanceUuid = instanceUuid
    }
}

struct SessionListResponse: Codable, Hashable, Sendable {
    let sessions: [SessionStub]

    /// Creates a SESSION_LIST response.
    /// - Parameter sessions: The list of session stubs.
    init(sessions: [SessionStub]) {
        self.sessions = sessions
    }
}

// MARK: - SESSION_GET / SESSION_UPDATE

struct SessionGetRequest: Codable, Hashable, Sendable {
    let sessionUuid: String

    /// Creates a SESSION_GET request.
    /// - Parameter sessionUuid: The session to retrieve.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

struct SessionGetResponse: Codable, Hashable, Sendable {
    let session: SessionRow
    let prompts: [PromptStub]
    let changeSummary: ChangeSummary
    /// Per-prompt change summaries (promptUuid nil = unattributed changes).
    ///
    /// Empty until file changes carry prompt attribution — run context is
    /// deferred from MVP, so entries may only appear via --prompt-uuid.
    let promptChanges: [PromptChangeSummary]

    /// Creates a SESSION_GET response with the session and its contents.
    /// - Parameters:
    ///   - session: The session row.
    ///   - prompts: The prompts in this session.
    ///   - changeSummary: The overall file change summary.
    ///   - promptChanges: The per-prompt change summaries.
    init(
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
struct SessionUpdateRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let expectedVersion: Int64
    let name: String?
    let backstory: String?
    let goal: String?
    /// v21-era additive OPTIONAL fields (no bump needed): manual override of
    /// the activation claim that PROMPT_SET_STATUS normally maintains for the
    /// calling Claude instance. activePromptUuid claims for clientKey;
    /// clearActivePrompt releases clientKey's claim.
    ///
    /// Exactly one of the pair.
    let activePromptUuid: String?
    let clearActivePrompt: Bool?
    /// The calling instance's identity (gm resolves it from process
    /// ancestry); required when either activation field is set.
    let clientKey: String?

    /// Creates a SESSION_UPDATE request to modify session fields and activation state.
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - name: The session name; nil to leave unchanged.
    ///   - backstory: The session backstory; nil to leave unchanged.
    ///   - goal: The session goal; nil to leave unchanged.
    ///   - activePromptUuid: The prompt uuid to activate; nil to leave unchanged.
    ///   - clearActivePrompt: True to release the activation claim; nil to leave unchanged.
    ///   - clientKey: The calling client's identity when using activation fields.
    init(
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

struct PromptCreateRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    /// Optional gmfs uuid pass-through (db ↔ gmfs join bridge).
    let uuid: String?
    /// Defaults to "p{seq}" when nil.
    let code: String?
    let name: String
    let backstory: String
    let goal: String
    let detail: String
    let command: String?
    let gmfsRelativeStoragePath: String?

    /// Creates a PROMPT_CREATE request to add a new prompt to a session.
    /// - Parameters:
    ///   - sessionUuid: The parent session uuid.
    ///   - name: The prompt name.
    ///   - uuid: The gmfs uuid if known; nil to auto-generate.
    ///   - code: The prompt code; nil defaults to "p{seq}".
    ///   - backstory: The prompt backstory; empty string by default.
    ///   - goal: The prompt goal; empty string by default.
    ///   - detail: The prompt detail; empty string by default.
    ///   - command: The bot command if applicable; nil if not.
    ///   - gmfsRelativeStoragePath: The relative path in gmfs; nil if not applicable.
    init(
        sessionUuid: String,
        name: String,
        uuid: String? = nil,
        code: String? = nil,
        backstory: String = "",
        goal: String = "",
        detail: String = "",
        command: String? = nil,
        gmfsRelativeStoragePath: String? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.uuid = uuid
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.detail = detail
        self.command = command
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
    }
}

/// `sessionUuid` is an optional filter (same contract as INSTANCE_LIST /
/// SESSION_LIST): nil lists every prompt in the db (stubs carry their parent
/// session uuid); a supplied-but-unknown uuid is NOT_FOUND, never a silent
/// empty list.
struct PromptListRequest: Codable, Hashable, Sendable {
    let sessionUuid: String?
    /// When true each stub carries its `reports` enrichment block (one call
    /// replaces the per-prompt CLARIFY_GET/ARCH_GET fan-out).
    ///
    /// Optional so a v8 client omitting it decodes as false.
    let withReports: Bool?

    /// Creates a PROMPT_LIST request.
    /// - Parameters:
    ///   - sessionUuid: The session to filter by; nil lists all prompts.
    ///   - withReports: True to include report enrichment; nil defaults to false.
    init(sessionUuid: String? = nil, withReports: Bool? = nil) {
        self.sessionUuid = sessionUuid
        self.withReports = withReports
    }
}

struct PromptListResponse: Codable, Hashable, Sendable {
    let prompts: [PromptStub]

    /// Creates a PROMPT_LIST response.
    /// - Parameter prompts: The list of prompt stubs.
    init(prompts: [PromptStub]) {
        self.prompts = prompts
    }
}

struct PromptGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates a PROMPT_GET request.
    /// - Parameter promptUuid: The prompt to retrieve.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct PromptGetResponse: Codable, Hashable, Sendable {
    let prompt: PromptRow
    let artifacts: [ArtifactRow]
    let kbiteCodes: [String]
    let changeSummary: ChangeSummary

    /// Creates a PROMPT_GET response with the prompt and its contents.
    /// - Parameters:
    ///   - prompt: The prompt row.
    ///   - artifacts: The artifacts in this prompt.
    ///   - kbiteCodes: The active kbite codes.
    ///   - changeSummary: The file change summary.
    init(prompt: PromptRow, artifacts: [ArtifactRow], kbiteCodes: [String], changeSummary: ChangeSummary) {
        self.prompt = prompt
        self.artifacts = artifacts
        self.kbiteCodes = kbiteCodes
        self.changeSummary = changeSummary
    }
}

// MARK: - PROMPT_UPDATE_CONTENT / PROMPT_SET_STATUS

/// Draft-only edit of exactly the STAY TRUE triple (backstory/goal/detail).
///
/// The daemon rejects with CONTENT_LOCKED once the prompt leaves draft.
struct PromptUpdateContentRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let expectedVersion: Int64
    let backstory: String?
    let goal: String?
    let detail: String?

    /// Creates a PROMPT_UPDATE_CONTENT request for draft-only edits.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - backstory: The new backstory; nil to leave unchanged.
    ///   - goal: The new goal; nil to leave unchanged.
    ///   - detail: The new detail; nil to leave unchanged.
    init(
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

struct PromptSetStatusRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let expectedVersion: Int64
    let status: PromptStatus
    /// v21-era additive OPTIONAL (no bump): the calling Claude instance's
    /// identity, resolved from process ancestry by gm.
    ///
    /// Entering implementing claims an activation for this key; done releases
    /// the prompt's claim.
    let clientKey: String?

    /// Creates a PROMPT_SET_STATUS request to change the prompt state.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - status: The new status.
    ///   - clientKey: The calling client's identity for activation tracking.
    init(
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

/// Register a file pointer for a bot-phase memory/ file.
///
/// Content stays in the file; the daemon stores only the pointer.
struct ArtifactAddRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let filePath: String
    let note: String?

    /// Creates an ARTIFACT_ADD request to register a memory file pointer.
    /// - Parameters:
    ///   - promptUuid: The parent prompt uuid.
    ///   - filePath: The path to the artifact file.
    ///   - note: An optional note about the artifact.
    init(promptUuid: String, filePath: String, note: String? = nil) {
        self.promptUuid = promptUuid
        self.filePath = filePath
        self.note = note
    }
}

struct ArtifactListRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates an ARTIFACT_LIST request.
    /// - Parameter promptUuid: The prompt to list artifacts for.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct ArtifactListResponse: Codable, Hashable, Sendable {
    let artifacts: [ArtifactRow]

    /// Creates an ARTIFACT_LIST response.
    /// - Parameter artifacts: The list of artifact rows.
    init(artifacts: [ArtifactRow]) {
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
struct PromptQualifiedDiagramRow: Codable, Hashable, Sendable {
    let uuid: String
    let promptUuid: String
    let diagramUuid: String
    let renderedPath: String
    let renderedRevision: Int64
    let renderFingerprint: String
    let qualification: String
    let version: Int64
    let createdAt: String
    let updatedAt: String

    /// Creates a prompt-diagram qualification record with render metadata.
    /// - Parameters:
    ///   - uuid: The qualification row uuid.
    ///   - promptUuid: The parent prompt uuid.
    ///   - diagramUuid: The diagram uuid.
    ///   - renderedPath: The path to the rendered diagram.
    ///   - renderedRevision: The render revision number.
    ///   - renderFingerprint: The serialized render fingerprint as JSON text.
    ///   - qualification: The qualification text.
    ///   - version: The row version for optimistic concurrency.
    ///   - createdAt: The row creation timestamp.
    ///   - updatedAt: The row last-write timestamp.
    init(
        uuid: String,
        promptUuid: String,
        diagramUuid: String,
        renderedPath: String,
        renderedRevision: Int64,
        renderFingerprint: String,
        qualification: String,
        version: Int64,
        createdAt: String,
        updatedAt: String
    ) {
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

/// Record (or replace) what this prompt makes of this diagram.
///
/// UPSERT on (prompt, diagram): no expected_version, because the pair is the
/// identity and the newer reading is by definition the one that stands.
struct PromptDiagramQualifyRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let diagramUuid: String
    let renderedPath: String
    let renderedRevision: Int64
    let renderFingerprint: String
    let qualification: String

    /// Creates a PROMPT_DIAGRAM_QUALIFY request to record a diagram qualification.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - diagramUuid: The diagram uuid.
    ///   - renderedPath: The path to the rendered diagram.
    ///   - renderedRevision: The render revision number.
    ///   - renderFingerprint: The serialized render fingerprint as JSON text.
    ///   - qualification: The qualification text.
    init(
        promptUuid: String,
        diagramUuid: String,
        renderedPath: String,
        renderedRevision: Int64,
        renderFingerprint: String,
        qualification: String
    ) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
        self.renderedPath = renderedPath
        self.renderedRevision = renderedRevision
        self.renderFingerprint = renderFingerprint
        self.qualification = qualification
    }
}

/// One qualification.
///
/// With `diagramUuid` it is the pair; without, it is the prompt's only
/// qualification — and an ambiguous ask (several exist) is a badRequest
/// pointing at the list verb rather than an arbitrary pick.
struct PromptDiagramGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let diagramUuid: String?

    /// Creates a PROMPT_DIAGRAM_GET request.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - diagramUuid: The diagram uuid; nil to get the only qualification.
    init(promptUuid: String, diagramUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.diagramUuid = diagramUuid
    }
}

struct PromptDiagramListRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates a PROMPT_DIAGRAM_LIST request.
    /// - Parameter promptUuid: The prompt to list qualifications for.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct PromptDiagramListResponse: Codable, Hashable, Sendable {
    let qualifications: [PromptQualifiedDiagramRow]

    /// Creates a PROMPT_DIAGRAM_LIST response.
    /// - Parameter qualifications: The list of qualified diagram rows.
    init(qualifications: [PromptQualifiedDiagramRow]) {
        self.qualifications = qualifications
    }
}

// MARK: - FILE_CHANGE_ADD

struct ChangeRange: Codable, Hashable, Sendable {
    let lineStart: Int
    let lineEnd: Int
    let changedContent: String?

    /// Creates a line range with optional changed content.
    /// - Parameters:
    ///   - lineStart: The starting line number.
    ///   - lineEnd: The ending line number.
    ///   - changedContent: The changed content if applicable; nil if not.
    init(lineStart: Int, lineEnd: Int, changedContent: String? = nil) {
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.changedContent = changedContent
    }
}

/// The primary high-frequency message. Carries full context blocks so the
/// ensure chain can run lazily, rather than uuid addressing, which would
/// couple callers to call order.

/// The `file_change.origin` vocabulary — ONE declaration, read by the guard in
/// FileChangeRepository.add, by the writers that stamp it, and by the
/// `agentics.enums.file_change_origin` dope entity that mirrors it.
///
/// The column has NO CHECK constraint, so THIS LIST IS THE CONSTRAINT: extend
/// it and the dope enum together, or every write of the new value throws. The
/// absent CHECK is also what lets the list shrink — rows written under a wider
/// vocabulary still read back, while a value absent here cannot be written.
enum FileChangeOrigin {
    /// PostToolUse Edit|Write|NotebookEdit — exact paths and exact
    /// structuredPatch ranges, straight off the payload.
    static let hook = "hook"
    /// Recorded by hand through `gm file-change add` or the pen tool.
    static let manual = "manual"
    /// INFERRED from the paths a Bash command NAMED (the write allowlist).
    ///
    /// Its own member rather than a `hook` row with tool_name=Bash: an
    /// inference must never be indistinguishable from an exact structuredPatch
    /// row, and every consumer can filter on it.
    static let command = "command"

    /// The accepted set, in documentation order.
    ///
    /// The guard's error detail is generated from this — never hand-written.
    static let all: [String] = [hook, manual, command]

    /// `hook|manual|command` — for help text and error details.
    static var vocabulary: String { all.joined(separator: "|") }
}

struct FileChangeAdd: Codable, Hashable, Sendable {
    let project: ProjectContext
    let instance: InstanceContext
    let session: SessionContext
    let promptUuid: String?
    let relativePath: String
    let changeKind: ChangeKind
    let ranges: [ChangeRange]
    /// When autoAttribute is true and promptUuid is nil, the daemon resolves
    /// the prompt itself.
    ///
    /// OPT-IN; "omitted means deliberately session-scoped" stays intact. No
    /// clientKey on this message—by design. Hook-origin write resolves through
    /// claude_session_binding, never ClientKey activation ladder; process
    /// ancestry cannot distinguish sibling subagents, so no field blocks hook
    /// write reach.
    let autoAttribute: Bool?
    /// Agent identity is SELF-REPORTED, because nothing on the transport
    /// distinguishes sibling subagents. origin is one of
    /// `FileChangeOrigin.all`, nil meaning the db default. workflow_phase is
    /// NEVER taken from the caller: the daemon stamps it from the attributed
    /// prompt's active bot_workflow.
    let agentId: String?
    let agentName: String?
    let origin: String?
    /// The PostToolUse payload, one field per column rather than a blob so
    /// every axis stays queryable.
    ///
    /// All OPTIONAL; manual carries none. claudeTurnId = payload's `prompt_id`,
    /// Claude Code's TURN id, unrelated to gmcc prompt uuid. toolUseId =
    /// idempotency key, paired with resolved session_file; (tool call, file)
    /// unit; replay returns EXISTING row with `deduplicated` set.
    let claudeSessionId: String?
    let claudeTurnId: String?
    let toolUseId: String?
    let toolName: String?
    let agentType: String?
    let permissionMode: String?
    let durationMs: Int?
    let transcriptPath: String?

    /// Creates a FILE_CHANGE_ADD request to record a file modification.
    /// - Parameters:
    ///   - project: The project context.
    ///   - instance: The instance context.
    ///   - session: The session context.
    ///   - relativePath: The file path relative to the repository root.
    ///   - changeKind: The type of change (edit, create, delete, rename).
    ///   - ranges: The affected line ranges.
    ///   - promptUuid: The attributed prompt uuid; nil if not attributed.
    ///   - autoAttribute: True to auto-attribute to the active prompt; nil defaults to false.
    ///   - agentId: The agent id; nil if not an agent write.
    ///   - agentName: The agent name; nil if not an agent write.
    ///   - origin: The origin (hook, manual, command); nil for database default.
    ///   - claudeSessionId: The Claude Code conversation uuid.
    ///   - claudeTurnId: The Claude Code turn id.
    ///   - toolUseId: The tool use id for deduplication.
    ///   - toolName: The tool name (Edit, Write, etc.).
    ///   - agentType: The agent type (aggressive, conservative, etc.).
    ///   - permissionMode: The permission mode (default, bypassPermissions, etc.).
    ///   - durationMs: The duration in milliseconds.
    ///   - transcriptPath: The path to the transcript file.
    init(
        project: ProjectContext,
        instance: InstanceContext,
        session: SessionContext,
        relativePath: String,
        changeKind: ChangeKind,
        ranges: [ChangeRange],
        promptUuid: String? = nil,
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

struct FileChangeAddResponse: Codable, Hashable, Sendable {
    let sessionFileUuid: String
    let fileChangeUuid: String
    let rangeUuids: [String]
    /// Set when this (tool_use_id, file) pair was ALREADY recorded: the uuids
    /// above are the existing row's, no event was appended and the session
    /// was not touched.
    ///
    /// An explicit already-recorded SUCCESS, so a replayed payload is never an
    /// error to the hook and never a second edit to a subscriber. Absent means
    /// a row was written.
    let deduplicated: Bool?

    /// Creates a FILE_CHANGE_ADD response with uuids for the recorded change.
    /// - Parameters:
    ///   - sessionFileUuid: The session file row uuid.
    ///   - fileChangeUuid: The file change row uuid.
    ///   - rangeUuids: The uuids of the affected ranges.
    ///   - deduplicated: True if the (tool_use_id, file) pair was already recorded.
    init(
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

struct FileChangeListRequest: Codable, Hashable, Sendable {
    let sessionUuid: String?
    let promptUuid: String?
    let relativePath: String?
    let limit: Int?

    /// Creates a FILE_CHANGE_LIST request with optional filters.
    /// - Parameters:
    ///   - sessionUuid: The session to filter by; nil lists all.
    ///   - promptUuid: The prompt to filter by; nil lists all.
    ///   - relativePath: The file path to filter by; nil lists all.
    ///   - limit: The maximum number of changes to return; nil for no limit.
    init(sessionUuid: String? = nil, promptUuid: String? = nil, relativePath: String? = nil, limit: Int? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.relativePath = relativePath
        self.limit = limit
    }
}

struct FileChangeListResponse: Codable, Hashable, Sendable {
    let changes: [FileChangeRow]

    /// Creates a FILE_CHANGE_LIST response.
    /// - Parameter changes: The list of file change rows.
    init(changes: [FileChangeRow]) {
        self.changes = changes
    }
}

// MARK: - KBITE_LIST / KBITE_ADD / KBITE_REMOVE

/// Registered kbites at a scope, resolved through the inheritance chain at
/// READ time (owner's own junction plus every ancestor's) — correct even for
/// kbites added after the child row was created. `all: true` ignores scope
/// and returns every kbite row in the db (the cleanup drift-check listing).
struct KbiteListRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let all: Bool?

    /// Creates a KBITE_LIST request.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - all: True to list all kbites in the db; nil defaults to false.
    init(scope: KbiteScope, ownerUuid: String, all: Bool? = nil) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.all = all
    }
}

struct KbiteListResponse: Codable, Hashable, Sendable {
    let kbites: [KbiteRef]

    /// Creates a KBITE_LIST response.
    /// - Parameter kbites: The list of kbite references.
    init(kbites: [KbiteRef]) {
        self.kbites = kbites
    }
}

/// Explicit-only registration (v11 inheritance model — never auto-added).
///
/// Db-only — the db is the sole kbite registry.
/// Idempotent; `added` is false when the junction already existed.
struct KbiteAddRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let code: String

    /// Creates a KBITE_ADD request to register a kbite at a scope.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - code: The kbite code.
    init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

struct KbiteAddResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let added: Bool

    /// Creates a KBITE_ADD response.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - code: The kbite code.
    ///   - added: True if the junction was newly created; false if it already existed.
    init(kbiteUuid: String, code: String, added: Bool) {
        self.kbiteUuid = kbiteUuid
        self.code = code
        self.added = added
    }
}

struct KbiteRemoveRequest: Codable, Hashable, Sendable {
    let scope: KbiteScope
    let ownerUuid: String
    let code: String

    /// Creates a KBITE_REMOVE request to unregister a kbite.
    /// - Parameters:
    ///   - scope: The scope level (project, instance, session, prompt).
    ///   - ownerUuid: The owner uuid.
    ///   - code: The kbite code.
    init(scope: KbiteScope, ownerUuid: String, code: String) {
        self.scope = scope
        self.ownerUuid = ownerUuid
        self.code = code
    }
}

struct KbiteRemoveResponse: Codable, Hashable, Sendable {
    let removed: Bool

    /// Creates a KBITE_REMOVE response.
    /// - Parameter removed: True if the junction was removed; false if it didn't exist.
    init(removed: Bool) {
        self.removed = removed
    }
}

// MARK: - KBITE_MAW_OPEN

/// Filesystem skeleton only — no db rows (maws are not tracked in the db).
///
/// The client resolves $GMCC_KBITE_OPEN and passes the absolute maw path; the
/// daemon never reads gmfs environment variables.
struct KbiteMawOpenRequest: Codable, Hashable, Sendable {
    let kbiteName: String
    let mawPath: String

    /// Creates a KBITE_MAW_OPEN request to initialize a maw filesystem.
    /// - Parameters:
    ///   - kbiteName: The kbite name.
    ///   - mawPath: The absolute path to the maw directory.
    init(kbiteName: String, mawPath: String) {
        self.kbiteName = kbiteName
        self.mawPath = mawPath
    }
}

struct KbiteMawOpenResponse: Codable, Hashable, Sendable {
    let mawPath: String
    let createdDirs: [String]
    let createdIndex: Bool

    /// Creates a KBITE_MAW_OPEN response.
    /// - Parameters:
    ///   - mawPath: The absolute path to the maw directory.
    ///   - createdDirs: The directories that were created.
    ///   - createdIndex: True if the index file was created.
    init(mawPath: String, createdDirs: [String], createdIndex: Bool) {
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
struct KbiteDigestRequest: Codable, Hashable, Sendable {
    let code: String
    let kbiteOpenPath: String

    /// Creates a KBITE_DIGEST request to import and digest a kbite.
    /// - Parameters:
    ///   - code: The kbite code.
    ///   - kbiteOpenPath: The absolute path to the open maw.
    init(code: String, kbiteOpenPath: String) {
        self.code = code
        self.kbiteOpenPath = kbiteOpenPath
    }
}

struct KbiteDigestResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let resourceCount: Int
    let fileCount: Int
    let keywordCount: Int
    let deletedChewedFiles: [String]
    /// Where the maw's raw sources went (`{digested}/{code}/`); nil when
    /// nothing was digested or the archive move failed.
    let archivedTo: String?
    /// The archive failure, when there was one.
    ///
    /// The db commit stands regardless — the maw is simply still on disk.
    let archiveError: String?

    /// Creates a KBITE_DIGEST response with import summary and status.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - resourceCount: The number of resources created.
    ///   - fileCount: The number of resource files created.
    ///   - keywordCount: The number of keywords created.
    ///   - deletedChewedFiles: The chewed files that were deleted.
    ///   - archivedTo: The path where raw sources were archived; nil if none or failed.
    ///   - archiveError: The archive failure message if one occurred.
    init(
        kbiteUuid: String,
        resourceCount: Int,
        fileCount: Int,
        keywordCount: Int,
        deletedChewedFiles: [String],
        archivedTo: String? = nil,
        archiveError: String? = nil
    ) {
        self.kbiteUuid = kbiteUuid
        self.resourceCount = resourceCount
        self.fileCount = fileCount
        self.keywordCount = keywordCount
        self.deletedChewedFiles = deletedChewedFiles
        self.archivedTo = archivedTo
        self.archiveError = archiveError
    }
}

// MARK: - KBITE_GET / KBITE_FILE_GET

struct KbiteGetRequest: Codable, Hashable, Sendable {
    let code: String

    /// Creates a KBITE_GET request.
    /// - Parameter code: The kbite code.
    init(code: String) {
        self.code = code
    }
}

/// One kbite with its resources, file STUBS (names + summaries, never
/// content), and kbite-level keywords.
///
/// Content loads go through KBITE_FILE_GET one file at a time.
struct KbiteGetResponse: Codable, Hashable, Sendable {
    let kbite: KbiteRow
    let resources: [KbiteResourceRow]
    let keywords: [String]

    /// Creates a KBITE_GET response with the kbite and its resources.
    /// - Parameters:
    ///   - kbite: The kbite row.
    ///   - resources: The resource rows with file stubs.
    ///   - keywords: The kbite-level keywords.
    init(kbite: KbiteRow, resources: [KbiteResourceRow], keywords: [String]) {
        self.kbite = kbite
        self.resources = resources
        self.keywords = keywords
    }
}

struct KbiteFileGetRequest: Codable, Hashable, Sendable {
    let fileUuid: String

    /// Creates a KBITE_FILE_GET request.
    /// - Parameter fileUuid: The resource file uuid.
    init(fileUuid: String) {
        self.fileUuid = fileUuid
    }
}

struct KbiteFileGetResponse: Codable, Hashable, Sendable {
    let file: KbiteResourceFileRow

    /// Creates a KBITE_FILE_GET response.
    /// - Parameter file: The resource file row with content.
    init(file: KbiteResourceFileRow) {
        self.file = file
    }
}

// MARK: - KBITE_SEARCH

/// FTS5 full-text query across kbite resource files; ranked stubs, never
/// content.
///
/// Empty/nil kbite_uuids searches everything.
struct KbiteSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let kbiteUuids: [String]?
    let limit: Int?

    /// Creates a KBITE_SEARCH request for full-text search.
    /// - Parameters:
    ///   - query: The FTS5 search query.
    ///   - kbiteUuids: The kbites to search; nil or empty searches everything.
    ///   - limit: The maximum number of results; nil for default.
    init(query: String, kbiteUuids: [String]? = nil, limit: Int? = nil) {
        self.query = query
        self.kbiteUuids = kbiteUuids
        self.limit = limit
    }
}

struct KbiteSearchResponse: Codable, Hashable, Sendable {
    let hits: [KbiteSearchHit]

    /// Creates a KBITE_SEARCH response.
    /// - Parameter hits: The ranked search result stubs.
    init(hits: [KbiteSearchHit]) {
        self.hits = hits
    }
}

// MARK: - SEARCH

/// The searchable row kinds.
///
/// Raw values match the source table names. (v9 added the five
/// exploration/review kinds — discharging m0003's explore.md/review.md
/// deferral note).
enum SearchKind: String, Codable, Hashable, CaseIterable, Sendable {
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
///
/// A query with no searchable tokens is BAD_REQUEST.
struct SearchRequest: Codable, Hashable, Sendable {
    let query: String
    let sessionUuid: String?
    /// nil/empty = every kind.
    let kinds: [SearchKind]?
    /// Clamped 1…500, default 50.
    let limit: Int?

    /// Creates a SEARCH request for full-text search across prompts and reports.
    /// - Parameters:
    ///   - query: The FTS5 search query.
    ///   - sessionUuid: The session to search; nil searches the whole db.
    ///   - kinds: The kinds of rows to include; nil or empty includes every kind.
    ///   - limit: The maximum number of results, clamped 1…500; nil defaults to 50.
    init(query: String, sessionUuid: String? = nil, kinds: [SearchKind]? = nil, limit: Int? = nil) {
        self.query = query
        self.sessionUuid = sessionUuid
        self.kinds = kinds
        self.limit = limit
    }
}

struct SearchResponse: Codable, Hashable, Sendable {
    let hits: [SearchHit]

    /// Creates a SEARCH response.
    /// - Parameter hits: The ranked search result stubs with prompt lineage.
    init(hits: [SearchHit]) {
        self.hits = hits
    }
}

// MARK: - CATALOG_SEARCH

/// Tokenized OR name/code search across instances + sessions, optionally
/// scoped to one project.
///
/// Returns matched sessions plus every parent instance needed to group them;
/// the client orders by created/updated.
struct CatalogSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let projectUuid: String?
    let limit: Int?
    /// ADDITIVE OPTIONAL: byte mode (see `CdePager`); sessions are the paged
    /// region and instances are recomputed as the parents of the page.
    let pageBytes: Int?
    let pageCursor: String?

    /// Creates a CATALOG_SEARCH request for name/code search across instances.
    /// - Parameters:
    ///   - query: The search query, tokenized with OR logic.
    ///   - projectUuid: The project to scope by; nil searches all projects.
    ///   - limit: The maximum results to return; nil for no limit.
    ///   - pageBytes: The byte-mode page budget; nil for no pagination.
    ///   - pageCursor: The pagination cursor from a prior result; nil to start.
    init(
        query: String,
        projectUuid: String? = nil,
        limit: Int? = nil,
        pageBytes: Int? = nil,
        pageCursor: String? = nil
    ) {
        self.query = query
        self.projectUuid = projectUuid
        self.limit = limit
        self.pageBytes = pageBytes
        self.pageCursor = pageCursor
    }
}

struct CatalogSearchResponse: Codable, Hashable, Sendable {
    let instances: [InstanceRow]
    let sessions: [SessionStub]
    /// ADDITIVE OPTIONAL, byte mode only.
    let page: CdePage?

    /// Creates a CATALOG_SEARCH response with matched instances and sessions.
    /// - Parameters:
    ///   - instances: The instances containing matched sessions.
    ///   - sessions: The matched session stubs.
    ///   - page: The pagination metadata; nil when not in byte-mode paging.
    init(instances: [InstanceRow], sessions: [SessionStub], page: CdePage? = nil) {
        self.instances = instances
        self.sessions = sessions
        self.page = page
    }
}

// MARK: - KBITE_KEYWORD_TAG

/// Attach or detach normalized keywords at kbite level or resource-file
/// level.
///
/// Keywords are upserted into the shared vocabulary on attach.
struct KbiteKeywordTagRequest: Codable, Hashable, Sendable {
    let level: KeywordTagLevel
    let targetUuid: String
    let keywords: [String]
    let detach: Bool

    /// Creates a KBITE_KEYWORD_TAG request to attach or detach keywords.
    /// - Parameters:
    ///   - level: The scope level (kbite or resource-file).
    ///   - targetUuid: The target kbite or resource-file uuid.
    ///   - keywords: The normalized keywords to attach or detach.
    ///   - detach: True to detach; false to attach.
    init(level: KeywordTagLevel, targetUuid: String, keywords: [String], detach: Bool = false) {
        self.level = level
        self.targetUuid = targetUuid
        self.keywords = keywords
        self.detach = detach
    }
}

struct KbiteKeywordTagResponse: Codable, Hashable, Sendable {
    let attached: Int
    let detached: Int

    /// Creates a KBITE_KEYWORD_TAG response with counts of changes.
    /// - Parameters:
    ///   - attached: The number of keywords newly attached.
    ///   - detached: The number of keywords detached.
    init(attached: Int, detached: Int) {
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
struct KbiteExportRequest: Codable, Hashable, Sendable {
    let code: String
    let dbExportPath: String
    let anonymize: [KbitePrefixRule]

    /// Creates a KBITE_EXPORT request to export a kbite to a JSON file.
    /// - Parameters:
    ///   - code: The kbite code.
    ///   - dbExportPath: The absolute path where the daemon writes db_export.json.
    ///   - anonymize: Prefix-to-placeholder rules for path anonymization.
    init(code: String, dbExportPath: String, anonymize: [KbitePrefixRule]) {
        self.code = code
        self.dbExportPath = dbExportPath
        self.anonymize = anonymize
    }
}

struct KbiteExportResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let resourceCount: Int
    let fileCount: Int
    let kbiteKeywordCount: Int
    let fileKeywordCount: Int
    let dbExportPath: String

    /// Creates a KBITE_EXPORT response with export summary and counts.
    /// - Parameters:
    ///   - kbiteUuid: The kbite uuid.
    ///   - code: The kbite code.
    ///   - resourceCount: The number of resources exported.
    ///   - fileCount: The number of resource files exported.
    ///   - kbiteKeywordCount: The number of kbite-level keywords.
    ///   - fileKeywordCount: The number of file-level keywords.
    ///   - dbExportPath: The path to the written db_export.json file.
    init(
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
enum KbiteImportCollision: String, Codable, Hashable, CaseIterable, Sendable {
    case skip
    case overwrite
}

/// Daemon reads db_export.json at `dbExportPath`, rehydrates placeholder
/// paths via `rehydrate`, and writes rows in one transaction.
///
/// Never creates registration rows — `gm kbite add` stays the only
/// registration door.
struct KbiteImportRequest: Codable, Hashable, Sendable {
    let dbExportPath: String
    let onCollision: KbiteImportCollision
    let rehydrate: [KbitePrefixRule]

    /// Creates a KBITE_IMPORT request to import a kbite from a JSON file.
    /// - Parameters:
    ///   - dbExportPath: The path to the db_export.json file to import.
    ///   - onCollision: The collision policy (skip or overwrite).
    ///   - rehydrate: Placeholder-to-prefix rules for path restoration.
    init(dbExportPath: String, onCollision: KbiteImportCollision, rehydrate: [KbitePrefixRule]) {
        self.dbExportPath = dbExportPath
        self.onCollision = onCollision
        self.rehydrate = rehydrate
    }
}

struct KbiteImportResponse: Codable, Hashable, Sendable {
    /// Never nil — the skip branch reports the existing kbite's uuid, the
    /// import branch the ensured one.
    ///
    /// Kept non-optional from birth: loosening a v22 field later is free,
    /// tightening never is.
    let kbiteUuid: String
    let code: String
    let imported: Bool
    let skippedExisting: Bool
    let resourceCount: Int
    let fileCount: Int
    let keywordCount: Int

    /// Creates a KBITE_IMPORT response with the kbite and import status.
    /// - Parameters:
    ///   - kbiteUuid: The imported or existing kbite uuid.
    ///   - code: The kbite code.
    ///   - imported: True if the kbite was newly imported; false if it existed.
    ///   - skippedExisting: True if an existing kbite was skipped due to collision.
    ///   - resourceCount: The number of resources in the kbite.
    ///   - fileCount: The number of resource files in the kbite.
    ///   - keywordCount: The number of keywords in the kbite.
    init(
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
/// behavior here, unlike overwrite).
///
/// Orphaned shared-vocabulary keywords are garbage-collected in the same transaction. daemon_event history survives.
struct KbiteDeleteRequest: Codable, Hashable, Sendable {
    let code: String

    /// Creates a KBITE_DELETE request.
    /// - Parameter code: The kbite code.
    init(code: String) {
        self.code = code
    }
}

struct KbiteDeleteResponse: Codable, Hashable, Sendable {
    let kbiteUuid: String
    let code: String
    let deletedResources: Int
    let deletedFiles: Int
    let deletedRegistrations: Int
    let gcKeywordCount: Int

    /// Creates a KBITE_DELETE response with deletion counts.
    /// - Parameters:
    ///   - kbiteUuid: The deleted kbite uuid.
    ///   - code: The kbite code.
    ///   - deletedResources: The number of deleted resources.
    ///   - deletedFiles: The number of deleted resource files.
    ///   - deletedRegistrations: The number of deleted scope registrations.
    ///   - gcKeywordCount: The number of garbage-collected shared keywords.
    init(
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

struct EventListRequest: Codable, Hashable, Sendable {
    /// Raw kind string (forward compat — filters on the TEXT column).
    let kind: String?
    let subjectUuid: String?
    let sinceId: Int64?
    /// ISO-8601 seconds-precision Z bounds; lexicographic comparison.
    let sinceTime: String?
    let untilTime: String?
    let limit: Int?

    /// Creates an EVENT_LIST request with optional filters.
    /// - Parameters:
    ///   - kind: The event kind filter; nil lists all kinds.
    ///   - subjectUuid: The subject uuid filter; nil lists all subjects.
    ///   - sinceId: The event id to start after; nil starts from the beginning.
    ///   - sinceTime: The ISO-8601 start time (inclusive); nil for no bound.
    ///   - untilTime: The ISO-8601 end time (exclusive); nil for no bound.
    ///   - limit: The maximum events to return; nil for no limit.
    init(
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

struct EventListResponse: Codable, Hashable, Sendable {
    let events: [EventNotification]

    /// Creates an EVENT_LIST response.
    /// - Parameter events: The event notifications matching the request.
    init(events: [EventNotification]) {
        self.events = events
    }
}

// MARK: - CLARIFY_* (v7)

struct ClarifyOpenRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates a CLARIFY_OPEN request to open a clarification summary.
    /// - Parameter promptUuid: The prompt uuid.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Shared response for clarify verbs that return the summary row. `created`
/// is true only when OPEN made the row (open is idempotent create-or-return
/// and never transitions the prompt).
struct ClarifySummaryResponse: Codable, Hashable, Sendable {
    let summary: ClarificationSummaryRow
    let created: Bool

    /// Creates a clarification summary response.
    /// - Parameters:
    ///   - summary: The clarification summary row.
    ///   - created: True if OPEN created the row; false if it already existed.
    init(summary: ClarificationSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Insert a user-facing question while the summary is `building` (m0025).
/// `options` become option child rows in order; the user answers by
/// selection (junction rows) and/or typed text.
struct ClarifyQuestionAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let question: String
    let options: [String]?
    let agentName: String?
    let agentId: String?

    /// Creates a CLARIFY_QUESTION_ADD request to add a user-facing question.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - question: The question text.
    ///   - options: The pre-authored answer options; nil for free-text only.
    ///   - agentName: The agent name that posed the question; nil if manual.
    ///   - agentId: The agent id that posed the question; nil if manual.
    init(
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

struct ClarifyQuestionRowResponse: Codable, Hashable, Sendable {
    let question: ClarificationQuestionRow

    /// Creates a CLARIFY_QUESTION_ADD response.
    /// - Parameter question: The newly created question row.
    init(question: ClarificationQuestionRow) {
        self.question = question
    }
}

/// Insert an internal clarification note (m0025): the agent's own record of
/// what confused exploration or itself. weight uses the finding_rating
/// polarity (0 = critical). questionUuid attaches the note to an answered
/// user question after the fact.
struct ClarifyNoteAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let body: String
    let confusedEntityUuid: String?
    let confusedEntityType: String?
    let weight: Int?
    let questionUuid: String?
    let agentName: String?
    let agentId: String?

    /// Creates a CLARIFY_NOTE_ADD request to add an internal note.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - body: The note body text.
    ///   - confusedEntityUuid: The confused entity uuid; nil if none.
    ///   - confusedEntityType: The confused entity type; nil if none.
    ///   - weight: The note weight (0=critical); nil for unranked.
    ///   - questionUuid: The related question uuid; nil if not attached.
    ///   - agentName: The agent name that wrote the note; nil if manual.
    ///   - agentId: The agent id that wrote the note; nil if manual.
    init(
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

struct ClarifyNoteRowResponse: Codable, Hashable, Sendable {
    let note: ClarificationNoteRow

    /// Creates a CLARIFY_NOTE_ADD response.
    /// - Parameter note: The newly created note row.
    init(note: ClarificationNoteRow) {
        self.note = note
    }
}

/// building → answering: locks the question list.
struct ClarifySealRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates a CLARIFY_SEAL request to transition from building to answering.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Answer one question (summary must be `answering`).
///
/// Revives a skipped row. Pure row update — never touches the summary's version. expectedVersion targets the QUESTION
/// row. skip=true marks the row skipped instead of answered. selectedOptionUuids replace the question's junction rows
/// wholesale; answerText carries a typed answer — either or both satisfy "answered".
struct ClarifyAnswerRequest: Codable, Hashable, Sendable {
    let questionUuid: String
    let expectedVersion: Int64
    let answerText: String?
    let selectedOptionUuids: [String]?
    let skip: Bool

    /// Creates a CLARIFY_ANSWER request to answer one question.
    /// - Parameters:
    ///   - questionUuid: The question row uuid.
    ///   - expectedVersion: The expected question version.
    ///   - answerText: Free-text answer; nil if not provided.
    ///   - selectedOptionUuids: Selected option uuids; nil if not provided.
    ///   - skip: True to mark the question skipped; false to answer it.
    init(
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
struct ClarifyReopenRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates a CLARIFY_REOPEN request to transition from complete to answering.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// answering → complete.
///
/// A PURE GATE since m0025: requires every question answered or skipped, validates the care package where one exists
/// (ready, non-empty intent), and writes NOTHING to the prompt row — the old refined_goal→prompt.goal copy is retired;
/// ZERO bot write doors to prompt content remain (backstory/goal/detail are human input only).
struct ClarifyFinalizeRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates a CLARIFY_FINALIZE request to transition from answering to complete.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

struct ClarifyFinalizeResponse: Codable, Hashable, Sendable {
    let summary: ClarificationSummaryRow

    /// Creates a CLARIFY_FINALIZE response.
    /// - Parameter summary: The finalized clarification summary row.
    init(summary: ClarificationSummaryRow) {
        self.summary = summary
    }
}

/// Same additive-optional narrowing contract as ArchGetRequest: nil means
/// "what CLARIFY_GET has always returned", so an unnarrowed request is
/// byte-identical and no wire bump is owed.
///
/// Two things here grow without bound — the embedded care package (its clarified intent plus N curated exploration
/// COPIES) and the note bodies — and each has its own switch. Questions are NOT windowed: a question plus its
/// pre-authored options is bounded by what a human can answer, and the count is small by design.
struct ClarifyGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    /// nil/true = the package rides along (the historical response). false
    /// replaces it with `carePackageStub`, because the whole package is
    /// separately readable through CARE_PACKAGE_GET and duplicating it here
    /// is the single largest avoidable weight in this response.
    let includeCarePackage: Bool?
    /// Weight window over the notes, mirroring the rating windows: a note at
    /// or below this weight stays a full row, the rest drop to `noteStubs`.
    ///
    /// Notes with NO weight are ALWAYS full — the same "unranked is the work queue" rule EXPLORE_GET applies to
    /// unranked findings. nil = every note full.
    let noteWeightMax: Int?

    /// Creates a CLARIFY_GET request with optional narrowing.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - includeCarePackage: True to include package; false for stub; nil for full (default).
    ///   - noteWeightMax: The maximum weight to return as full rows; nil for all.
    init(promptUuid: String, includeCarePackage: Bool? = nil, noteWeightMax: Int? = nil) {
        self.promptUuid = promptUuid
        self.includeCarePackage = includeCarePackage
        self.noteWeightMax = noteWeightMax
    }

    var isNarrowed: Bool { includeCarePackage != nil || noteWeightMax != nil }
}

/// A note carrying a leading excerpt of its body plus the body's true length.
///
/// A note has no title, so a body-less stub would be unreadable: the excerpt is what makes "is this one worth widening
/// for" answerable.
struct ClarificationNoteStub: Codable, Hashable, Sendable {
    let uuid: String
    let weight: Int?
    let agentName: String?
    let questionUuid: String?
    let bodyExcerpt: String
    let bodyChars: Int
    let bodyTruncated: Bool

    /// Creates a clarification note stub with a body excerpt.
    /// - Parameters:
    ///   - uuid: The note uuid.
    ///   - weight: The note weight; nil for unranked.
    ///   - agentName: The agent that wrote the note; nil if manual.
    ///   - questionUuid: The related question uuid; nil if not attached.
    ///   - bodyExcerpt: The leading excerpt of the body text.
    ///   - bodyChars: The total character count of the body.
    ///   - bodyTruncated: True if the excerpt was truncated.
    init(
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
struct CarePackageStub: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let status: String
    let clarifiedIntentChars: Int
    let dopeRefCount: Int
    let kbiteRefCount: Int
    let explorationRefCount: Int
    let dopeScopeUuid: String?
    let dopeScopeRevision: Int64?

    /// Creates a care package stub with metadata and counts.
    /// - Parameters:
    ///   - uuid: The package uuid.
    ///   - version: The package version.
    ///   - status: The package status.
    ///   - clarifiedIntentChars: The character count of the clarified intent.
    ///   - dopeRefCount: The number of dope references.
    ///   - kbiteRefCount: The number of kbite references.
    ///   - explorationRefCount: The number of exploration references.
    ///   - dopeScopeUuid: The dope scope uuid; nil if none.
    ///   - dopeScopeRevision: The dope scope revision; nil if none.
    init(
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

    /// Creates a care package stub from a full package row.
    /// - Parameter package: The care package row to derive from.
    init(package: CarePackageRow) {
        self.init(
            uuid: package.uuid,
            version: package.version,
            status: package.status,
            clarifiedIntentChars: package.clarifiedIntent.count,
            dopeRefCount: package.dopeRefs.count,
            kbiteRefCount: package.kbiteRefs.count,
            explorationRefCount: package.explorationRefs.count,
            dopeScopeUuid: package.dopeScopeUuid,
            dopeScopeRevision: package.dopeScopeRevision
        )
    }
}

/// The care package's read-time dope drift report — the same shape
/// BriefingStaleness carries, computed by the same
/// `DopeRepository.scopeStaleness`.
///
/// Computed at read, never stored.
struct CarePackageStaleness: Codable, Hashable, Sendable {
    let stampedRevision: Int64?
    let currentRevision: Int64?
    let drifted: Bool
    let ghostDotPaths: [String]

    /// Creates a care package staleness report.
    /// - Parameters:
    ///   - stampedRevision: The dope revision when the package was created; nil if none.
    ///   - currentRevision: The current dope revision; nil if no scope.
    ///   - drifted: True if the package is stale relative to current dope.
    ///   - ghostDotPaths: The dope entities referenced that are not present.
    init(
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
/// ONE badge.
///
/// An additive protocol on existing Codable types — the JSON is byte-identical, so this is NOT a wire change.
protocol DopeScopeStalenessReporting {
    var stampedRevision: Int64? { get }
    var currentRevision: Int64? { get }
    var drifted: Bool { get }
    var ghostDotPaths: [String] { get }
}

extension BriefingStaleness: DopeScopeStalenessReporting {}
extension CarePackageStaleness: DopeScopeStalenessReporting {}

struct ClarifyGetResponse: Codable, Hashable, Sendable {
    let summary: ClarificationSummaryRow
    let questions: [ClarificationQuestionRow]
    let notes: [ClarificationNoteRow]
    /// nil until package-open (bot-variant flows never create one).
    let carePackage: CarePackageRow?
    /// ADDITIVE OPTIONAL (no wire bump — decodes as nil on a stale peer).
    ///
    /// INVARIANT: non-nil IFF `carePackage` is non-nil.
    let carePackageStaleness: CarePackageStaleness?
    /// ADDITIVE OPTIONAL (no wire bump).
    ///
    /// Non-nil ONLY when `includeCarePackage: false` narrowed a package that DOES exist — so `carePackage == nil &&
    /// carePackageStub == nil` still means, as it always has, that no package was ever opened.
    let carePackageStub: CarePackageStub?
    /// ADDITIVE OPTIONAL.
    ///
    /// Non-nil ONLY when a weight window was applied: the notes outside it, as excerpts.
    let noteStubs: [ClarificationNoteStub]?

    /// Creates a CLARIFY_GET response with the summary, questions, and notes.
    /// - Parameters:
    ///   - summary: The clarification summary row.
    ///   - questions: The question rows.
    ///   - notes: The clarification note rows.
    ///   - carePackage: The care package row; nil if not opened.
    ///   - carePackageStaleness: The staleness report; nil if no package.
    ///   - carePackageStub: The package stub; nil unless narrowed.
    ///   - noteStubs: The excerpted notes; nil unless windowed.
    init(
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

/// Open (or return) the care package on a clarification summary.
///
/// Multi-agent flows only by convention — the schema is variant-agnostic.
struct CarePackageOpenRequest: Codable, Hashable, Sendable {
    let summaryUuid: String

    /// Creates a CARE_PACKAGE_OPEN request.
    /// - Parameter summaryUuid: The clarification summary uuid.
    init(summaryUuid: String) {
        self.summaryUuid = summaryUuid
    }
}

struct CarePackageResponse: Codable, Hashable, Sendable {
    let package: CarePackageRow
    let created: Bool
    /// ADDITIVE OPTIONAL (no wire bump).
    ///
    /// Non-nil ONLY when CARE_PACKAGE_GET narrowed the curated exploration COPIES away: `package.explorationRefs` then
    /// holds just the refs whose bodies were asked for, and this holds the complete roster as excerpts. NARROWING
    /// EMPTIES AN ARRAY AND NAMES WHAT LEFT IT — it never rewrites a row's fields, so no value inside a CarePackageRow
    /// is ever a truncated lie.
    let explorationRefStubs: [CarePackageExplorationRefStub]?

    /// Creates a CARE_PACKAGE_OPEN or CARE_PACKAGE_GET response.
    /// - Parameters:
    ///   - package: The care package row.
    ///   - created: True if OPEN created the package; false if it existed.
    ///   - explorationRefStubs: The exploration ref excerpts; nil unless narrowed.
    init(
        package: CarePackageRow,
        created: Bool = false,
        explorationRefStubs: [CarePackageExplorationRefStub]? = nil
    ) {
        self.package = package
        self.created = created
        self.explorationRefStubs = explorationRefStubs
    }
}

/// A curated exploration COPY carrying a leading excerpt of its body.
struct CarePackageExplorationRefStub: Codable, Hashable, Sendable {
    let uuid: String
    let curatedTitle: String
    let filePath: String?
    let sourceFindingUuid: String?
    let seq: Int
    let curatedBodyExcerpt: String
    let curatedBodyChars: Int
    let curatedBodyTruncated: Bool

    /// Creates a care package exploration reference stub with a body excerpt.
    /// - Parameters:
    ///   - uuid: The reference uuid.
    ///   - curatedTitle: The curated title.
    ///   - filePath: The source file path; nil if none.
    ///   - sourceFindingUuid: The source finding uuid; nil if not traced.
    ///   - seq: The sequence order within the package.
    ///   - curatedBodyExcerpt: The leading excerpt of the curated body.
    ///   - curatedBodyChars: The total character count of the curated body.
    ///   - curatedBodyTruncated: True if the excerpt was truncated.
    init(
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
enum CarePackageRefKind: String, Codable, Hashable, CaseIterable, Sendable {
    case dope
    case kbite
    case exploration
}

/// Add one ref child while the package is `building`.
///
/// Exactly the fields for the kind: dope → dopeCode (+note); kbite → kbiteFileUuid; exploration → curatedTitle +
/// curatedBody (+filePath, +sourceFindingUuid) — a COPY, never a re-exploration.
struct CarePackageRefAddRequest: Codable, Hashable, Sendable {
    let packageUuid: String
    let kind: CarePackageRefKind
    let dopeCode: String?
    let note: String?
    let kbiteFileUuid: String?
    let curatedTitle: String?
    let curatedBody: String?
    let filePath: String?
    let sourceFindingUuid: String?

    /// Creates a CARE_PACKAGE_REF_ADD request to add one reference child.
    /// - Parameters:
    ///   - packageUuid: The care package uuid.
    ///   - kind: The reference kind (dope, kbite, exploration).
    ///   - dopeCode: The dope code; required for dope kind.
    ///   - note: An optional note; for dope kind only.
    ///   - kbiteFileUuid: The kbite file uuid; required for kbite kind.
    ///   - curatedTitle: The curated title; required for exploration kind.
    ///   - curatedBody: The curated body text; required for exploration kind.
    ///   - filePath: The source file path; optional for exploration kind.
    ///   - sourceFindingUuid: The source finding uuid; optional for exploration kind.
    init(
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
/// path — the overview-at-complete idiom).
///
/// The daemon stamps the dope scope revision itself, exactly like briefing complete.
struct CarePackageCompleteRequest: Codable, Hashable, Sendable {
    let packageUuid: String
    let expectedVersion: Int64
    let clarifiedIntent: String

    /// Creates a CARE_PACKAGE_COMPLETE request to transition to ready.
    /// - Parameters:
    ///   - packageUuid: The care package uuid.
    ///   - expectedVersion: The expected package version.
    ///   - clarifiedIntent: The clarified intent text (its sole write path).
    init(packageUuid: String, expectedVersion: Int64, clarifiedIntent: String) {
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
struct CarePackageGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    /// nil/true = curated exploration bodies inline (the historical
    /// response). false moves the roster to `explorationRefStubs`.
    let includeRefBodies: Bool?
    /// Return exactly this exploration ref's curated body in full.
    let refUuid: String?

    /// Creates a CARE_PACKAGE_GET request with optional narrowing.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - includeRefBodies: True for full bodies; false for stubs; nil for full (default).
    ///   - refUuid: A specific ref uuid to return in full; nil for the default.
    init(promptUuid: String, includeRefBodies: Bool? = nil, refUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.includeRefBodies = includeRefBodies
        self.refUuid = refUuid
    }

    var isNarrowed: Bool { includeRefBodies != nil || refUuid != nil }
}

// MARK: - ARCH_* (v7)

struct ArchOpenRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates an ARCH_OPEN request to open an architecture summary.
    /// - Parameter promptUuid: The prompt uuid.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct ArchSummaryResponse: Codable, Hashable, Sendable {
    let summary: ArchitectureSummaryRow
    let created: Bool

    /// Creates an architecture summary response.
    /// - Parameters:
    ///   - summary: The architecture summary row.
    ///   - created: True if OPEN created the summary; false if it existed.
    init(summary: ArchitectureSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Set the concept-level body (approach, components, data flow, tradeoffs —
/// never specific file changes; those are the normalized change rows).
struct ArchSummarizeRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64
    let body: String

    /// Creates an ARCH_SUMMARIZE request to set the concept-level body.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - expectedVersion: The expected summary version.
    ///   - body: The architectural overview text.
    init(summaryUuid: String, expectedVersion: Int64, body: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.body = body
    }
}

struct ArchPersistAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let className: String
    let filePath: String
    let reasonBrief: String
    /// m0025: add|modify|rename|delete (defaults to modify at write).
    let changeKind: String?
    /// m0025: domain.entity dot-path CODE, ghost-legal.
    let dopeRef: String?

    /// Creates an ARCH_PERSIST_ADD request to add a persistence change.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - className: The Swift class or struct name.
    ///   - filePath: The source file path.
    ///   - reasonBrief: A concise explanation of the change.
    ///   - changeKind: The change type (add, modify, rename, delete); nil defaults to modify.
    ///   - dopeRef: A dope entity dot-path; nil if not applicable.
    init(
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

struct ArchPersistAddResponse: Codable, Hashable, Sendable {
    let change: ArchPersistenceChangeRow

    /// Creates an ARCH_PERSIST_ADD response.
    /// - Parameter change: The newly created persistence change row.
    init(change: ArchPersistenceChangeRow) {
        self.change = change
    }
}

struct ArchFieldAddRequest: Codable, Hashable, Sendable {
    let persistenceChangeUuid: String
    let fieldName: String
    let dataType: String
    let changeReason: String
    let changePurpose: String
    let nullable: Bool
    let isForeignKey: Bool
    let fkTarget: String?
    let isIndexed: Bool
    /// m0025: add|modify|rename|delete (defaults to add at write).
    let changeKind: String?
    /// m0025: old field name when changeKind == rename.
    let renamedFrom: String?
    /// m0025: domain.entity.property dot-path CODE, ghost-legal.
    let dopePropertyRef: String?

    /// Creates an ARCH_FIELD_ADD request to add a field change.
    /// - Parameters:
    ///   - persistenceChangeUuid: The persistence change uuid.
    ///   - fieldName: The database column name.
    ///   - dataType: The SQL data type.
    ///   - changeReason: The reason for the change.
    ///   - changePurpose: The purpose of the change.
    ///   - nullable: True if the field allows NULL; false otherwise.
    ///   - isForeignKey: True if the field is a foreign key; false otherwise.
    ///   - fkTarget: The target table and column for a foreign key; nil if not a key.
    ///   - isIndexed: True if the field should be indexed; false otherwise.
    ///   - changeKind: The change type (add, modify, rename, delete); nil defaults to add.
    ///   - renamedFrom: The old field name when changeKind is rename; nil otherwise.
    ///   - dopePropertyRef: A dope property dot-path; nil if not applicable.
    init(
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

struct ArchFieldAddResponse: Codable, Hashable, Sendable {
    let field: ArchPersistenceFieldChangeRow

    /// Creates an ARCH_FIELD_ADD response.
    /// - Parameter field: The newly created field change row.
    init(field: ArchPersistenceFieldChangeRow) {
        self.field = field
    }
}

struct ArchGeneralAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let filePath: String
    let className: String?
    let reasonBrief: String
    let changeDepth: ChangeDepth
    let changeCode: String

    /// Creates an ARCH_GENERAL_ADD request to add a general change.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - filePath: The affected file path.
    ///   - reasonBrief: A concise explanation of the change.
    ///   - changeDepth: The scope (file, class, method).
    ///   - changeCode: The code snippet for the change.
    ///   - className: The Swift class or struct name; nil if file-level.
    init(
        summaryUuid: String,
        filePath: String,
        reasonBrief: String,
        changeDepth: ChangeDepth,
        changeCode: String,
        className: String? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.filePath = filePath
        self.className = className
        self.reasonBrief = reasonBrief
        self.changeDepth = changeDepth
        self.changeCode = changeCode
    }
}

struct ArchGeneralAddResponse: Codable, Hashable, Sendable {
    let change: ArchGeneralChangeRow

    /// Creates an ARCH_GENERAL_ADD response.
    /// - Parameter change: The newly created general change row.
    init(change: ArchGeneralChangeRow) {
        self.change = change
    }
}

/// drafting → proposed (seals change rows for review).
struct ArchProposeRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates an ARCH_PROPOSE request to seal changes for review.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// proposed → approved (terminal; unlocks architecting → implementing).
struct ArchApproveRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates an ARCH_APPROVE request to approve and finalize the architecture.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// proposed → drafting (the revision edge).
struct ArchReviseRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates an ARCH_REVISE request to transition back to drafting.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Structurally-partitioned read — the ARCH analogue of the rating windows on
/// EXPLORE_GET / REVIEW_GET.
///
/// Architecture rows carry no rating, so the window is STRUCTURAL: option bodies, change_code, and a page over the
/// general change rows. Every field here is an additive OPTIONAL whose nil means full bodies and every row, so an older
/// peer gets a byte-identical response. THE NARROWING IS APPLIED BY THE PEN, NOT THE DAEMON. persistenceChanges are
/// NEVER narrowed and NEVER paged, because sorted-key JSON puts "options" ahead of them and a clip mid-array eats the
/// persistence set silently.
struct ArchGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    /// nil/true = option BODIES inline (the historical response). false drops
    /// the bodies to `optionStubs` — the option ROSTER never disappears, so
    /// narrowing can hide content but never existence. nil with an
    /// `optionUuid` set means "only that one body".
    let includeOptions: Bool?
    /// Return exactly this option's body in full.
    ///
    /// In team flows the options are four architect essays and this is how you read one.
    let optionUuid: String?
    /// nil/true = general change_code verbatim (the store caps it at 2 MB
    /// EACH, which is the other half of the weight). false drops every
    /// general row to `generalChangeStubs` — leading excerpt + true length.
    /// nil with a `changeUuid` set means "only that one body".
    let full: Bool?
    /// Return exactly this general change's change_code in full.
    ///
    /// Pins one row, so it ignores limit/cursor.
    let changeUuid: String?
    /// Page size over the GENERAL change rows (nil = every row).
    let limit: Int?
    /// Opaque continuation token — the `changePage.nextCursor` of the
    /// previous page, never constructed by hand.
    let cursor: String?

    /// Creates an ARCH_GET request with optional narrowing.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - includeOptions: True for full option bodies; false for stubs; nil for full (default).
    ///   - optionUuid: A specific option uuid to return in full; nil for the default.
    ///   - full: True for full change_code; false for stubs; nil for full (default).
    ///   - changeUuid: A specific change uuid to return in full; nil for the default.
    ///   - limit: Page size over general changes; nil for all.
    ///   - cursor: Pagination cursor from a prior response; nil to start.
    init(
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

    /// True when the caller asked for ANY narrowing.
    ///
    /// Drives the byte-identical-default guarantee: false ⇒ none of the additive response keys is emitted.
    var isNarrowed: Bool {
        includeOptions != nil || optionUuid != nil || full != nil
            || changeUuid != nil || limit != nil || cursor != nil
    }
}

/// An option carrying its body LENGTH in place of the body, plus everything
/// needed to decide whether to fetch it, including which one won.
///
/// The decision RATIONALE is not duplicated here: it lives on `ArchitectureSummaryRow.decisionRationale`, which every
/// response carries.
struct ArchitectureOptionStub: Codable, Hashable, Sendable {
    let uuid: String
    let agentName: String
    let agentId: String?
    let status: String
    let selected: Bool
    let bodyChars: Int

    /// Creates an architecture option stub with metadata and body size.
    /// - Parameters:
    ///   - uuid: The option uuid.
    ///   - agentName: The architect agent name.
    ///   - agentId: The architect agent id; nil if the option is system-generated.
    ///   - status: The option status.
    ///   - selected: True if this option was selected; false otherwise.
    ///   - bodyChars: The character count of the option body.
    init(
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

/// A general change row carrying a leading excerpt of change_code and its true
/// length.
///
/// Every other field — path, reason, depth, derived implementation state — stays verbatim, because those are what an
/// audit reads.
struct ArchGeneralChangeStub: Codable, Hashable, Sendable {
    let uuid: String
    let seq: Int64
    let filePath: String
    let className: String?
    let reasonBrief: String
    let changeDepth: String
    let changeCodeExcerpt: String
    let changeCodeChars: Int
    let changeCodeTruncated: Bool
    let implementation: ChangeImplementationState

    /// Creates an architecture general change stub with an excerpt.
    /// - Parameters:
    ///   - uuid: The change uuid.
    ///   - seq: The sequence order within the architecture.
    ///   - filePath: The affected file path.
    ///   - className: The affected class name; nil if file-level.
    ///   - reasonBrief: The reason for the change.
    ///   - changeDepth: The scope (file, class, method).
    ///   - changeCodeExcerpt: The leading excerpt of the change code.
    ///   - changeCodeChars: The total character count of the change code.
    ///   - changeCodeTruncated: True if the excerpt was truncated.
    ///   - implementation: The implementation state of the change.
    init(
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
struct ArchChangePage: Codable, Hashable, Sendable {
    let limit: Int?
    let returned: Int
    let totalGeneralChanges: Int
    /// nil = this is the last page.
    let nextCursor: String?

    /// Creates an architecture change page descriptor.
    /// - Parameters:
    ///   - limit: The page size requested; nil for all.
    ///   - returned: The number of changes in this page.
    ///   - totalGeneralChanges: The total number of general changes in the architecture.
    ///   - nextCursor: The cursor for the next page; nil if this is the last.
    init(limit: Int?, returned: Int, totalGeneralChanges: Int, nextCursor: String?) {
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
/// (nil when either side is empty or untouched).
///
/// Join is path-level on daemon-normalized repo-relative paths; file changes without a prompt_uuid are invisible to it
/// — always pass --prompt-uuid when recording.
struct ArchGetResponse: Codable, Hashable, Sendable {
    let summary: ArchitectureSummaryRow
    /// m0025: the persisted methodology options (empty outside team flows).
    let options: [ArchitectureOptionRow]
    let persistenceChanges: [ArchPersistenceChangeRow]
    let generalChanges: [ArchGeneralChangeRow]
    let unplannedChanges: [UnplannedChangeRow]
    let orderingRespected: Bool?
    /// ADDITIVE OPTIONAL (no wire bump — absent on every unnarrowed read and
    /// on any stale peer).
    ///
    /// Non-nil ONLY when the request narrowed options: the complete roster, so a dropped body is never a dropped
    /// option.
    let optionStubs: [ArchitectureOptionStub]?
    /// ADDITIVE OPTIONAL.
    ///
    /// Non-nil ONLY when the request narrowed change_code or paged: the stub form of the general rows in this page.
    let generalChangeStubs: [ArchGeneralChangeStub]?
    /// ADDITIVE OPTIONAL.
    ///
    /// Non-nil ONLY on a narrowed read — where the page sits in the whole set.
    let changePage: ArchChangePage?

    /// Creates an ARCH_GET response with the architecture and changes.
    /// - Parameters:
    ///   - summary: The architecture summary row.
    ///   - persistenceChanges: The persistence change rows.
    ///   - generalChanges: The general change rows.
    ///   - unplannedChanges: The unplanned file change rows.
    ///   - orderingRespected: True if persistence changes were executed before general ones; nil if not applicable.
    ///   - options: The methodology option rows; empty outside team flows.
    ///   - optionStubs: The option stubs; nil unless narrowed.
    ///   - generalChangeStubs: The general change stubs; nil unless narrowed.
    ///   - changePage: The pagination metadata; nil unless paging.
    init(
        summary: ArchitectureSummaryRow,
        persistenceChanges: [ArchPersistenceChangeRow],
        generalChanges: [ArchGeneralChangeRow],
        unplannedChanges: [UnplannedChangeRow],
        orderingRespected: Bool?,
        options: [ArchitectureOptionRow] = [],
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
/// first architect pen verb.
///
/// Options are team-only by convention; zero options = the direct persist/field/general expansion stays legal.
struct ArchOptionAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let agentName: String
    let agentId: String?
    let body: String
    /// REVISION, as the same verb.
    ///
    /// Set BOTH of these to supersede an existing option row: the new row is inserted, the superseded row is stamped
    /// `rejected` (kept — the record is append-only history), and a selection on the old row carries over to the new
    /// one with a line appended to the summary's decision rationale. The pair travels together: one without the other
    /// is refused. Additive OPTIONALS, so nil-nil is the original wire shape byte-for-byte and this does NOT bump
    /// GmWireProtocol.version.
    let supersedesOptionUuid: String?
    /// The superseded row's version — threaded like every mutation.
    let expectedVersion: Int64?

    /// Creates an ARCH_OPTION_ADD request to add a methodology option.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - agentName: The architect agent name.
    ///   - body: The option methodology text.
    ///   - agentId: The architect agent id; nil if system-generated.
    ///   - supersedesOptionUuid: A prior option to replace; nil for new option.
    ///   - expectedVersion: The superseded option version; nil if not replacing.
    init(
        summaryUuid: String,
        agentName: String,
        body: String,
        agentId: String? = nil,
        supersedesOptionUuid: String? = nil,
        expectedVersion: Int64? = nil
    ) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.agentId = agentId
        self.body = body
        self.supersedesOptionUuid = supersedesOptionUuid
        self.expectedVersion = expectedVersion
    }
}

struct ArchOptionRowResponse: Codable, Hashable, Sendable {
    let option: ArchitectureOptionRow

    /// Creates an ARCH_OPTION_ADD response.
    /// - Parameter option: The newly created option row.
    init(option: ArchitectureOptionRow) {
        self.option = option
    }
}

/// Atomically select one option (rejecting its siblings) and record the
/// decision rationale on the summary.
///
/// Only after a decision may the selected option expand into persistence/field/general change rows — enforced as a
/// store guard, not a CHECK (the m0016 cross-table rule).
struct ArchDecideRequest: Codable, Hashable, Sendable {
    let optionUuid: String
    let expectedVersion: Int64
    let rationale: String

    /// Creates an ARCH_DECIDE request to select and finalize an option.
    /// - Parameters:
    ///   - optionUuid: The selected option uuid.
    ///   - expectedVersion: The expected option version.
    ///   - rationale: The decision rationale text.
    init(optionUuid: String, expectedVersion: Int64, rationale: String) {
        self.optionUuid = optionUuid
        self.expectedVersion = expectedVersion
        self.rationale = rationale
    }
}

struct ArchDecideResponse: Codable, Hashable, Sendable {
    let summary: ArchitectureSummaryRow
    let options: [ArchitectureOptionRow]

    /// Creates an ARCH_DECIDE response with the updated summary and options.
    /// - Parameters:
    ///   - summary: The architecture summary row.
    ///   - options: The option rows.
    init(summary: ArchitectureSummaryRow, options: [ArchitectureOptionRow]) {
        self.summary = summary
        self.options = options
    }
}

// MARK: - BOT_* (v24: the daemon-held workflow state machine)

/// Workflow variants. `task` is deliberately ABSENT from the machine — its
/// write-nothing contract means no workflow row; the registry lists it only
/// so errors can name it.
enum BotVariant: String, Codable, Hashable, CaseIterable, Sendable {
    case bot
    case rpi
    case team
}

/// Enter the machine from `draft`: creates the workflow row and claims it
/// for the calling instance.
///
/// Deliberately NO status change — briefing and exploration run while the prompt is still draft, exactly as the manual
/// flow always has; gm prompt set-status stays the only door.
struct PromptStartRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let variant: BotVariant
    let clientKey: String?

    /// Creates a PROMPT_START request to enter the workflow machine.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - variant: The workflow variant (bot, rpi, team).
    ///   - clientKey: The client instance key; nil if not from a client.
    init(promptUuid: String, variant: BotVariant, clientKey: String? = nil) {
        self.promptUuid = promptUuid
        self.variant = variant
        self.clientKey = clientKey
    }
}

/// Adopt whatever evidence exists: fetch-or-create the workflow row,
/// re-stamp the client key, change no status.
///
/// Phase is recomputed at every NEXT — resume IS the first-run code path.
struct PromptResumeRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    /// Required when resume must CREATE the row (a pre-machine prompt).
    let variant: BotVariant?
    let clientKey: String?

    /// Creates a PROMPT_RESUME request to resume the workflow machine.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - variant: The workflow variant; required for a new row.
    ///   - clientKey: The client instance key; nil if not from a client.
    init(promptUuid: String, variant: BotVariant? = nil, clientKey: String? = nil) {
        self.promptUuid = promptUuid
        self.variant = variant
        self.clientKey = clientKey
    }
}

struct BotWorkflowResponse: Codable, Hashable, Sendable {
    let workflow: BotWorkflowRow
    let created: Bool

    /// Creates a PROMPT_START or PROMPT_RESUME response.
    /// - Parameters:
    ///   - workflow: The workflow row.
    ///   - created: True if START created the row; false if it already existed.
    init(workflow: BotWorkflowRow, created: Bool = false) {
        self.workflow = workflow
        self.created = created
    }
}

/// Zero-uuid form: promptUuid nil resolves through the activation registry
/// (caller's own claim → session's single claim), exactly like briefing get.
struct BotNextRequest: Codable, Hashable, Sendable {
    let promptUuid: String?
    let clientKey: String?
    let sessionUuid: String?

    /// Creates a BOT_NEXT request to get the next phase instructions.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid; nil to resolve from activation registry.
    ///   - clientKey: The client instance key; nil if not from a client.
    ///   - sessionUuid: The session uuid; nil to use the prompt's session.
    init(promptUuid: String? = nil, clientKey: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.clientKey = clientKey
        self.sessionUuid = sessionUuid
    }
}

/// The uuid bundle NEXT serves alongside the instruction text — everything
/// the phase needs, computed from db state at read (nothing stored).
struct BotPhaseUuids: Codable, Hashable, Sendable {
    let promptUuid: String
    let sessionUuid: String
    let briefingUuid: String?
    let clarificationSummaryUuid: String?
    let carePackageUuid: String?
    let architectureSummaryUuid: String?
    let reviewSummaryUuid: String?
    /// (agent_type → summary uuid) for the prompt's exploration rows.
    let explorationSummaryUuids: [String: String]

    /// Creates a BOT_NEXT uuid bundle with phase-specific row uuids.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - sessionUuid: The session uuid.
    ///   - briefingUuid: The briefing summary uuid; nil if not opened.
    ///   - clarificationSummaryUuid: The clarification summary uuid; nil if not opened.
    ///   - carePackageUuid: The care package uuid; nil if not opened.
    ///   - architectureSummaryUuid: The architecture summary uuid; nil if not opened.
    ///   - reviewSummaryUuid: The review summary uuid; nil if not opened.
    ///   - explorationSummaryUuids: Agent types mapped to exploration summary uuids.
    init(
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

struct BotNextResponse: Codable, Hashable, Sendable {
    let workflow: BotWorkflowRow
    /// The furthest phase whose entry gate is satisfied.
    let phase: String
    /// Compiled-in instruction text for (variant, phase) — the Cheatsheet
    /// precedent; drift-guarded by WorkflowSpecTests.
    let instructions: String
    /// What still blocks the NEXT phase (empty when the phase's own work is
    /// simply not done yet).
    let gateBlockers: [String]
    let uuids: BotPhaseUuids

    /// Creates a BOT_NEXT response with the current workflow state and gate information.
    /// - Parameters:
    ///   - workflow: The bot workflow row.
    ///   - phase: The furthest phase whose entry gate is satisfied.
    ///   - instructions: Compiled-in instruction text for the phase.
    ///   - gateBlockers: Array of strings describing what blocks the next phase; empty if complete.
    ///   - uuids: The phase uuid bundle.
    init(
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
struct BotGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String?
    let clientKey: String?
    let sessionUuid: String?

    /// Creates a BOT_GET request to fetch the raw workflow row.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid; nil to resolve zero-uuid.
    ///   - clientKey: The client key; nil if not applicable.
    ///   - sessionUuid: The session uuid; nil if not applicable.
    init(promptUuid: String? = nil, clientKey: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.clientKey = clientKey
        self.sessionUuid = sessionUuid
    }
}

// MARK: - AGENT_REGISTER

/// Who agent X is — TWO WRITERS, ONE ROW, keyed on agent_id alone.
///
/// The SubagentStart hook writes the IDENTITY half, which every spawn shape delivers, and the daemon resolves session
/// and prompt from `claudeSessionId` through the binding. AGENT_REGISTER writes the AUTHORITY half, since no spawn
/// shape carries a role. Fields are MERGED, never overwritten, so neither writer can erase the other's half, and
/// ORDERING IS NOT A CONSTRAINT: the join happens at READ time.
struct AgentRegisterRequest: Codable, Hashable, Sendable {
    /// Opaque and NEVER parsed.
    ///
    /// Its shape varies by spawn kind, and reading structure into it would make the registry wrong for whichever shape
    /// ships next.
    let agentId: String
    let role: String?
    let methodology: String?
    /// The phase the spawner spawned this agent FOR — the spawner's claim,
    /// distinct from the workflow phase the daemon derives and stamps onto a
    /// file_change.
    let workflowPhase: String?
    /// The identity half, off the SubagentStart payload.
    ///
    /// `agentType` is a LABEL and never authoritative: it carries the
    /// subagent_type, the literal `workflow-subagent`, or a teammate's NAME
    /// depending on spawn shape. The role that means something arrives on the
    /// authority half. `claudeTurnId` is the naming trap — the payload calls
    /// it `prompt_id` and it is Claude Code's TURN id, not a prompt uuid.
    let agentType: String?
    let claudeSessionId: String?
    let claudeTurnId: String?

    /// Creates an AGENT_REGISTER request to register or update an agent.
    /// - Parameters:
    ///   - agentId: Opaque agent identifier, never parsed.
    ///   - role: The agent role; nil if not yet determined.
    ///   - methodology: The agent methodology; nil if not applicable.
    ///   - workflowPhase: The workflow phase the spawner invoked this agent for; nil if not applicable.
    ///   - agentType: Agent type label from the spawn payload; nil if not yet set.
    ///   - claudeSessionId: Claude session id from the SubagentStart payload; nil if not available.
    ///   - claudeTurnId: Claude turn id from the SubagentStart payload; nil if not available.
    init(
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

struct AgentRegisterResponse: Codable, Hashable, Sendable {
    let registration: AgentRegistrationRow
    /// True when this call created the row — i.e. the spawner got there
    /// before the SubagentStart hook, and the identity half is still empty.
    let created: Bool

    /// Creates an AGENT_REGISTER response with the agent registration row.
    /// - Parameters:
    ///   - registration: The agent registration row.
    ///   - created: True if this call created the row; false if it was merged.
    init(registration: AgentRegistrationRow, created: Bool) {
        self.registration = registration
        self.created = created
    }
}

// MARK: - EXPLORE_* (v24: literal per-agent summaries)

/// Open (or return) the summary for (prompt, agentType). agentType defaults
/// to 'general'; 'synthesis' is the prompt-level seal/synthesis row the
/// primary completes last.
struct ExploreOpenRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let agentType: String?
    let agentId: String?

    /// Creates an EXPLORE_OPEN request to open or retrieve an exploration summary.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - agentType: The agent type; nil defaults to 'general'.
    ///   - agentId: The agent id; nil if system-generated.
    init(promptUuid: String, agentType: String? = nil, agentId: String? = nil) {
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
    }
}

/// Shared response for explore verbs that return the summary row. `created`
/// is true only when OPEN made the row (open is idempotent create-or-return;
/// it is EXPLICIT-only — never wired into prompt status transitions, since
/// exploration runs while the prompt is still `draft`).
struct ExploreSummaryResponse: Codable, Hashable, Sendable {
    let summary: ExplorationSummaryRow
    let created: Bool

    /// Creates an EXPLORE_SUMMARY response with the exploration summary row.
    /// - Parameters:
    ///   - summary: The exploration summary row.
    ///   - created: True if OPEN created the summary; false if it existed.
    init(summary: ExplorationSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Add one key file (summary must be `exploring`).
///
/// Key files are a shared deduped set: a duplicate path is an idempotent upsert-ignore returning the existing row with
/// created=false, never an error.
struct ExploreKeyFileAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let filePath: String

    /// Creates an EXPLORE_KEY_FILE_ADD request to add a key file to the summary.
    /// - Parameters:
    ///   - summaryUuid: The exploration summary uuid.
    ///   - filePath: The file path to add as a key file.
    init(summaryUuid: String, filePath: String) {
        self.summaryUuid = summaryUuid
        self.filePath = filePath
    }
}

struct ExploreKeyFileAddResponse: Codable, Hashable, Sendable {
    let keyFile: ExplorationKeyFileRow
    let created: Bool

    /// Creates an EXPLORE_KEY_FILE_ADD response with the key file row.
    /// - Parameters:
    ///   - keyFile: The exploration key file row.
    ///   - created: True if this call created the row; false if it already existed.
    init(keyFile: ExplorationKeyFileRow, created: Bool) {
        self.keyFile = keyFile
        self.created = created
    }
}

/// Insert a finding while the summary is `exploring`. `rating` is optional at
/// insert — NULL marks the finding unranked (work-in-progress); COMPLETE
/// refuses while any finding is unranked.
struct ExploreFindingAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let kind: ExplorationFindingKind
    let title: String
    let body: String
    /// m0025: the merged key-file half of the finding/file pair.
    let filePath: String?
    let agentName: String
    let agentId: String?
    let rating: Int?

    /// Creates an EXPLORE_FINDING_ADD request to add a finding to the summary.
    /// - Parameters:
    ///   - summaryUuid: The exploration summary uuid.
    ///   - kind: The finding kind.
    ///   - title: The finding title.
    ///   - body: The finding body text.
    ///   - agentName: The agent that created the finding.
    ///   - filePath: The related file path; nil for cross-cutting findings.
    ///   - agentId: The agent id; nil if system-generated.
    ///   - rating: The finding rating; nil for unranked (work-in-progress).
    init(
        summaryUuid: String,
        kind: ExplorationFindingKind,
        title: String,
        body: String,
        agentName: String,
        filePath: String? = nil,
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

struct ExploreFindingRowResponse: Codable, Hashable, Sendable {
    let finding: ExplorationFindingRow

    /// Creates an EXPLORE_FINDING_ADD response with the newly created finding row.
    /// - Parameter finding: The exploration finding row.
    init(finding: ExplorationFindingRow) {
        self.finding = finding
    }
}

/// Batch-rank findings (summary must be `exploring` — ranking a sealed set
/// would shift the sub-100 contract; reopen first).
///
/// The whole batch validates before any write and applies atomically: one bad pair (out-of-range, duplicate, or a
/// finding not belonging to this summary) rejects everything. Deliberately version-less: the team re-ranker
/// blind-overwrites ratings it never read — that IS the specified semantic — and the single-writer DatabaseQueue
/// serializes competing batches. Re-rank = same verb again.
struct ExploreRankRequest: Codable, Hashable, Sendable {
    /// m0025: the batch is PROMPT-scoped — one atomic calibrated batch across
    /// every summary of the prompt (cross-persona tombstoning preserved,
    /// re-keyed from summary to prompt).
    let promptUuid: String
    let ratings: [FindingRating]

    /// Creates an EXPLORE_RANK request to batch-rank exploration findings.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid; applies the batch across all summaries.
    ///   - ratings: The finding rating assignments to apply.
    init(promptUuid: String, ratings: [FindingRating]) {
        self.promptUuid = promptUuid
        self.ratings = ratings
    }
}

struct ExploreRankResponse: Codable, Hashable, Sendable {
    let promptUuid: String
    let updatedCount: Int
    /// 0 ⇒ the synthesis COMPLETE (seal) will pass its rank gate.
    let unrankedCount: Int

    /// Creates an EXPLORE_RANK response with the ranking result summary.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - updatedCount: The number of findings that were ranked.
    ///   - unrankedCount: The number of findings still unranked.
    init(promptUuid: String, updatedCount: Int, unrankedCount: Int) {
        self.promptUuid = promptUuid
        self.updatedCount = updatedCount
        self.unrankedCount = unrankedCount
    }
}

/// exploring → complete.
///
/// Refuses while any finding is unranked. `overview` is carried ONLY here — there is no earlier write path, so the
/// narrative is structurally written by the primary agent after the ranked findings exist.
struct ExploreCompleteRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64
    let overview: String

    /// Creates an EXPLORE_COMPLETE request to seal exploration and transition to complete.
    /// - Parameters:
    ///   - summaryUuid: The exploration summary uuid.
    ///   - expectedVersion: The expected summary version.
    ///   - overview: The exploration narrative text.
    init(summaryUuid: String, expectedVersion: Int64, overview: String) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
    }
}

/// complete → exploring: the revision edge.
///
/// Preserves everything (findings, ratings, key files, overview) — the next COMPLETE must re-carry the overview, so
/// staleness cannot survive a re-seal.
struct ExploreReopenRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates an EXPLORE_REOPEN request to transition back to exploring.
    /// - Parameters:
    ///   - summaryUuid: The exploration summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Threshold-partitioned read.
///
/// Default window is ratings under 100; findings inside the window (or unranked — NULL-rated rows are ALWAYS full, they
/// are the resume work-queue) come back as full rows, the rest as stubs. full=true returns everything full;
/// ratingMax/ratingMin shift the window.
struct ExploreGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    /// Optional filter to one agent's summary; nil returns all of them.
    let agentType: String?
    let full: Bool
    let ratingMin: Int?
    let ratingMax: Int?

    /// Creates an EXPLORE_GET request to fetch exploration findings with optional filtering.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - agentType: Filter to one agent's summary; nil returns all.
    ///   - full: True to return all findings in full; false for threshold-partitioned stubs.
    ///   - ratingMin: Minimum rating to include in full rows; nil for default window.
    ///   - ratingMax: Maximum rating to include in full rows; nil for default window (100).
    init(
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

struct ExploreGetResponse: Codable, Hashable, Sendable {
    /// m0025: every summary row of the prompt (or the agentType filter's
    /// one), synthesis first, then alphabetical by agent_type.
    let summaries: [ExplorationSummaryRow]
    /// COMPUTED view: findings of kind 'key_file' across those summaries —
    /// kept as a wire array so consumers keep a stable key-file surface.
    let keyFiles: [ExplorationKeyFileRow]
    /// Full rows: rating inside the window OR unranked, ordered unranked
    /// first, then by rating ascending.
    let findings: [ExplorationFindingRow]
    /// Lightweight stubs for everything outside the window.
    let findingStubs: [ExplorationFindingStub]

    /// Creates an EXPLORE_GET response with exploration summaries and findings.
    /// - Parameters:
    ///   - summaries: The exploration summary rows.
    ///   - keyFiles: The key file rows across all summaries.
    ///   - findings: Full finding rows within the window or unranked.
    ///   - findingStubs: Lightweight stubs for findings outside the window.
    init(
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

struct ReviewOpenRequest: Codable, Hashable, Sendable {
    let promptUuid: String

    /// Creates a REVIEW_OPEN request to open or retrieve a review summary.
    /// - Parameter promptUuid: The prompt uuid.
    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Same contract as ExploreSummaryResponse: open is idempotent and EXPLICIT-
/// only — prompt status transitions never create or gate on this summary
/// (skip-to-done stays legal).
struct ReviewSummaryResponse: Codable, Hashable, Sendable {
    let summary: ReviewSummaryRow
    let created: Bool

    /// Creates a REVIEW_SUMMARY response with the review summary row.
    /// - Parameters:
    ///   - summary: The review summary row.
    ///   - created: True if OPEN created the summary; false if it existed.
    init(summary: ReviewSummaryRow, created: Bool = false) {
        self.summary = summary
        self.created = created
    }
}

/// Insert a finding while the summary is `reviewing`. filePath is nil for
/// cross-cutting findings; lineEnd requires lineStart.
struct ReviewFindingAddRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let kind: ReviewFindingKind
    let title: String
    let body: String
    let filePath: String?
    let lineStart: Int?
    let lineEnd: Int?
    let agentName: String
    /// m0025 agent_id sweep (additive optional).
    let agentId: String?
    let rating: Int?

    /// Creates a REVIEW_FINDING_ADD request to add a finding to the review.
    /// - Parameters:
    ///   - summaryUuid: The review summary uuid.
    ///   - kind: The finding kind.
    ///   - title: The finding title.
    ///   - body: The finding body text.
    ///   - agentName: The agent that created the finding.
    ///   - filePath: The affected file path; nil for cross-cutting findings.
    ///   - lineStart: The starting line number; nil if not applicable.
    ///   - lineEnd: The ending line number; required if lineStart is set.
    ///   - agentId: The agent id; nil if system-generated.
    ///   - rating: The finding rating; nil for unranked (work-in-progress).
    init(
        summaryUuid: String,
        kind: ReviewFindingKind,
        title: String,
        body: String,
        agentName: String,
        filePath: String? = nil,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
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

struct ReviewFindingRowResponse: Codable, Hashable, Sendable {
    let finding: ReviewFindingRow

    /// Creates a REVIEW_FINDING_ADD response with the newly created finding row.
    /// - Parameter finding: The review finding row.
    init(finding: ReviewFindingRow) {
        self.finding = finding
    }
}

/// Batch rank — same contract and rationale as ExploreRankRequest.
struct ReviewRankRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let ratings: [FindingRating]

    /// Creates a REVIEW_RANK request to batch-rank review findings.
    /// - Parameters:
    ///   - summaryUuid: The review summary uuid.
    ///   - ratings: The finding rating assignments to apply.
    init(summaryUuid: String, ratings: [FindingRating]) {
        self.summaryUuid = summaryUuid
        self.ratings = ratings
    }
}

struct ReviewRankResponse: Codable, Hashable, Sendable {
    let summary: ReviewSummaryRow
    let updatedCount: Int
    let unrankedCount: Int

    /// Creates a REVIEW_RANK response with the ranking result summary.
    /// - Parameters:
    ///   - summary: The review summary row.
    ///   - updatedCount: The number of findings that were ranked.
    ///   - unrankedCount: The number of findings still unranked.
    init(summary: ReviewSummaryRow, updatedCount: Int, unrankedCount: Int) {
        self.summary = summary
        self.updatedCount = updatedCount
        self.unrankedCount = unrankedCount
    }
}

/// Record one finding's resolution.
///
/// Pure child-row update, expectedVersion targets the FINDING. Deliberately UNGATED on summary status — the fix loop
/// runs after COMPLETE, and a reopen mid-loop must not strand in-flight resolves (the inversion of the clarify
/// child-lock, by design).
struct ReviewResolveRequest: Codable, Hashable, Sendable {
    let findingUuid: String
    let expectedVersion: Int64
    let status: ReviewFindingStatus

    /// Creates a REVIEW_RESOLVE request to record a finding's resolution.
    /// - Parameters:
    ///   - findingUuid: The review finding uuid.
    ///   - expectedVersion: The expected finding version.
    ///   - status: The resolution status of the finding.
    init(findingUuid: String, expectedVersion: Int64, status: ReviewFindingStatus) {
        self.findingUuid = findingUuid
        self.expectedVersion = expectedVersion
        self.status = status
    }
}

/// reviewing → complete.
///
/// Refuses while any finding is unranked; requires a verdict. overview + verdict are carried ONLY here
/// (primary-agent-only by write-path shape).
struct ReviewCompleteRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64
    let overview: String
    let verdict: ReviewVerdict

    /// Creates a REVIEW_COMPLETE request to seal review and transition to complete.
    /// - Parameters:
    ///   - summaryUuid: The review summary uuid.
    ///   - expectedVersion: The expected summary version.
    ///   - overview: The review narrative text.
    ///   - verdict: The review verdict (approve or request changes).
    init(summaryUuid: String, expectedVersion: Int64, overview: String, verdict: ReviewVerdict) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
        self.overview = overview
        self.verdict = verdict
    }
}

/// complete → reviewing: the revision edge (same preservation contract as
/// ExploreReopenRequest; the persisted verdict survives until re-complete).
struct ReviewReopenRequest: Codable, Hashable, Sendable {
    let summaryUuid: String
    let expectedVersion: Int64

    /// Creates a REVIEW_REOPEN request to transition back to reviewing.
    /// - Parameters:
    ///   - summaryUuid: The review summary uuid.
    ///   - expectedVersion: The expected summary version.
    init(summaryUuid: String, expectedVersion: Int64) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

struct ReviewGetRequest: Codable, Hashable, Sendable {
    let promptUuid: String
    let full: Bool
    let ratingMin: Int?
    let ratingMax: Int?

    /// Creates a REVIEW_GET request to fetch review findings with optional filtering.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid.
    ///   - full: True to return all findings in full; false for threshold-partitioned stubs.
    ///   - ratingMin: Minimum rating to include in full rows; nil for default window.
    ///   - ratingMax: Maximum rating to include in full rows; nil for default window.
    init(promptUuid: String, full: Bool = false, ratingMin: Int? = nil, ratingMax: Int? = nil) {
        self.promptUuid = promptUuid
        self.full = full
        self.ratingMin = ratingMin
        self.ratingMax = ratingMax
    }
}

struct ReviewGetResponse: Codable, Hashable, Sendable {
    let summary: ReviewSummaryRow
    let findings: [ReviewFindingRow]
    let findingStubs: [ReviewFindingStub]

    /// Creates a REVIEW_GET response with the review summary and findings.
    /// - Parameters:
    ///   - summary: The review summary row.
    ///   - findings: Full finding rows within the window or unranked.
    ///   - findingStubs: Lightweight stubs for findings outside the window.
    init(
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
struct SessionResolveRequest: Codable, Hashable, Sendable {
    let sessionUuid: String

    /// Creates a SESSION_RESOLVE request to fetch the session's git checkout state.
    /// - Parameter sessionUuid: The session uuid.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

struct SessionResolveResponse: Codable, Hashable, Sendable {
    let session: SessionRow
    let checkedOut: Bool
    let headState: String
    /// The slugged code of whatever IS checked out (nil when detached or
    /// unavailable).
    ///
    /// Slugging is forward-only: branch / → __, never unslugged.
    let currentSessionCode: String?
    /// The RAW branch name (nil whenever head_state !
    ///
    /// = "branch"). The code stays slugged; the two are never interconverted client-side.
    let currentBranch: String?

    /// Creates a SESSION_RESOLVE response with the session and its checkout state.
    /// - Parameters:
    ///   - session: The session row.
    ///   - checkedOut: True if the session is checked out at the repository root.
    ///   - headState: The git head state (branch, detached, or unavailable).
    ///   - currentSessionCode: The slugged code of the checked-out session; nil if detached.
    ///   - currentBranch: The raw branch name; nil if not checked out to a branch.
    init(
        session: SessionRow,
        checkedOut: Bool,
        headState: String,
        currentSessionCode: String?,
        currentBranch: String?
    ) {
        self.session = session
        self.checkedOut = checkedOut
        self.headState = headState
        self.currentSessionCode = currentSessionCode
        self.currentBranch = currentBranch
    }
}

struct InstanceCurrentSessionRequest: Codable, Hashable, Sendable {
    let instanceUuid: String

    /// Creates an INSTANCE_CURRENT_SESSION request to fetch the current session.
    /// - Parameter instanceUuid: The instance uuid.
    init(instanceUuid: String) {
        self.instanceUuid = instanceUuid
    }
}

/// session is nil when detached, unavailable, or the checked-out branch has
/// no session row yet.
struct InstanceCurrentSessionResponse: Codable, Hashable, Sendable {
    let session: SessionStub?
    let headState: String
    let currentSessionCode: String?
    /// The RAW branch name (nil whenever head_state !
    ///
    /// = "branch").
    let currentBranch: String?

    /// Creates an INSTANCE_CURRENT_SESSION response with the current session information.
    /// - Parameters:
    ///   - session: The current session stub; nil if detached or unavailable.
    ///   - headState: The git head state (branch, detached, or unavailable).
    ///   - currentSessionCode: The slugged code of the checked-out session; nil if detached.
    ///   - currentBranch: The raw branch name; nil if not checked out to a branch.
    init(session: SessionStub?, headState: String, currentSessionCode: String?, currentBranch: String?) {
        self.session = session
        self.headState = headState
        self.currentSessionCode = currentSessionCode
        self.currentBranch = currentBranch
    }
}

// MARK: - PATHS_GET / CONFIG_SET (v7)

struct PathsGetRequest: Codable, Hashable, Sendable {
    /// Creates a PATHS_GET request to fetch the configured filesystem paths.
    init() {}
}

/// Typed roots — never a map, because dictionary keys and coder key strategies
/// do not mix.
///
/// The fs root plus db/socket/backups come from Paths; the kbite roots from daemon_config, settable via CONFIG_SET.
/// `projectsRoot` is the absolute half of every `gmfs_relative_storage_path`.
struct PathsGetResponse: Codable, Hashable, Sendable {
    let gmFsRoot: String
    let dbPath: String
    let socketPath: String
    let backupsRoot: String
    let projectsRoot: String
    let kbiteRoot: String
    let kbiteOpenRoot: String
    let kbiteDigestedRoot: String

    /// Creates a PATHS_GET response with all configured filesystem paths.
    /// - Parameters:
    ///   - gmFsRoot: The GM filesystem root path.
    ///   - dbPath: The database file path.
    ///   - socketPath: The daemon socket path.
    ///   - backupsRoot: The backups directory root.
    ///   - projectsRoot: The projects directory root.
    ///   - kbiteRoot: The kbite resources root.
    ///   - kbiteOpenRoot: The kbite open-maw resources root.
    ///   - kbiteDigestedRoot: The kbite digested resources root.
    init(
        gmFsRoot: String,
        dbPath: String,
        socketPath: String,
        backupsRoot: String,
        projectsRoot: String,
        kbiteRoot: String,
        kbiteOpenRoot: String,
        kbiteDigestedRoot: String
    ) {
        self.gmFsRoot = gmFsRoot
        self.dbPath = dbPath
        self.socketPath = socketPath
        self.backupsRoot = backupsRoot
        self.projectsRoot = projectsRoot
        self.kbiteRoot = kbiteRoot
        self.kbiteOpenRoot = kbiteOpenRoot
        self.kbiteDigestedRoot = kbiteDigestedRoot
    }
}

struct ConfigSetRequest: Codable, Hashable, Sendable {
    let key: ConfigKey
    let value: String

    /// Creates a CONFIG_SET request to set a configuration value.
    /// - Parameters:
    ///   - key: The configuration key to set.
    ///   - value: The string value to set.
    init(key: ConfigKey, value: String) {
        self.key = key
        self.value = value
    }
}

struct ConfigSetResponse: Codable, Hashable, Sendable {
    let key: ConfigKey
    let value: String

    /// Creates a CONFIG_SET response with the updated configuration.
    /// - Parameters:
    ///   - key: The configuration key that was set.
    ///   - value: The string value that was set.
    init(key: ConfigKey, value: String) {
        self.key = key
        self.value = value
    }
}

// MARK: - BRIEFING_* (v21)

/// Reserve (or reset) the briefing row for one (owner, step) pair.
///
/// Exactly one owner may be supplied: promptUuid for bot-workflow briefings, or sessionUuid alone for /gm_task-owned
/// ones. The daemon derives session_uuid from the prompt's owner chain when prompt-owned, so the two can never
/// disagree. OPEN on an existing pair RESETS the row to `building` (version bump, content kept for wholesale
/// replacement at complete) — a step's briefing is always its CURRENT briefing, never a pile of drafts.
struct BriefingOpenRequest: Codable, Hashable, Sendable {
    let promptUuid: String?
    let sessionUuid: String?
    let briefingForStep: String
    /// The calling instance's identity.
    ///
    /// A prompt-owned open ALSO claims the activation for this key: briefings are consumed during explore (prompt still
    /// draft) and architect phases — long before set-status implementing would claim — and opening a briefing IS
    /// declaring "this instance works this prompt". Without it the zero-uuid resolution ladder had no path to success
    /// in the documented flows.
    let clientKey: String?

    /// Creates a BRIEFING_OPEN request to reserve or reset a briefing row.
    /// - Parameters:
    ///   - briefingForStep: The workflow step for the briefing.
    ///   - promptUuid: The prompt uuid if prompt-owned; nil for session-owned.
    ///   - sessionUuid: The session uuid for session-owned briefings; nil if prompt-owned.
    ///   - clientKey: The calling instance's identity to claim activation.
    init(
        briefingForStep: String,
        promptUuid: String? = nil,
        sessionUuid: String? = nil,
        clientKey: String? = nil
    ) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
        self.briefingForStep = briefingForStep
        self.clientKey = clientKey
    }
}

struct BriefingRowResponse: Codable, Hashable, Sendable {
    let briefing: AgentBriefingRow
    let created: Bool
    /// Well-formed dope dot-paths the briefing asked for that resolve to
    /// NOTHING in the dope tree.
    ///
    /// Reported back in the tool result so a briefer sees its own unresolvable refs instead of discovering them as
    /// silence. Additive OPTIONAL field (nil = this build did not compute it), so it decodes safely in both directions
    /// — no wire bump.
    let unresolvedDopeRefs: [String]?

    /// Creates a BRIEFING_OPEN or related response with the briefing row.
    /// - Parameters:
    ///   - briefing: The agent briefing row.
    ///   - created: True if this call created the row; false if it already existed.
    ///   - unresolvedDopeRefs: Dope dot-paths that resolve to nothing; nil if not computed.
    init(
        briefing: AgentBriefingRow,
        created: Bool = false,
        unresolvedDopeRefs: [String]? = nil
    ) {
        self.briefing = briefing
        self.created = created
        self.unresolvedDopeRefs = unresolvedDopeRefs
    }
}

/// building → ready.
///
/// The daemon stamps dope_scope_uuid + dope_scope_revision ITSELF from the session's SESSION_INSTANCE scope (the
/// writing agent cannot mis-stamp), and denormalizes each kbite ref's brief by joining the kbite tables — the briefer
/// passes file uuids only.
struct BriefingCompleteRequest: Codable, Hashable, Sendable {
    let briefingUuid: String
    let expectedVersion: Int64
    /// DOT-PATH strings (domain.entity.property style), never uuids.
    /// m0025: written as agent_briefing_dope_persistence child rows.
    let dopeRefs: [String]?
    /// KBite file uuids; the daemon resolves each brief at write time.
    let kbiteRefs: [String]?
    /// file_change uuids (agent_session_file_change children).
    let fileChangeRefs: [String]?
    /// Briefer self-report for dedup/tracking.
    let agentId: String?

    /// Creates a BRIEFING_COMPLETE request to seal the briefing and transition to ready.
    /// - Parameters:
    ///   - briefingUuid: The briefing uuid.
    ///   - expectedVersion: The expected briefing version.
    ///   - dopeRefs: Dope dot-path references included in the briefing; nil for none.
    ///   - kbiteRefs: KBite file uuid references; nil for none.
    ///   - fileChangeRefs: File change uuid references; nil for none.
    ///   - agentId: The agent id for self-reporting; nil if not applicable.
    init(
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
///
/// This is what makes the lookup DETERMINISTIC for spawned agents: gm resolves session (cwd) and clientKey (process
/// ancestry) itself, so no uuid ever has to survive a spawn prompt or an agent's echo. A real owner with no rows is
/// SUMMARY_ABSENT, never an empty fabrication.
struct BriefingGetRequest: Codable, Hashable, Sendable {
    let briefingUuid: String?
    let promptUuid: String?
    let sessionUuid: String?
    let step: String?
    let clientKey: String?

    /// Creates a BRIEFING_GET request to fetch a briefing by uuid or lookup criteria.
    /// - Parameters:
    ///   - briefingUuid: The briefing uuid; nil to resolve by owner and step.
    ///   - promptUuid: The prompt uuid if looking up a prompt-owned briefing; nil otherwise.
    ///   - sessionUuid: The session uuid if looking up a session-owned briefing; nil otherwise.
    ///   - step: The workflow step to look up; nil if using uuid.
    ///   - clientKey: The calling instance's client key for resolution; nil if not provided.
    init(
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
/// (a legal state, diagram-binding precedent).
///
/// Warn, never block.
struct BriefingStaleness: Codable, Hashable, Sendable {
    let stampedRevision: Int64?
    let currentRevision: Int64?
    let drifted: Bool
    let ghostDotPaths: [String]

    /// Creates a briefing staleness report with dope scope revision information.
    /// - Parameters:
    ///   - stampedRevision: The dope revision when the briefing was created; nil if none.
    ///   - currentRevision: The current dope revision; nil if no scope.
    ///   - drifted: True if the briefing is stale relative to current dope.
    ///   - ghostDotPaths: The dope entities referenced that are not present.
    init(
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

struct BriefingGetResponse: Codable, Hashable, Sendable {
    let briefing: AgentBriefingRow
    let staleness: BriefingStaleness

    /// Creates a BRIEFING_GET response with the briefing row and staleness report.
    /// - Parameters:
    ///   - briefing: The agent briefing row.
    ///   - staleness: The staleness report comparing briefing to current dope.
    init(briefing: AgentBriefingRow, staleness: BriefingStaleness) {
        self.briefing = briefing
        self.staleness = staleness
    }
}

struct BriefingListRequest: Codable, Hashable, Sendable {
    let promptUuid: String?
    let sessionUuid: String?

    /// Creates a BRIEFING_LIST request to fetch briefings for an owner.
    /// - Parameters:
    ///   - promptUuid: The prompt uuid to list prompt-owned briefings; nil for none.
    ///   - sessionUuid: The session uuid to list session-owned briefings; nil for none.
    init(promptUuid: String? = nil, sessionUuid: String? = nil) {
        self.promptUuid = promptUuid
        self.sessionUuid = sessionUuid
    }
}

struct BriefingListResponse: Codable, Hashable, Sendable {
    let briefings: [AgentBriefingRow]

    /// Creates a BRIEFING_LIST response with the briefing rows.
    /// - Parameter briefings: The agent briefing rows for the requested owner.
    init(briefings: [AgentBriefingRow]) {
        self.briefings = briefings
    }
}

/// The SubagentStart hook's one call.
///
/// The daemon resolves cwd → instance → current session → active_prompt_uuid, maps the agent role to its step via
/// BriefingStepSpec, and composes a compact plain-text stub (uuids, one-line summary, staleness flag, and the exact `gm
/// briefing get` pull command). Roles without a step — and sessions with nothing applicable — yield an EMPTY stub with
/// ok=true: the hook must never wedge a spawn.
struct BriefingStubRequest: Codable, Hashable, Sendable {
    let agentType: String?
    /// Client-resolved session (the gm CLI resolves cwd context; the daemon
    /// does not see the caller's working directory).
    let sessionUuid: String?
    /// Client-resolved instance identity (process ancestry) — scopes the
    /// stub to the SPAWNING Claude instance's activation, so concurrent
    /// prompts on one session each hand their agents the right briefing.
    let clientKey: String?

    /// Creates a BRIEFING_STUB request to generate a hook-time briefing stub.
    /// - Parameters:
    ///   - agentType: The agent type label; nil to resolve from role.
    ///   - sessionUuid: The session uuid resolved by the client.
    ///   - clientKey: The calling instance's client key for activation scoping.
    init(agentType: String? = nil, sessionUuid: String? = nil, clientKey: String? = nil) {
        self.agentType = agentType
        self.sessionUuid = sessionUuid
        self.clientKey = clientKey
    }
}

struct BriefingStubResponse: Codable, Hashable, Sendable {
    /// Plain text, ≤2KB by construction; empty when nothing applies.
    let stub: String

    /// Creates a BRIEFING_STUB response with the formatted briefing text.
    /// - Parameter stub: The plain-text briefing stub; empty if nothing applies.
    init(stub: String) {
        self.stub = stub
    }
}

// MARK: - DOPE_* (v11)

/// Create-or-return a dope scope (idempotent, the archOpen precedent).
/// scope_type is derived: PROMPT when promptUuid is present, else
/// SESSION_INSTANCE. `cloneFromSessionBase` forks the session's
/// SESSION_INSTANCE tree of the same code into a freshly created PROMPT scope.
struct DopeInitRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let promptUuid: String?
    let code: String
    let name: String
    let description: String?
    let cloneFromSessionBase: Bool?

    /// Creates a DOPE_INIT request to create or return a dope scope.
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - code: The scope code identifier.
    ///   - name: The scope name.
    ///   - promptUuid: The prompt uuid for PROMPT-tier scope; nil for SESSION_INSTANCE.
    ///   - description: Optional description of the scope.
    ///   - cloneFromSessionBase: True to fork the session's SESSION_INSTANCE tree into the new PROMPT scope.
    init(
        sessionUuid: String,
        code: String,
        name: String,
        promptUuid: String? = nil,
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

struct DopeScopeResponse: Codable, Hashable, Sendable {
    let scope: DopeScopeRow
    let created: Bool

    /// Creates a DOPE_INIT or DOPE-related response with the scope row.
    /// - Parameters:
    ///   - scope: The dope scope row.
    ///   - created: True if this call created the scope; false if it existed.
    init(scope: DopeScopeRow, created: Bool) {
        self.scope = scope
        self.created = created
    }
}

/// Scope enumeration for pickers (v12).
///
/// Without promptUuid: the session's SESSION_INSTANCE scopes. With it: ONLY that prompt's PROMPT scopes — never a
/// union, so a GUI never string-parses dopeGet's "several dope scopes match" BAD_REQUEST. Unknown session/prompt uuid
/// is NOT_FOUND; a real target with no scopes is a normal empty list, never SUMMARY_ABSENT. No code filter: enumerating
/// IS the point and every row carries its own code.
struct DopeListRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let promptUuid: String?

    /// Creates a DOPE_LIST request to enumerate dope scopes.
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - promptUuid: The prompt uuid to list PROMPT scopes; nil for SESSION_INSTANCE scopes.
    init(sessionUuid: String, promptUuid: String? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
    }
}

struct DopeListResponse: Codable, Hashable, Sendable {
    /// ORDER BY code — the SAME order dopeGet's candidate list prints, so a
    /// picker's rows and the disambiguator message can never disagree.
    let scopes: [DopeScopeRow]

    /// Creates a DOPE_LIST response with the enumerated scope rows.
    /// - Parameter scopes: The dope scope rows ordered by code.
    init(scopes: [DopeScopeRow]) {
        self.scopes = scopes
    }
}

/// Tree read.
///
/// With promptUuid set, the PROMPT scope is preferred and the SESSION_INSTANCE tree is the fallback (resolvedVia
/// reports which). With several scopes matching and no code, the store answers BAD_REQUEST naming the candidate codes.
struct DopeGetRequest: Codable, Hashable, Sendable {
    /// Empty ONLY when addressing by `projectUuid` instead.
    ///
    /// Kept non-optional so every existing caller and every older peer's
    /// payload still decodes unchanged — a project-tier read passes "" here
    /// and fills `projectUuid`. Making it Optional would have been a
    /// breaking shape change on an existing message for no gain.
    let sessionUuid: String
    let promptUuid: String?
    let code: String?
    /// PROJECT-tier addressing: reads the PROJECT_ITEM overlay, else the
    /// BASE_PROJECT scope that `gm dope promote` maintains.
    ///
    /// Additive OPTIONAL, so no wire bump: an older peer omits it and gets
    /// exactly today's session-only behavior.
    let projectUuid: String?
    /// Merge the masking overlay over its base and return the resolved tree.
    ///
    /// OPT-IN, and deliberately so: without it every existing caller — the CLI, GMVibes, gm diagram from-dope, the
    /// screenshot path — keeps its exact single-layer semantics. Additive OPTIONAL, so an older peer that omits it
    /// means "unresolved", which is today's behavior.
    let resolved: Bool?

    /// Creates a DOPE_GET request to fetch a dope scope tree.
    /// - Parameters:
    ///   - sessionUuid: The session uuid; empty string for PROJECT-tier addressing.
    ///   - promptUuid: The prompt uuid for PROMPT-tier scope; nil for SESSION_INSTANCE fallback.
    ///   - code: The scope code; nil to handle disambiguation or use default.
    ///   - resolved: True to merge overlay over base and return resolved tree; nil for unresolved.
    ///   - projectUuid: The project uuid for PROJECT-tier addressing; nil for session-tier.
    init(
        sessionUuid: String,
        promptUuid: String? = nil,
        code: String? = nil,
        resolved: Bool? = nil,
        projectUuid: String? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    /// Creates a DOPE_GET request for PROJECT-tier addressing.
    /// - Parameters:
    ///   - projectUuid: The project uuid to read its scope ladder.
    ///   - code: The scope code; nil for default.
    ///   - resolved: True to merge overlay over base; nil for unresolved.
    init(projectUuid: String, code: String? = nil, resolved: Bool? = nil) {
        self.sessionUuid = ""
        self.promptUuid = nil
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, code, resolved, projectUuid
    }

    /// Decodes a dope search result from a keyed container, providing defaults for missing keys.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Decoding errors from the container.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid) ?? ""
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved)
        projectUuid = try c.decodeIfPresent(String.self, forKey: .projectUuid)
    }
}

struct DopeGetResponse: Codable, Hashable, Sendable {
    let tree: DopeScopeTree
    /// Which scope supplied the tree: "prompt" | "session_base", or
    /// "<overlay_tier>_over_<base_tier>" when --resolved merged two layers.
    let resolvedVia: String
    /// Present only for a resolved read: dot-path -> provenance.
    let resolutions: [DopeOverlay.Resolution]?
    /// Dot-paths a whiteout masked away.
    let hidden: [String]?
    /// Non-fatal observations (orphaned masks).
    ///
    /// Never an error.
    let warnings: [String]?
    /// Per-area content counters ("persistence", "cogs").
    ///
    /// A client compares one number to decide whether that subtree needs refetching, which is what makes dope
    /// sub-LOADABLE. These sit BESIDE tree.revision, which remains the whole-tree counter and the sole CAS gate.
    let areaVersions: [String: Int64]?

    /// Creates a DOPE_GET response with the scope tree and optional metadata.
    /// - Parameters:
    ///   - tree: The dope scope tree.
    ///   - resolvedVia: The scope that supplied the tree (prompt, session_base, or merged tiers).
    ///   - resolutions: Provenance mapping for resolved overlays; nil for non-resolved reads.
    ///   - hidden: Whiteout dot-paths that were masked away; nil if none.
    ///   - warnings: Non-fatal observations like orphaned masks; nil if none.
    ///   - areaVersions: Per-area content counters for change detection; nil if not relevant.
    init(
        tree: DopeScopeTree,
        resolvedVia: String,
        resolutions: [DopeOverlay.Resolution]? = nil,
        hidden: [String]? = nil,
        warnings: [String]? = nil,
        areaVersions: [String: Int64]? = nil
    ) {
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
enum DopeSearchScope: String, Codable, Hashable, CaseIterable, Sendable {
    case prompt, session, project
}

/// One UNION arm per source table.
enum DopeSearchSource: String, Codable, Hashable, CaseIterable, Sendable {
    case scope, persistence, entity, property, enumeration, option, cog, cogElement
}

struct DopeSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let scope: DopeSearchScope
    let sessionUuid: String?
    let promptUuid: String?
    let projectUuid: String?
    /// Keep only hits whose dot-path came from the overlay rather than the
    /// base.
    ///
    /// A post-filter over resolver provenance, so the FTS query is the same shape with and without it.
    let onlyMasks: Bool?
    /// Restrict the UNION to these arms. m0028-era ADDITIVE OPTIONAL: nil or
    /// empty means every arm, which is exactly what the absent field meant, so
    /// it decodes safely in both directions and needed no wire bump of its own.
    ///
    /// The arms were always enumerable through `DopeSearchSource`; what was
    /// missing was any way for a caller to SELECT among them, which is what the
    /// agent tool surface needs when it asks for persistence rows or cogs
    /// specifically rather than the whole tree.
    let sources: [DopeSearchSource]?
    let limit: Int?

    /// Creates a DOPE_SEARCH request to find dope entities by keyword.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - scope: The search scope (prompt, session, or project).
    ///   - sessionUuid: Filter to one session; nil to search all.
    ///   - promptUuid: Filter to one prompt; nil to search all.
    ///   - projectUuid: Filter to one project; nil to search all.
    ///   - onlyMasks: Filter to overlay-sourced hits; nil for all sources.
    ///   - sources: Restrict the search to these entity types; nil or empty for all.
    ///   - limit: Maximum results to return; nil for no limit.
    init(
        query: String,
        scope: DopeSearchScope,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        projectUuid: String? = nil,
        onlyMasks: Bool? = nil,
        sources: [DopeSearchSource]? = nil,
        limit: Int? = nil
    ) {
        self.query = query; self.scope = scope; self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid; self.projectUuid = projectUuid
        self.onlyMasks = onlyMasks; self.sources = sources; self.limit = limit
    }
}

struct DopeSearchHit: Codable, Hashable, Sendable {
    let kind: String
    let subjectUuid: String
    let scopeUuid: String
    let scopeCode: String
    let scopeType: String
    /// The dot-path — the same identity the resolver merges on.
    let path: String
    let title: String
    let excerpt: String
    let score: Double
    /// Resolver provenance; present only for an --only-masks search.
    let origin: String?

    /// Creates a search hit result.
    /// - Parameters:
    ///   - kind: The entity kind (scope, persistence, entity, property, etc.).
    ///   - subjectUuid: The uuid of the found entity.
    ///   - scopeUuid: The uuid of the scope containing the entity.
    ///   - scopeCode: The code of the scope.
    ///   - scopeType: The type of the scope (prompt, session, or project).
    ///   - path: The dot-path of the entity.
    ///   - title: The entity title or name.
    ///   - excerpt: A text excerpt showing context.
    ///   - score: The search relevance score.
    ///   - origin: Provenance layer; nil unless filtered by --only-masks.
    init(
        kind: String,
        subjectUuid: String,
        scopeUuid: String,
        scopeCode: String,
        scopeType: String,
        path: String,
        title: String,
        excerpt: String,
        score: Double,
        origin: String?
    ) {
        self.kind = kind; self.subjectUuid = subjectUuid; self.scopeUuid = scopeUuid
        self.scopeCode = scopeCode; self.scopeType = scopeType; self.path = path
        self.title = title; self.excerpt = excerpt; self.score = score; self.origin = origin
    }
}

struct DopeSearchResponse: Codable, Hashable, Sendable {
    let hits: [DopeSearchHit]

    /// Creates a DOPE_SEARCH response with the search results.
    /// - Parameter hits: The search hits found.
    init(hits: [DopeSearchHit]) { self.hits = hits }
}

// MARK: - COGS

struct DopeCogElementNode: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let elementType: String
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let parentElementUuid: String?
    /// Ghost-tolerant CODE reference to a dope scope, resolved at read time —
    /// never a uuid FK (ingest re-mints uuids, and scope delete is not
    /// offered, so there is no ON DELETE answer to give).
    let dopeScopeCode: String?
    /// From the type's subtype table.
    ///
    /// Hull only.
    let primaryPath: String?
    /// From the type's subtype table.
    ///
    /// PersistenceOwner only: the CODE of the persistence domain this element's parent Hull owns. Additive and
    /// OPTIONAL, so it decodes safely in both directions.
    let dopePersistenceCode: String?
    let deletedOn: String?

    /// Creates a cog element node representing a part of a cog hierarchy.
    /// - Parameters:
    ///   - uuid: The element uuid.
    ///   - version: The element version for optimistic locking.
    ///   - elementType: The element type (Hull, PersistenceOwner, etc.).
    ///   - code: The element code identifier.
    ///   - name: The element name.
    ///   - description: The element description.
    ///   - sortOrder: The display sort order.
    ///   - parentElementUuid: The parent element uuid; nil if root.
    ///   - dopeScopeCode: Ghost-tolerant reference to a dope scope; nil if not applicable.
    ///   - primaryPath: The primary path for Hull elements; nil for others.
    ///   - deletedOn: Timestamp if soft-deleted; nil if active.
    ///   - dopePersistenceCode: Owned persistence domain code for PersistenceOwner; nil otherwise.
    init(
        uuid: String,
        version: Int64,
        elementType: String,
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        parentElementUuid: String?,
        dopeScopeCode: String?,
        primaryPath: String?,
        deletedOn: String?,
        dopePersistenceCode: String? = nil
    ) {
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

struct DopeCogNode: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let deletedOn: String?
    let elements: [DopeCogElementNode]

    /// Creates a cog node representing a cog in a dope scope.
    /// - Parameters:
    ///   - uuid: The cog uuid.
    ///   - version: The cog version for optimistic locking.
    ///   - code: The cog code identifier.
    ///   - name: The cog name.
    ///   - description: The cog description.
    ///   - sortOrder: The display sort order.
    ///   - deletedOn: Timestamp if soft-deleted; nil if active.
    ///   - elements: The child element nodes.
    init(
        uuid: String,
        version: Int64,
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        deletedOn: String?,
        elements: [DopeCogElementNode]
    ) {
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

struct DopeCogAddRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let code: String
    let name: String
    let description: String?
    let sortOrder: Int?

    /// Creates a DOPE_COG_ADD request to create a new cog in a scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to add the cog to.
    ///   - code: The cog code identifier.
    ///   - name: The cog name.
    ///   - description: The cog description; nil if none.
    ///   - sortOrder: The display sort order; nil for default.
    init(
        scopeUuid: String,
        code: String,
        name: String,
        description: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.scopeUuid = scopeUuid; self.code = code; self.name = name
        self.description = description; self.sortOrder = sortOrder
    }
}

struct DopeCogUpdateRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?

    /// Creates a DOPE_COG_UPDATE request to modify a cog's properties.
    /// - Parameters:
    ///   - uuid: The cog uuid to update.
    ///   - expectedVersion: The expected cog version.
    ///   - code: New code identifier; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    init(
        uuid: String,
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
    }
}

struct DopeCogDeleteRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let soft: Bool?

    /// Creates a DOPE_COG_DELETE request to remove or soft-delete a cog.
    /// - Parameters:
    ///   - uuid: The cog uuid to delete.
    ///   - expectedVersion: The expected cog version.
    ///   - soft: True for soft-delete (timestamped); false for hard delete; nil for default.
    init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

struct DopeCogElementAddRequest: Codable, Hashable, Sendable {
    let cogUuid: String
    let elementType: String
    let code: String
    let name: String
    let description: String?
    let sortOrder: Int?
    let parentElementUuid: String?
    let dopeScopeCode: String?
    let primaryPath: String?
    /// PersistenceOwner's owned domain CODE.
    ///
    /// Additive and OPTIONAL, so it decodes safely in both directions per the wire convention.
    let dopePersistenceCode: String?

    /// Creates a DOPE_COG_ELEMENT_ADD request to add an element to a cog.
    /// - Parameters:
    ///   - cogUuid: The cog uuid to add the element to.
    ///   - elementType: The element type (Hull, PersistenceOwner, etc.).
    ///   - code: The element code identifier.
    ///   - name: The element name.
    ///   - description: The element description; nil if none.
    ///   - sortOrder: The display sort order; nil for default.
    ///   - parentElementUuid: Parent element uuid; nil if root.
    ///   - dopeScopeCode: Ghost-tolerant dope scope reference; nil if not applicable.
    ///   - primaryPath: Primary path for Hull elements; nil for other types.
    ///   - dopePersistenceCode: Owned persistence domain code; nil for non-PersistenceOwner.
    init(
        cogUuid: String,
        elementType: String,
        code: String,
        name: String,
        description: String? = nil,
        sortOrder: Int? = nil,
        parentElementUuid: String? = nil,
        dopeScopeCode: String? = nil,
        primaryPath: String? = nil,
        dopePersistenceCode: String? = nil
    ) {
        self.cogUuid = cogUuid; self.elementType = elementType; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.parentElementUuid = parentElementUuid; self.dopeScopeCode = dopeScopeCode
        self.primaryPath = primaryPath; self.dopePersistenceCode = dopePersistenceCode
    }
}

struct DopeCogElementUpdateRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let dopeScopeCode: String?
    let clearDopeScopeCode: Bool?
    let primaryPath: String?

    /// Creates a DOPE_COG_ELEMENT_UPDATE request to modify a cog element.
    /// - Parameters:
    ///   - uuid: The element uuid to update.
    ///   - expectedVersion: The expected element version.
    ///   - code: New code identifier; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    ///   - dopeScopeCode: New dope scope reference; nil to leave unchanged.
    ///   - clearDopeScopeCode: True to clear the scope reference; nil to ignore.
    ///   - primaryPath: New primary path; nil to leave unchanged.
    init(
        uuid: String,
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        dopeScopeCode: String? = nil,
        clearDopeScopeCode: Bool? = nil,
        primaryPath: String? = nil
    ) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.dopeScopeCode = dopeScopeCode; self.clearDopeScopeCode = clearDopeScopeCode
        self.primaryPath = primaryPath
    }
}

struct DopeCogElementDeleteRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let soft: Bool?

    /// Creates a DOPE_COG_ELEMENT_DELETE request to remove or soft-delete a cog element.
    /// - Parameters:
    ///   - uuid: The element uuid to delete.
    ///   - expectedVersion: The expected element version.
    ///   - soft: True for soft-delete (timestamped); false for hard delete; nil for default.
    init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

struct DopeCogGetRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let code: String?

    /// Creates a DOPE_COG_GET request to fetch cogs from a scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to query.
    ///   - code: Filter to one cog by code; nil to retrieve all.
    init(scopeUuid: String, code: String? = nil) {
        self.scopeUuid = scopeUuid; self.code = code
    }
}

struct DopeCogResponse: Codable, Hashable, Sendable {
    let cog: DopeCogNode
    let revision: Int64

    /// Creates a DOPE_COG response with the created or modified cog.
    /// - Parameters:
    ///   - cog: The cog node.
    ///   - revision: The scope revision after the operation.
    init(cog: DopeCogNode, revision: Int64) { self.cog = cog; self.revision = revision }
}

struct DopeCogElementResponse: Codable, Hashable, Sendable {
    let element: DopeCogElementNode
    let revision: Int64

    /// Creates a DOPE_COG_ELEMENT response with the created or modified element.
    /// - Parameters:
    ///   - element: The cog element node.
    ///   - revision: The scope revision after the operation.
    init(element: DopeCogElementNode, revision: Int64) {
        self.element = element; self.revision = revision
    }
}

struct DopeCogDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let cascadedElements: Int
    let scopeUuid: String
    let revision: Int64

    /// Creates a DOPE_COG_DELETE response with deletion results.
    /// - Parameters:
    ///   - deletedUuid: The uuid of the deleted cog.
    ///   - cascadedElements: The number of child elements cascade-deleted.
    ///   - scopeUuid: The scope uuid of the deleted cog.
    ///   - revision: The scope revision after the deletion.
    init(deletedUuid: String, cascadedElements: Int, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid; self.cascadedElements = cascadedElements
        self.scopeUuid = scopeUuid; self.revision = revision
    }
}

struct DopeCogGetResponse: Codable, Hashable, Sendable {
    let cogs: [DopeCogNode]

    /// Creates a DOPE_COG_GET response with the fetched cogs.
    /// - Parameter cogs: The cog nodes from the scope.
    init(cogs: [DopeCogNode]) { self.cogs = cogs }
}

/// DOPE_PROMOTE — publish a session's SESSION_INSTANCE tree into the
/// project's BASE_PROJECT scope.
///
/// Runs automatically at boot behind DopeBootSync, and manually via `gm dope promote` (a non-throwing boot path that
/// silently does nothing is undebuggable, so the verb exists too).
struct DopePromoteRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let code: String?
    /// Compute the decision and write NOTHING.
    ///
    /// This is what makes "why didn't it promote?" answerable, and it is what gm doctor uses to report a stale
    /// BASE_PROJECT without ever publishing as a side effect.
    let dryRun: Bool?

    /// Creates a DOPE_PROMOTE request to publish a session's scope tree to the project base scope.
    /// - Parameters:
    ///   - sessionUuid: The session uuid to promote from.
    ///   - code: Filter to one scope; nil to promote all.
    ///   - dryRun: True to compute decision without writing; false or nil to publish.
    init(sessionUuid: String, code: String? = nil, dryRun: Bool? = nil) {
        self.sessionUuid = sessionUuid
        self.code = code
        self.dryRun = dryRun
    }
}

struct DopePromotedScope: Codable, Hashable, Sendable {
    let code: String
    let baseScopeUuid: String
    /// The high-water the base carried before this promotion.
    let fromRevision: Int64
    /// The source revision now recorded as the high-water.
    let toRevision: Int64
    let counts: DopeTreeCounts

    /// Creates a promoted scope record with revision and content details.
    /// - Parameters:
    ///   - code: The scope code.
    ///   - baseScopeUuid: The base scope uuid in the project.
    ///   - fromRevision: The base scope's revision before promotion.
    ///   - toRevision: The session scope revision promoted.
    ///   - counts: Entity count breakdown of the promoted tree.
    init(
        code: String,
        baseScopeUuid: String,
        fromRevision: Int64,
        toRevision: Int64,
        counts: DopeTreeCounts
    ) {
        self.code = code
        self.baseScopeUuid = baseScopeUuid
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.counts = counts
    }
}

struct DopePromoteResponse: Codable, Hashable, Sendable {
    /// On a dry run these are what WOULD be published, and nothing was
    /// written.
    let promoted: [DopePromotedScope]
    /// "branch_mismatch" | "no_session_scope" | "up_to_date" | nil.
    let skipped: String?
    let detail: String?

    /// Creates a DOPE_PROMOTE response with promotion results or skip reasons.
    /// - Parameters:
    ///   - promoted: The scopes that were promoted (empty on skip or dry run).
    ///   - skipped: Skip reason if promotion was not performed; nil if successful.
    ///   - detail: Additional context explaining the skip or operation result.
    init(promoted: [DopePromotedScope], skipped: String? = nil, detail: String? = nil) {
        self.promoted = promoted
        self.skipped = skipped
        self.detail = detail
    }
}

/// The generic node-mutation payload. nil = leave alone; the clear* flags
/// mean "set NULL" — a distinction plain optionals cannot express.
///
/// Which fields a level owns is DopeLevelSpec's ownedFields; a misdirected field is a precise BAD_REQUEST.
struct DopeNodeFields: Codable, Hashable, Sendable {
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let entityType: DopeEntityType?
    let repoRepresentativeFile: String?
    let baseComposableUuid: String?
    let dataType: DopePropertyDataType?
    let nullable: Bool?
    let isUnique: Bool?
    let autoIncrement: Bool?
    let textCharLimit: Int?
    let enumUuid: String?
    let relationshipTargetUuid: String?
    let baseOriginPropertyUuid: String?
    let clearRepoRepresentativeFile: Bool?
    let clearBaseComposable: Bool?
    let clearBaseOrigin: Bool?
    let clearAutoIncrement: Bool?
    let clearTextCharLimit: Bool?
    let clearEnum: Bool?
    let clearRelationshipTarget: Bool?

    /// Creates generic node mutation fields; nil values leave fields unchanged; clear* flags set them NULL.
    /// - Parameters:
    ///   - code: New code; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    ///   - entityType: New entity type; nil to leave unchanged.
    ///   - repoRepresentativeFile: New file path; nil to leave unchanged.
    ///   - baseComposableUuid: New base composable uuid; nil to leave unchanged.
    ///   - dataType: New property data type; nil to leave unchanged.
    ///   - nullable: New nullability flag; nil to leave unchanged.
    ///   - isUnique: New uniqueness flag; nil to leave unchanged.
    ///   - autoIncrement: New autoincrement flag; nil to leave unchanged.
    ///   - textCharLimit: New character limit; nil to leave unchanged.
    ///   - enumUuid: New enum uuid; nil to leave unchanged.
    ///   - relationshipTargetUuid: New relationship target uuid; nil to leave unchanged.
    ///   - baseOriginPropertyUuid: New base origin uuid; nil to leave unchanged.
    ///   - clearRepoRepresentativeFile: True to set file path to NULL.
    ///   - clearBaseComposable: True to set base composable to NULL.
    ///   - clearBaseOrigin: True to set base origin to NULL.
    ///   - clearAutoIncrement: True to set autoincrement to NULL.
    ///   - clearTextCharLimit: True to set character limit to NULL.
    ///   - clearEnum: True to set enum to NULL.
    ///   - clearRelationshipTarget: True to set relationship target to NULL.
    init(
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

struct DopeNodeAddRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let parentUuid: String
    let fields: DopeNodeFields

    /// Creates a DOPE_NODE_ADD request to insert a new dope entity.
    /// - Parameters:
    ///   - level: The dope level where the node belongs (scope, entity, property, etc.).
    ///   - parentUuid: The parent node uuid.
    ///   - fields: The node's field values.
    init(level: DopeLevel, parentUuid: String, fields: DopeNodeFields) {
        self.level = level
        self.parentUuid = parentUuid
        self.fields = fields
    }
}

struct DopeNodeUpdateRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let nodeUuid: String
    let expectedVersion: Int64
    let fields: DopeNodeFields

    /// Creates a DOPE_NODE_UPDATE request to modify a dope entity.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - nodeUuid: The node uuid to update.
    ///   - expectedVersion: The expected node version.
    ///   - fields: The field values to update.
    init(level: DopeLevel, nodeUuid: String, expectedVersion: Int64, fields: DopeNodeFields) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.fields = fields
    }
}

struct DopeNodeDeleteRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let nodeUuid: String
    let expectedVersion: Int64
    /// Soft delete: stamp `deleted_on` instead of removing the row.
    ///
    /// The node stays visible to every read (that IS the feature — it communicates an intended delete), keeps
    /// satisfying every FK, and in an overlay tree acts as the resolver's whiteout over the base node at that dot-path.
    ///
    /// Additive OPTIONAL, so a peer that omits it still means "hard delete".
    let soft: Bool?

    /// Creates a DOPE_NODE_DELETE request to remove or soft-delete a dope entity.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - nodeUuid: The node uuid to delete.
    ///   - expectedVersion: The expected node version.
    ///   - soft: True for soft-delete (timestamped); nil or false for hard delete.
    init(
        level: DopeLevel,
        nodeUuid: String,
        expectedVersion: Int64,
        soft: Bool? = nil
    ) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.soft = soft
    }
}

struct DopeNodeResponse: Codable, Hashable, Sendable {
    let level: DopeLevel
    let uuid: String
    let version: Int64
    let scopeUuid: String
    /// The scope's whole-tree content counter after this mutation.
    let revision: Int64

    /// Creates a DOPE_NODE response with the created or modified node details.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - uuid: The node uuid.
    ///   - version: The node version after the operation.
    ///   - scopeUuid: The scope uuid containing the node.
    ///   - revision: The scope revision after the operation.
    init(level: DopeLevel, uuid: String, version: Int64, scopeUuid: String, revision: Int64) {
        self.level = level
        self.uuid = uuid
        self.version = version
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

struct DopeNodeDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let cascaded: DopeTreeCounts
    let scopeUuid: String
    let revision: Int64

    /// Creates a DOPE_NODE_DELETE response with deletion results.
    /// - Parameters:
    ///   - deletedUuid: The uuid of the deleted node.
    ///   - cascaded: Count of cascade-deleted child nodes.
    ///   - scopeUuid: The scope uuid of the deleted node.
    ///   - revision: The scope revision after the deletion.
    init(deletedUuid: String, cascaded: DopeTreeCounts, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascaded = cascaded
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

/// Parse + validate the on-disk tree.
///
/// Never writes. Exactly one of scopeUuid (resolve the scope's own instance root) or dirPath (an explicit instance root
/// — read-only, still required to be a git checkout) must be present.
struct DopeReadRepoRequest: Codable, Hashable, Sendable {
    let scopeUuid: String?
    let dirPath: String?

    /// Creates a DOPE_READ_REPO request to parse and validate a scope's on-disk tree.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to resolve its instance root; nil if dirPath is given.
    ///   - dirPath: Explicit instance root path; nil to use the scope's own.
    init(scopeUuid: String? = nil, dirPath: String? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
    }
}

struct DopeReadRepoResponse: Codable, Hashable, Sendable {
    let bundle: DopeDocumentBundle
    let onDiskRevision: Int64
    let dbRevision: Int64?
    let drift: Bool?
    let warnings: [String]

    /// Creates a DOPE_READ_REPO response with the parsed tree and version information.
    /// - Parameters:
    ///   - bundle: The parsed dope document bundle.
    ///   - onDiskRevision: The file version found on disk.
    ///   - dbRevision: The database revision; nil if not applicable.
    ///   - drift: True if on-disk and database revisions diverge.
    ///   - warnings: Non-fatal observations during parsing.
    init(
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

/// db → files.
///
/// Refuses when the on-disk version is AHEAD of the db revision (the files hold edits never ingested) unless force.
/// Does not modify the db beyond the audit event; does not bump revision (a projection, so a repeat run is
/// byte-idempotent).
struct DopeWriteRepoRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let force: Bool?

    /// Creates a DOPE_WRITE_REPO request to write the database tree to files.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to write.
    ///   - force: True to overwrite when on-disk version is ahead; false or nil to refuse.
    init(scopeUuid: String, force: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.force = force
    }
}

struct DopeWriteRepoResponse: Codable, Hashable, Sendable {
    let dopeRoot: String
    let filesWritten: [String]
    let filesPruned: [String]
    let revision: Int64

    /// Creates a DOPE_WRITE_REPO response with the written files and result.
    /// - Parameters:
    ///   - dopeRoot: The root directory where files were written.
    ///   - filesWritten: Paths of files created or modified.
    ///   - filesPruned: Paths of files removed.
    ///   - revision: The database revision at write time.
    init(dopeRoot: String, filesWritten: [String], filesPruned: [String], revision: Int64) {
        self.dopeRoot = dopeRoot
        self.filesWritten = filesWritten
        self.filesPruned = filesPruned
        self.revision = revision
    }
}

/// files → db, whole-tree overwrite (no smart diff): the on-disk version
/// must equal db revision + 1 exactly.
///
/// Every child uuid changes on every ingest — the locked consequence of uuid-free JSON.
struct DopeIngestRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// Explicit instance root to read from; nil = the scope's own.
    let dirPath: String?
    /// Files-are-authoritative mode (boot sync only): permits any strictly
    /// FORWARD move (on-disk version > db revision), including seeding a
    /// virgin scope at revision 0 from a tree at any version.
    ///
    /// Never moves backward. Additive optional — absent means the strict +1 gate.
    let adopt: Bool?

    /// Creates a DOPE_INGEST request to parse files and update the database scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to ingest into.
    ///   - dirPath: Explicit instance root path; nil to use the scope's own.
    ///   - adopt: True for files-are-authoritative mode (boot sync); nil for strict +1.
    init(scopeUuid: String, dirPath: String? = nil, adopt: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
        self.adopt = adopt
    }
}

struct DopeIngestResponse: Codable, Hashable, Sendable {
    let scope: DopeScopeRow
    let counts: DopeTreeCounts
    /// Revision the scope held before this ingest (additive optional).
    let previousRevision: Int64?
    /// Revisions skipped beyond the strict +1 step (adopt only, additive).
    let gapCrossed: Int64?

    /// Creates a DOPE_INGEST response with the updated scope and entity counts.
    /// - Parameters:
    ///   - scope: The scope row after ingestion.
    ///   - counts: Entity counts in the ingested tree.
    ///   - previousRevision: The scope's revision before ingestion (additive optional).
    ///   - gapCrossed: Revisions skipped in adopt mode; nil in strict mode.
    init(
        scope: DopeScopeRow,
        counts: DopeTreeCounts,
        previousRevision: Int64? = nil,
        gapCrossed: Int64? = nil
    ) {
        self.scope = scope
        self.counts = counts
        self.previousRevision = previousRevision
        self.gapCrossed = gapCrossed
    }
}

// MARK: - DIAGRAM_* (v15)

/// Create-or-return a diagram (idempotent per (tier owner, code) — the
/// dopeInit precedent).
///
/// Exactly ONE owner uuid picks the tier; the store derives and persists the full ancestor chain by joins
/// (chain-non-null ladder). gmccDiagramPath is refused at PROJECT tier (no instance root to resolve it against).
struct DiagramInitRequest: Codable, Hashable, Sendable {
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String
    let name: String
    let description: String?
    let gmccDiagramPath: String?
    /// The dope scope this whole diagram reads/writes through.
    ///
    /// Restricted to the masking tiers (PROJECT_ITEM / SESSION_INSTANCE_ITEM) so a canvas always edits a personal
    /// overlay rather than shared truth.
    let dopeScopeCode: String?

    /// Creates a DIAGRAM_INIT request to create or retrieve a diagram.
    /// - Parameters:
    ///   - code: The diagram code identifier.
    ///   - name: The diagram name.
    ///   - projectUuid: Project tier owner; nil if not at project tier.
    ///   - instanceUuid: Instance tier owner; nil if not at instance tier.
    ///   - sessionUuid: Session tier owner; nil if not at session tier.
    ///   - promptUuid: Prompt tier owner; nil if not at prompt tier.
    ///   - description: The diagram description; nil if none.
    ///   - gmccDiagramPath: GMK diagram path; nil at project tier or if none.
    ///   - dopeScopeCode: Dope scope for editing (masking tiers only); nil for default.
    init(
        code: String,
        name: String,
        projectUuid: String? = nil,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
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

struct DiagramResponse: Codable, Hashable, Sendable {
    let diagram: DiagramRow
    let created: Bool

    /// Creates a DIAGRAM_INIT response with the created or retrieved diagram.
    /// - Parameters:
    ///   - diagram: The diagram row.
    ///   - created: True if INIT created the diagram; false if it existed.
    init(diagram: DiagramRow, created: Bool) {
        self.diagram = diagram
        self.created = created
    }
}

/// Picker enumeration — the v12 dopeList contract verbatim: exactly one
/// owner uuid, exactly that tier's rows for that owner, never a union or a
/// cross-tier ladder, ORDER BY code.
///
/// Unknown owner is NOT_FOUND; a real owner with no diagrams is a normal empty list.
struct DiagramListRequest: Codable, Hashable, Sendable {
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    /// v23, additive: server-side visibility filter (PRIVATE|PUBLIC).
    ///
    /// Absent = both. Still single-owner single-tier — never a union.
    let visibility: String?

    /// Creates a DIAGRAM_LIST request to fetch diagrams for a tier owner.
    /// - Parameters:
    ///   - projectUuid: Project tier owner; nil if not querying project tier.
    ///   - instanceUuid: Instance tier owner; nil if not querying instance tier.
    ///   - sessionUuid: Session tier owner; nil if not querying session tier.
    ///   - promptUuid: Prompt tier owner; nil if not querying prompt tier.
    ///   - visibility: Filter by visibility (PRIVATE or PUBLIC); nil for both.
    init(
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

struct DiagramListResponse: Codable, Hashable, Sendable {
    let diagrams: [DiagramRow]

    /// Creates a DIAGRAM_LIST response with the diagrams for the requested tier owner.
    /// - Parameter diagrams: The diagram rows from the tier.
    init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// Full-tree read: by diagramUuid, or by exactly one owner uuid + optional
/// code.
///
/// Deliberately NO cross-tier fallback ladder (tiers are explicit workspaces — the ladder belongs to dope binding
/// resolution INSIDE the diagram). Several owner matches without a code → BAD_REQUEST naming the candidate codes; a
/// real owner with none → SUMMARY_ABSENT (diagramAbsent). The response does NOT embed dope trees — clients pair it with
/// DOPE_GET.
struct DiagramGetRequest: Codable, Hashable, Sendable {
    let diagramUuid: String?
    let projectUuid: String?
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String?

    /// Creates a DIAGRAM_GET request to fetch a diagram's full tree.
    /// - Parameters:
    ///   - diagramUuid: Fetch by diagram uuid; nil to use owner+code.
    ///   - projectUuid: Project tier owner; nil if not querying project tier.
    ///   - instanceUuid: Instance tier owner; nil if not querying instance tier.
    ///   - sessionUuid: Session tier owner; nil if not querying session tier.
    ///   - promptUuid: Prompt tier owner; nil if not querying prompt tier.
    ///   - code: Filter to one diagram by code; nil to use first match.
    init(
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

struct DiagramGetResponse: Codable, Hashable, Sendable {
    let tree: DiagramTree
    /// One row per dope_scope binding element (resolvedVia nil = ghost).
    let bindings: [DiagramBindingResolution]
    /// The OWNER's `gmfs_relative_storage_path` — the root a rendered
    /// screenshot lands under, whichever tier owns the diagram.
    ///
    /// An additive optional, so an older peer ignores it. It rides this
    /// response rather than being fetched separately because the alternative is
    /// three round trips for something the daemon already held while resolving
    /// the owner.
    let ownerStoragePath: String?

    /// Creates a DIAGRAM_GET response with the full diagram tree and bindings.
    /// - Parameters:
    ///   - tree: The diagram tree with all nodes and relationships.
    ///   - bindings: Resolved dope scope bindings for diagram elements.
    ///   - ownerStoragePath: The owner's storage path for screenshots; nil if unavailable.
    init(
        tree: DiagramTree,
        bindings: [DiagramBindingResolution],
        ownerStoragePath: String? = nil
    ) {
        self.tree = tree
        self.bindings = bindings
        self.ownerStoragePath = ownerStoragePath
    }

    private enum CodingKeys: String, CodingKey {
        case tree, bindings, ownerStoragePath
    }

    /// Decodes a diagram response, handling the additive optional `ownerStoragePath`.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Decoding errors from the container.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tree = try c.decode(DiagramTree.self, forKey: .tree)
        bindings = try c.decode([DiagramBindingResolution].self, forKey: .bindings)
        // decodeIfPresent: a peer built before this field existed omits it.
        ownerStoragePath = try c.decodeIfPresent(String.self, forKey: .ownerStoragePath)
    }
}

/// Granular element verbs — each is a one-mutation batch over the SAME
/// store body as DIAGRAM_BATCH_APPLY, so granular and batch semantics
/// cannot drift.
///
/// Diagram-row updates (rename/promotion) ride batch-apply's diagramUpdate mutation.
struct DiagramNodeAddRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let add: DiagramElementAdd

    /// Creates a DIAGRAM_NODE_ADD request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - add: The element addition specification.
    init(diagramUuid: String, add: DiagramElementAdd) {
        self.diagramUuid = diagramUuid
        self.add = add
    }
}

struct DiagramNodeUpdateRequest: Codable, Hashable, Sendable {
    let update: DiagramElementUpdate

    /// Creates a DIAGRAM_NODE_UPDATE request.
    /// - Parameter update: The element update specification.
    init(update: DiagramElementUpdate) {
        self.update = update
    }
}

struct DiagramNodeDeleteRequest: Codable, Hashable, Sendable {
    let delete: DiagramElementDelete

    /// Creates a DIAGRAM_NODE_DELETE request.
    /// - Parameter delete: The element deletion specification.
    init(delete: DiagramElementDelete) {
        self.delete = delete
    }
}

/// Every mutation response carries diagramUuid + revision so clients update
/// without a refetch (the DopeNodeResponse contract).
struct DiagramNodeResponse: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let diagramUuid: String
    let revision: Int64

    /// Creates a DIAGRAM_NODE response.
    /// - Parameters:
    ///   - uuid: The element's unique identifier.
    ///   - version: The element's version number.
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's revision number after the mutation.
    init(uuid: String, version: Int64, diagramUuid: String, revision: Int64) {
        self.uuid = uuid
        self.version = version
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

struct DiagramNodeDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    /// Element rows removed, including the target itself.
    let cascadedElements: Int
    let diagramUuid: String
    let revision: Int64

    /// Creates a DIAGRAM_NODE_DELETE response.
    /// - Parameters:
    ///   - deletedUuid: The unique identifier of the deleted element.
    ///   - cascadedElements: The count of elements removed by cascading.
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's revision number after the deletion.
    init(deletedUuid: String, cascadedElements: Int, diagramUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascadedElements = cascadedElements
        self.diagramUuid = diagramUuid
        self.revision = revision
    }
}

/// THE interactive write: many typed mutations, one transaction, ONE
/// revision bump, ONE DIAGRAM_CHANGE event.
///
/// Mutations apply strictly in array order; elementAdd clientRefs are resolvable by later mutations in the same batch.
/// expectedRevision non-nil is a whole-diagram CAS gate (VERSION_CONFLICT on mismatch — gesture-end concurrency for
/// GMVibes).
struct DiagramBatchApplyRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let expectedRevision: Int64?
    let mutations: [DiagramMutation]

    /// Creates a DIAGRAM_BATCH_APPLY request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - mutations: The list of mutations to apply in order.
    ///   - expectedRevision: The expected diagram revision for CAS gating; nil skips the gate.
    init(diagramUuid: String, mutations: [DiagramMutation], expectedRevision: Int64? = nil) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
        self.mutations = mutations
    }
}

struct DiagramBatchApplyResponse: Codable, Hashable, Sendable {
    let diagramUuid: String
    let revision: Int64
    /// Index-aligned with the request's mutations array.
    let results: [DiagramMutationResult]

    /// Creates a DIAGRAM_BATCH_APPLY response.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - revision: The diagram's new revision after applying mutations.
    ///   - results: The results of each mutation, aligned with the request's mutations array.
    init(diagramUuid: String, revision: Int64, results: [DiagramMutationResult]) {
        self.diagramUuid = diagramUuid
        self.revision = revision
        self.results = results
    }
}

// MARK: - Diagram Studio (v23)

/// DIAGRAM_SEARCH — the cross-tier browse AND search surface backing the
/// GMVibes galleries.
///
/// A SEPARATE message from DIAGRAM_LIST, whose single-owner no-union picker contract it must not disturb. Two modes in
/// one message: a nil/empty `query` is a plain filtered SELECT of the project's diagrams across tiers ordered by
/// updated_at DESC (the gallery grid); a non-empty query is a bm25-ranked FTS5 MATCH over diagram_fts (the gallery
/// search box). `sessionUuid` narrows to one session's SESSION+PROMPT rows; `visibility` filters the axis.
struct DiagramSearchRequest: Codable, Hashable, Sendable {
    let projectUuid: String
    let sessionUuid: String?
    let query: String?
    let visibility: String?
    let limit: Int?

    /// Creates a DIAGRAM_SEARCH request.
    /// - Parameters:
    ///   - projectUuid: The project's unique identifier.
    ///   - sessionUuid: The session to narrow to; nil searches all sessions.
    ///   - query: The search query; nil or empty shows all diagrams sorted by updated_at DESC.
    ///   - visibility: Filter by visibility axis; nil shows all.
    ///   - limit: Maximum diagrams to return; nil uses default.
    init(
        projectUuid: String,
        sessionUuid: String? = nil,
        query: String? = nil,
        visibility: String? = nil,
        limit: Int? = nil
    ) {
        self.projectUuid = projectUuid
        self.sessionUuid = sessionUuid
        self.query = query
        self.visibility = visibility
        self.limit = limit
    }
}

/// Rows in rank order (bm25 when a query ran, updated_at DESC otherwise).
///
/// DiagramRow already carries tier/visibility/owner uuids/revision — the whole card surface — so hits are plain rows,
/// not a parallel shape.
struct DiagramSearchResponse: Codable, Hashable, Sendable {
    let diagrams: [DiagramRow]

    /// Creates a DIAGRAM_SEARCH response.
    /// - Parameter diagrams: The diagram rows matching the search, in rank order.
    init(diagrams: [DiagramRow]) {
        self.diagrams = diagrams
    }
}

/// DIAGRAM_DELETE — row delete with an optional whole-diagram CAS gate.
///
/// Elements and subtype rows cascade via FKs, the FTS mirror via its delete trigger, and prompt-qualified readings via
/// m0022's CASCADE. A durable DIAGRAM_CHANGE (action "deleted") is recorded BEFORE the row drops so live
/// galleries/editors close cleanly. Screenshot cleanup is the CLIENT's (gmfs is gm territory, exactly like rendering).
struct DiagramDeleteRequest: Codable, Hashable, Sendable {
    let diagramUuid: String
    let expectedRevision: Int64?

    /// Creates a DIAGRAM_DELETE request.
    /// - Parameters:
    ///   - diagramUuid: The diagram's unique identifier.
    ///   - expectedRevision: The expected diagram revision for CAS gating; nil skips the gate.
    init(diagramUuid: String, expectedRevision: Int64? = nil) {
        self.diagramUuid = diagramUuid
        self.expectedRevision = expectedRevision
    }
}

struct DiagramDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let code: String
    /// Element rows removed with the diagram.
    let cascadedElements: Int
    /// The owner storage path a screenshot may exist under (client cleanup).
    let ownerStoragePath: String?
    /// The row's screenshot directory override — the client must clean the
    /// SAME path gm render wrote, not a guessed default.
    let gmccDiagramPath: String?

    /// Creates a DIAGRAM_DELETE response.
    /// - Parameters:
    ///   - deletedUuid: The unique identifier of the deleted diagram.
    ///   - code: The deletion response code.
    ///   - cascadedElements: The count of element rows removed with the diagram.
    ///   - ownerStoragePath: The owner storage path for client screenshot cleanup; nil if not applicable.
    ///   - gmccDiagramPath: The diagram path override for client screenshot cleanup; nil if not applicable.
    init(
        deletedUuid: String,
        code: String,
        cascadedElements: Int,
        ownerStoragePath: String? = nil,
        gmccDiagramPath: String? = nil
    ) {
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
/// applied verbatim).
///
/// Explicit only: setting PUBLIC never writes files.
struct DiagramWriteRepoRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    /// Overwrite files stamped AHEAD of the db (the dope --force contract).
    let force: Bool

    /// Creates a DIAGRAM_WRITE_REPO request.
    /// - Parameters:
    ///   - sessionUuid: The session's unique identifier.
    ///   - force: Whether to overwrite files stamped ahead of the db; defaults to false.
    init(sessionUuid: String, force: Bool = false) {
        self.sessionUuid = sessionUuid
        self.force = force
    }
}

struct DiagramWriteRepoResponse: Codable, Hashable, Sendable {
    /// Diagram codes written this pass.
    let written: [String]
    /// Files pruned because their diagram was demoted or deleted.
    let pruned: [String]
    /// The absolute .gmcc/diagrams directory written under.
    let root: String

    /// Creates a DIAGRAM_WRITE_REPO response.
    /// - Parameters:
    ///   - written: The diagram codes written this pass.
    ///   - pruned: The diagram codes pruned due to demotion or deletion.
    ///   - root: The absolute .gmcc/diagrams directory written under.
    init(written: [String], pruned: [String], root: String) {
        self.written = written
        self.pruned = pruned
        self.root = root
    }
}

/// DIAGRAM_INGEST — files→db, strictly forward-only (the dope ingest gate):
/// a file version must be STRICTLY greater than the db revision to land.
///
/// Code-keyed upsert into the calling session's SESSION tier as PUBLIC; connector code-path targets re-resolve,
/// unresolvable → ghost.
struct DiagramIngestRequest: Codable, Hashable, Sendable {
    let sessionUuid: String

    /// Creates a DIAGRAM_INGEST request.
    /// - Parameter sessionUuid: The session's unique identifier.
    init(sessionUuid: String) {
        self.sessionUuid = sessionUuid
    }
}

struct DiagramIngestResponse: Codable, Hashable, Sendable {
    /// Codes created or updated from files.
    let ingested: [String]
    /// Codes skipped (db at or ahead of the file, or a PRIVATE collision).
    let skipped: [String]
    /// Per-file problems (corrupt JSON, name/code mismatch, refused
    /// content).
    ///
    /// One bad file must never abort the family's sync — and the boot path must have something to PRINT, or the failure
    /// is silent.
    let warnings: [String]
    /// The absolute .gmcc/diagrams directory read from.
    let root: String

    /// Creates a DIAGRAM_INGEST response.
    /// - Parameters:
    ///   - ingested: The diagram codes created or updated from files.
    ///   - skipped: The diagram codes skipped (db ahead of file or collision).
    ///   - root: The absolute .gmcc/diagrams directory read from.
    ///   - warnings: Per-file problems encountered during ingest; defaults to empty.
    init(
        ingested: [String],
        skipped: [String],
        root: String,
        warnings: [String] = []
    ) {
        self.ingested = ingested
        self.skipped = skipped
        self.warnings = warnings
        self.root = root
    }
}

// MARK: - Dope merge / resolve

/// DOPE_MERGE_PLAN — the per-element boundary plan for one scope.
///
/// Read-only.
struct DopeMergePlanRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// Creates a DOPE_MERGE_PLAN request.
    /// - Parameter scopeUuid: The scope's unique identifier.
    init(scopeUuid: String) { self.scopeUuid = scopeUuid }
}

struct DopeMergeOutcomeRow: Codable, Hashable, Sendable {
    let dotPath: String
    let kind: String
    let decision: String
    /// Creates a merge outcome row for one boundary.
    /// - Parameters:
    ///   - dotPath: The dotted path of the element.
    ///   - kind: The element kind.
    ///   - decision: The merge decision for this element.
    init(dotPath: String, kind: String, decision: String) {
        self.dotPath = dotPath
        self.kind = kind
        self.decision = decision
    }
}

struct DopeMergePlanResponse: Codable, Hashable, Sendable {
    let outcomes: [DopeMergeOutcomeRow]
    let conflictCount: Int
    /// Creates a DOPE_MERGE_PLAN response.
    /// - Parameters:
    ///   - outcomes: The merge outcome rows for each boundary element.
    ///   - conflictCount: The count of conflicting dot-paths.
    init(outcomes: [DopeMergeOutcomeRow], conflictCount: Int) {
        self.outcomes = outcomes
        self.conflictCount = conflictCount
    }
}

/// DOPE_RESOLVE — settle conflicting dot-paths in one direction.
struct DopeResolveRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// nil = every unresolved conflict.
    let dotPath: String?
    /// true keeps the db side, false takes the file side.
    let takeOurs: Bool
    /// Creates a DOPE_RESOLVE request.
    /// - Parameters:
    ///   - scopeUuid: The scope's unique identifier.
    ///   - takeOurs: True keeps the db side, false takes the file side.
    ///   - dotPath: The specific dot-path to resolve; nil resolves all unresolved conflicts.
    init(scopeUuid: String, takeOurs: Bool, dotPath: String? = nil) {
        self.scopeUuid = scopeUuid
        self.dotPath = dotPath
        self.takeOurs = takeOurs
    }
}

struct DopeResolveResponse: Codable, Hashable, Sendable {
    let resolved: [String]
    let takeOurs: Bool
    /// Creates a DOPE_RESOLVE response.
    /// - Parameters:
    ///   - resolved: The dot-paths that were resolved.
    ///   - takeOurs: True if the db side was kept, false if the file side was taken.
    init(resolved: [String], takeOurs: Bool) {
        self.resolved = resolved
        self.takeOurs = takeOurs
    }
}

// MARK: - Pen result budget (the generic oversize guard)

/// Excerpting policy shared by every stub in this file.
///
/// One constant, so a stub is the same size wherever it comes from.
enum CdeExcerpt {
    /// Long enough to recognize what a body is about; short enough that a
    /// hundred stubs still fit inside the result budget below.
    static let chars = 400

    /// Excerpt a body to a character limit.
    ///
    /// Character-based, never byte-based: an excerpt is shown to a reader, and clipping a grapheme in half would put
    /// mojibake in the record.
    /// - Parameters:
    ///   - body: The string to excerpt.
    ///   - limit: The character limit; defaults to `CdeExcerpt.chars`.
    /// - Returns: The excerpt text, true length in characters, and whether anything was dropped.
    static func take(
        _ body: String,
        chars limit: Int = CdeExcerpt.chars
    )
        -> (excerpt: String, chars: Int, truncated: Bool)
    {
        let total = body.count
        guard total > limit else { return (body, total, false) }
        return (String(body.prefix(limit)), total, true)
    }
}

/// What a pen read tool can be told to make itself smaller.
///
/// Data, not prose, so the guard below can quote it back to the caller in a form the caller can act on without reading
/// English.
struct CdeNarrowing: Codable, Hashable, Sendable {
    /// The tool's own argument names, in the order worth trying.
    let parameters: [String]
    /// The exact next call to make.
    let retryWith: String

    /// Creates a narrowing hint for an oversized result.
    /// - Parameters:
    ///   - `parameters`: The tool's argument names in suggested narrowing order.
    ///   - `retryWith`: The exact next call to make to narrow the result.
    init(parameters: [String], retryWith: String) {
        self.parameters = parameters
        self.retryWith = retryWith
    }
}

/// The machine-readable header stamped on an over-budget result.
///
/// NEVER a prose apology and NEVER a clipped JSON body: the failure mode being fixed is a caller hand-parsing truncated
/// JSON, so an over-budget read returns a well-formed envelope that names the parameter which narrows THIS tool.
struct CdeOversizeNote: Codable, Hashable, Sendable {
    let tool: String
    /// "degraded" = a narrowed payload rides along under `result`.
    /// "withheld" = even the narrowed form did not fit; there is no payload.
    /// "completed_degraded" / "completed_withheld" are the same two
    /// outcomes for a WRITE, and the prefix is load-bearing: the write landed,
    /// so the caller must read the result back rather than retry the call.
    let outcome: String
    /// Size of the response the tool actually produced.
    let bytes: Int
    /// Size of what is being returned instead (nil when withheld).
    let degradedBytes: Int?
    let budgetBytes: Int
    let parameters: [String]
    let retryWith: String

    /// Creates an oversize result note.
    /// - Parameters:
    ///   - `tool`: The tool that produced the oversized result.
    ///   - `outcome`: The outcome status: "degraded", "withheld", or completed variants.
    ///   - `bytes`: The actual byte count of the result produced.
    ///   - `degradedBytes`: The byte count of the degraded result; nil if withheld.
    ///   - `budgetBytes`: The maximum allowed byte count.
    ///   - `parameters`: The tool's narrowing parameter names.
    ///   - `retryWith`: The exact next call to make to narrow the result.
    init(
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

/// THE GENERIC RESPONSE-SIZE GUARD.
///
/// Pen reads pass here before harness sees: over-budget result refused whole,
/// reader gets body cut mid-array with no note. `maxBytes` = 45,000 (measured).
/// 79,598-char result refused; against harness's 25,000-token ceiling, 2.5
/// bytes/token for JSON, 45K bytes ≈ 18K tokens with envelope headroom.
enum CdeResultBudget {
    static let maxBytes = 45_000
    /// The page budget the cde server hands `CdePager` by default.
    ///
    /// 15 KB under `maxBytes` is the room for the envelope, the fixed parts of a page and pretty-print inflation, all
    /// measured on the same encoder.
    static let pageBytes = 30_000

    /// Creates a JSON encoder with pretty-printing and sorted keys.
    /// - Returns: A JSONEncoder configured for the CDE budget.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Render a tool result under the budget.
    ///
    /// 1. Fits → the payload verbatim.
    /// 2. Over → the `withheld` note ALONE. A caller that gets no `result`
    ///    key knows it got no data, which is a fact it can act on; a truncated
    ///    body is a fact it cannot. Every read is paged by `CdePager` before
    ///    it reaches here, so this branch is a last resort, not a plan.
    /// - Parameters:
    ///   - tool: The name of the tool producing the result.
    ///   - narrowing: Narrowing options for an oversized result; nil if not applicable.
    ///   - value: The value to encode and render.
    ///   - isWrite: True if this is a write result; defaults to false.
    /// - Returns: The rendered JSON string, either the full result or an oversize note.
    /// - Throws: Encoding errors from the encoder.
    static func render(
        tool: String,
        narrowing: CdeNarrowing?,
        value: any Encodable,
        isWrite: Bool = false
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
            retryWith =
                "the write COMPLETED and is recorded — do NOT retry it, "
                + "these verbs append and a second call writes a second row. "
                + "Read the result back with \(readBack)."
        } else {
            retryWith =
                narrowing?.retryWith
                ?? "this tool has no narrowing parameter — its result is one indivisible record; read it through a different tool or a narrower subject"
        }
        func stamp(_ base: String) -> String { isWrite ? "completed_\(base)" : base }

        let note = CdeOversizeNote(
            tool: tool,
            outcome: stamp("withheld"),
            bytes: data.count,
            degradedBytes: nil,
            budgetBytes: maxBytes,
            parameters: parameters,
            retryWith: retryWith
        )
        return try envelope(note: note, payload: nil, encoder: encoder)
    }

    /// Compose note + optional payload into ONE well-formed JSON document.
    ///
    /// The payload is spliced as already-encoded bytes rather than re-encoded
    /// through JSONSerialization, so nothing in it can be reshaped on the way
    /// out.
    /// - Parameters:
    ///   - note: The oversize note to include in the envelope.
    ///   - payload: The optional encoded result payload as bytes.
    ///   - encoder: The JSON encoder to use for encoding the note.
    /// - Returns: A well-formed JSON string containing the note and optional payload.
    /// - Throws: Encoding errors from the encoder.
    static func envelope(
        note: CdeOversizeNote,
        payload: Data?,
        encoder: JSONEncoder
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

    /// Creates a type-erasing wrapper for an Encodable value.
    /// - Parameter wrapped: The value to erase and wrap.
    init(_ wrapped: any Encodable) {
        encodeTo = { encoder in try wrapped.encode(to: encoder) }
    }

    /// Encodes the wrapped value using the given encoder.
    /// - Parameter encoder: The encoder to use for encoding.
    /// - Throws: Encoding errors from the wrapped value's encode method.
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}

// MARK: - Agent test mutual exclusion (v29)

/// Run lifecycle.
///
/// Lives here rather than as a SQL `CHECK` because post-m0021 the vocabulary is Swift's job: an inline CHECK cannot be
/// dropped without the documented twelve-step table rebuild, so encoding five arms in the schema buys a rebuild the
/// first time a sixth is wanted.
enum TestRunState: String, Codable, Hashable, CaseIterable, Sendable {
    case queued
    case running
    case passed
    case failed
    /// The holder died or released without reporting. Distinct from `failed`
    /// on purpose — "we never found out" is not "it went red", and collapsing
    /// them would let a crashed run masquerade as a real result.
    case abandoned
}

/// How a caller can tell the run finished.
///
/// The MACHINE-checkable half; the human sentence is `doneHint`.
enum TestDoneKind: String, Codable, Hashable, CaseIterable, Sendable {
    /// A file appears at `done_condition.path`.
    case exitFile = "exit_file"
    /// The `test_run` row itself reaches a terminal state.
    case dbRow = "db_row"
    /// The supervised process exits (`exitCode` becomes non-nil).
    case process
}

/// The claim cell's two states.
///
/// The ask spelled the release edge explicitly — a run holds its target "until it is modified back into an open state".
enum TestLockState: String, Codable, Hashable, CaseIterable, Sendable {
    case open
    case held
}

/// How liveness is decided for the current holder.
enum TestHolderKind: String, Codable, Hashable, CaseIterable, Sendable {
    /// DEFAULT, and the one that makes the lock safe. Liveness is a
    /// `flock(LOCK_NB)` probe on `lockPath`: if the probe succeeds the holder
    /// is gone, full stop. Authority is DERIVED from a won lock exactly as
    /// `KernelOwnership` derives it, so SIGKILLing a holder frees the lock at
    /// the next status call with no timeout, no reaper and nothing to tune.
    case process
    /// Degraded fallback for a holder that cannot keep a file descriptor open.
    /// Uses `expiresAt`, which is strictly worse: a TTL fails toward HOLDING a
    /// stuck lock, and for a mutex that is the worst available direction.
    case lease
}

/// One runnable suite, declared in the REPO rather than the database — the ask
/// was that repo tests be configured in the repo, and a manifest that travels
/// with the checkout is the only version of that which survives cloning the
/// repo into another environment.
struct TestSuiteSpec: Codable, Hashable, Sendable {
    let id: String
    let command: String
    let doneKind: TestDoneKind
    let doneHint: String?

    /// Creates a test run specification.
    /// - Parameters:
    ///   - id: The test specification identifier.
    ///   - command: The command to run.
    ///   - doneKind: The type of completion indicator.
    ///   - doneHint: An optional human-readable hint for completion; defaults to nil.
    init(id: String, command: String, doneKind: TestDoneKind, doneHint: String? = nil) {
        self.id = id
        self.command = command
        self.doneKind = doneKind
        self.doneHint = doneHint
    }
}

struct TestSuiteListRequest: Codable, Hashable, Sendable {
    let projectUuid: String

    /// Creates a TEST_SUITE_LIST request.
    /// - Parameter projectUuid: The project's unique identifier.
    init(projectUuid: String) {
        self.projectUuid = projectUuid
    }
}

struct TestSuiteListResponse: Codable, Hashable, Sendable {
    let suites: [TestSuiteSpec]
    /// Where the manifest was read from, so a caller that got an empty list can
    /// tell "no suites declared" from "looked in the wrong checkout".
    let manifestPath: String?

    /// Creates a TEST_SUITE_LIST response.
    /// - Parameters:
    ///   - suites: The list of test suite specifications.
    ///   - manifestPath: The path the manifest was read from; nil if not available.
    init(suites: [TestSuiteSpec], manifestPath: String? = nil) {
        self.suites = suites
        self.manifestPath = manifestPath
    }
}

struct TestLockStatusRequest: Codable, Hashable, Sendable {
    let projectUuid: String

    /// Creates a TEST_LOCK_STATUS request.
    /// - Parameter projectUuid: The project's unique identifier.
    init(projectUuid: String) {
        self.projectUuid = projectUuid
    }
}

struct TestLockAcquireRequest: Codable, Hashable, Sendable {
    let projectUuid: String
    /// The checkout being claimed — the ask's "targets an instance".
    let targetInstanceUuid: String?
    let sessionUuid: String?
    let agentId: String?
    let suiteId: String
    /// The ephemeral root this run owns.
    ///
    /// HARD CONSTRAINT on whatever generates it: `sun_path` is 104 bytes on
    /// macOS and the server binds `NWEndpoint.unix(path:)` under this root, so
    /// a long root yields a listener that cannot bind. Keep run ids SHORT.
    let runRoot: String
    /// The file the holder `flock`s.
    ///
    /// Absent means lease mode, which is the degraded path — see `TestHolderKind`.
    let lockPath: String?
    let holderPid: Int32?
    let gitSha: String?
    let gitBranch: String?
    let doneKind: TestDoneKind
    /// JSON keyed by `doneKind` (e.g. `{"path": "…/result.json"}`).
    ///
    /// JSON rather than columns because the shape varies per kind and none of it is queried.
    let doneCondition: String
    /// The human sentence another agent reads to decide whether to wait.
    ///
    /// The ask's "a description of how to tell when the test is done running" — deliberately free text, because it is
    /// documentation for a reader rather than a predicate for the machine.
    let doneHint: String?
    /// Lease mode only.
    ///
    /// Ignored when a `lockPath` is given.
    let leaseSeconds: Int?

    /// Creates a TEST_LOCK_ACQUIRE request.
    /// - Parameters:
    ///   - projectUuid: The project's unique identifier.
    ///   - suiteId: The test suite identifier.
    ///   - runRoot: The ephemeral root this run owns; must be short for sun_path.
    ///   - doneKind: The type of completion indicator.
    ///   - doneCondition: JSON keyed by doneKind describing when the test is done.
    ///   - targetInstanceUuid: The checkout being claimed; nil if not specified.
    ///   - sessionUuid: The session UUID; nil if not specified.
    ///   - agentId: The agent ID; nil if not specified.
    ///   - lockPath: The file to flock; nil uses lease mode.
    ///   - holderPid: The holder's process ID; nil if not specified.
    ///   - gitSha: The git commit SHA; nil if not specified.
    ///   - gitBranch: The git branch; nil if not specified.
    ///   - doneHint: Human-readable description of completion; nil if not specified.
    ///   - leaseSeconds: Lease duration for lease mode; nil if using lockPath.
    init(
        projectUuid: String,
        suiteId: String,
        runRoot: String,
        doneKind: TestDoneKind,
        doneCondition: String,
        targetInstanceUuid: String? = nil,
        sessionUuid: String? = nil,
        agentId: String? = nil,
        lockPath: String? = nil,
        holderPid: Int32? = nil,
        gitSha: String? = nil,
        gitBranch: String? = nil,
        doneHint: String? = nil,
        leaseSeconds: Int? = nil
    ) {
        self.projectUuid = projectUuid
        self.targetInstanceUuid = targetInstanceUuid
        self.sessionUuid = sessionUuid
        self.agentId = agentId
        self.suiteId = suiteId
        self.runRoot = runRoot
        self.lockPath = lockPath
        self.holderPid = holderPid
        self.gitSha = gitSha
        self.gitBranch = gitBranch
        self.doneKind = doneKind
        self.doneCondition = doneCondition
        self.doneHint = doneHint
        self.leaseSeconds = leaseSeconds
    }
}

struct TestLockReleaseRequest: Codable, Hashable, Sendable {
    let projectUuid: String
    /// The run releasing.
    ///
    /// Required: releasing a lock you do not hold is the mistake worth refusing, and without this the verb cannot tell.
    let runUuid: String
    /// Terminal state to stamp on the run as it lets go.
    let finalState: TestRunState
    let exitCode: Int32?
    let summary: String?
    /// Break a lock held by someone else.
    ///
    /// AUDITED — it events like any other transition, so a forced release is visible afterwards rather than
    /// indistinguishable from a clean one.
    let force: Bool

    /// Creates a TEST_LOCK_RELEASE request.
    /// - Parameters:
    ///   - projectUuid: The project's unique identifier.
    ///   - runUuid: The run releasing the lock.
    ///   - finalState: Terminal state to stamp on the run.
    ///   - exitCode: The run's exit code; nil if not specified.
    ///   - summary: Summary of the run; nil if not specified.
    ///   - force: Whether to break a lock held by someone else; defaults to false.
    init(
        projectUuid: String,
        runUuid: String,
        finalState: TestRunState,
        exitCode: Int32? = nil,
        summary: String? = nil,
        force: Bool = false
    ) {
        self.projectUuid = projectUuid
        self.runUuid = runUuid
        self.finalState = finalState
        self.exitCode = exitCode
        self.summary = summary
        self.force = force
    }
}

struct TestLockResponse: Codable, Hashable, Sendable {
    let projectUuid: String
    let state: TestLockState
    let heldByRunUuid: String?
    let targetInstanceUuid: String?
    let holderKind: TestHolderKind?
    let lockPath: String?
    let holderPid: Int32?
    let claimedAt: String?
    let expiresAt: String?
    let version: Int64
    /// The run currently holding, inlined so a waiting agent gets `doneHint`
    /// and `doneCondition` without a second round trip — the whole point of
    /// asking is "can I go yet", and that answer lives on the run.
    let run: TestRunSummary?
    /// True when this call RECLAIMED a lock whose holder was gone.
    ///
    /// Surfaced rather than silent: a caller that believes it queued cleanly should be able to see that it actually
    /// stepped over a corpse.
    let reclaimed: Bool

    /// Creates a TEST_LOCK response.
    /// - Parameters:
    ///   - projectUuid: The project's unique identifier.
    ///   - state: The current lock state.
    ///   - version: The lock version.
    ///   - heldByRunUuid: The run UUID holding the lock; nil if not held.
    ///   - targetInstanceUuid: The target instance UUID; nil if not specified.
    ///   - holderKind: The holder kind; nil if not applicable.
    ///   - lockPath: The lock file path; nil if using lease mode.
    ///   - holderPid: The holder's process ID; nil if not available.
    ///   - claimedAt: When the lock was claimed; nil if not specified.
    ///   - expiresAt: When the lock expires; nil if not specified.
    ///   - run: The run holding the lock, inlined for agents; nil if not available.
    ///   - reclaimed: True when this call reclaimed a lock whose holder was gone.
    init(
        projectUuid: String,
        state: TestLockState,
        version: Int64,
        heldByRunUuid: String? = nil,
        targetInstanceUuid: String? = nil,
        holderKind: TestHolderKind? = nil,
        lockPath: String? = nil,
        holderPid: Int32? = nil,
        claimedAt: String? = nil,
        expiresAt: String? = nil,
        run: TestRunSummary? = nil,
        reclaimed: Bool = false
    ) {
        self.projectUuid = projectUuid
        self.state = state
        self.heldByRunUuid = heldByRunUuid
        self.targetInstanceUuid = targetInstanceUuid
        self.holderKind = holderKind
        self.lockPath = lockPath
        self.holderPid = holderPid
        self.claimedAt = claimedAt
        self.expiresAt = expiresAt
        self.version = version
        self.run = run
        self.reclaimed = reclaimed
    }
}

/// The append-only ledger row, as the wire sees it.
struct TestRunSummary: Codable, Hashable, Sendable {
    let uuid: String
    let projectUuid: String
    let instanceUuid: String?
    let sessionUuid: String?
    let agentId: String?
    let runRoot: String
    let suiteId: String
    let gitSha: String?
    let gitBranch: String?
    let state: TestRunState
    let doneKind: TestDoneKind
    let doneCondition: String
    let doneHint: String?
    let startedAt: String?
    let finishedAt: String?
    let exitCode: Int32?
    let summary: String?
    let createdAt: String
    let updatedAt: String
    let version: Int64

    /// Creates a test run summary.
    /// - Parameters:
    ///   - uuid: The run's unique identifier.
    ///   - projectUuid: The project's unique identifier.
    ///   - runRoot: The ephemeral root this run owns.
    ///   - suiteId: The test suite identifier.
    ///   - state: The run's current state.
    ///   - doneKind: The type of completion indicator.
    ///   - doneCondition: JSON describing when the test is done.
    ///   - createdAt: When the run was created.
    ///   - updatedAt: When the run was last updated.
    ///   - version: The run's version number.
    ///   - instanceUuid: The instance UUID; nil if not specified.
    ///   - sessionUuid: The session UUID; nil if not specified.
    ///   - agentId: The agent ID; nil if not specified.
    ///   - gitSha: The git commit SHA; nil if not specified.
    ///   - gitBranch: The git branch; nil if not specified.
    ///   - doneHint: Human-readable completion hint; nil if not specified.
    ///   - startedAt: When the run started; nil if not started.
    ///   - finishedAt: When the run finished; nil if not finished.
    ///   - exitCode: The exit code; nil if not specified.
    ///   - summary: Summary text; nil if not specified.
    init(
        uuid: String,
        projectUuid: String,
        runRoot: String,
        suiteId: String,
        state: TestRunState,
        doneKind: TestDoneKind,
        doneCondition: String,
        createdAt: String,
        updatedAt: String,
        version: Int64,
        instanceUuid: String? = nil,
        sessionUuid: String? = nil,
        agentId: String? = nil,
        gitSha: String? = nil,
        gitBranch: String? = nil,
        doneHint: String? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        exitCode: Int32? = nil,
        summary: String? = nil
    ) {
        self.uuid = uuid
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.agentId = agentId
        self.runRoot = runRoot
        self.suiteId = suiteId
        self.gitSha = gitSha
        self.gitBranch = gitBranch
        self.state = state
        self.doneKind = doneKind
        self.doneCondition = doneCondition
        self.doneHint = doneHint
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}

/// Mark a claimed run as actually started.
///
/// Split from acquire because claiming the lock and beginning to run are genuinely different moments, and a run that
/// was claimed but never started is a state worth being able to see.
struct TestRunStartRequest: Codable, Hashable, Sendable {
    let runUuid: String
    let expectedVersion: Int64

    /// Creates a TEST_RUN_START request.
    /// - Parameters:
    ///   - runUuid: The run's unique identifier.
    ///   - expectedVersion: The expected run version for CAS gating.
    init(runUuid: String, expectedVersion: Int64) {
        self.runUuid = runUuid
        self.expectedVersion = expectedVersion
    }
}

struct TestRunStatusRequest: Codable, Hashable, Sendable {
    /// One run by uuid, or — when nil — the recent runs for `projectUuid`.
    let runUuid: String?
    let projectUuid: String?
    let limit: Int?

    /// Creates a TEST_RUN_STATUS request.
    /// - Parameters:
    ///   - runUuid: The run's unique identifier for a specific run; nil to query by project.
    ///   - projectUuid: The project's unique identifier for recent runs; nil if querying a specific run.
    ///   - limit: Maximum runs to return; nil for default.
    init(runUuid: String? = nil, projectUuid: String? = nil, limit: Int? = nil) {
        self.runUuid = runUuid
        self.projectUuid = projectUuid
        self.limit = limit
    }
}

struct TestRunResponse: Codable, Hashable, Sendable {
    let runs: [TestRunSummary]

    /// Creates a TEST_RUN response.
    /// - Parameter runs: The test run summaries.
    init(runs: [TestRunSummary]) {
        self.runs = runs
    }
}

// MARK: - The harness envelope (v30)

/// The identity a harness-side caller must supply, because the kernel cannot
/// derive it. THIS STRUCT IS WHY THE HARNESS CHILD PROCESS EXISTS:
/// 1. `ClientKey.resolve()` walks process ancestry for a `claude` parent, and
///    that string IS the activation-claim key. A kernel is no such descendant,
///    so it resolves nil and the registry degrades to last-writer-wins.
/// 2. `main()` chdirs to `$CLAUDE_PROJECT_DIR` so `GitContext.detect()` finds
///    the right repo, and one long-lived process cannot hold N cwds.
/// 3. MCP stdio transport is per-server-process.

/// The child is therefore THIN: it resolves the triple once at startup and
/// forwards it. `clientKey` is resolved BEFORE any chdir and cached, since
/// ancestry cannot change for a live process. `cwd` is read AFTER the chdir.
struct GmHarnessIdentity: Codable, Hashable, Sendable {
    /// `claude:<pid>:<starttime>`, resolved by the child from ITS ancestry.
    ///
    /// Optional, and the nil case DEGRADES rather than refuses. A refusal here
    /// is a dead pen, and the pen is the repair tool — the one thing a user
    /// reaches for when the machine is already broken. The kernel logs one line
    /// and proceeds unclaimed.
    let clientKey: String?
    /// The child's working directory, read after it chdirs to the project dir.
    let cwd: String?
    /// `$CLAUDE_PROJECT_DIR` as the harness reported it.
    let projectDir: String?

    /// Creates a harness identity.
    /// - Parameters:
    ///   - clientKey: The activation-claim key; nil if not available.
    ///   - cwd: The harness child's working directory; nil if not available.
    ///   - projectDir: The project directory as reported by the harness; nil if not available.
    init(clientKey: String? = nil, cwd: String? = nil, projectDir: String? = nil) {
        self.clientKey = clientKey
        self.cwd = cwd
        self.projectDir = projectDir
    }
}

/// `MCP_CALL` — one MCP `tools/call`, relayed to the kernel.
///
/// `arguments` stays an untyped `GmJsonValue` for the same reason `TX_BATCH`
/// keeps its inner lines opaque: this verb needs no knowledge of the tool
/// schemas it can carry, and teaching it would make every roster change a wire
/// change.
struct McpCallRequest: Codable, Hashable, Sendable {
    /// The tool name as the harness spelled it, UNQUALIFIED — `cde_rpir_explore`
    /// and its `op`, never the plugin-namespaced form `CdeToolSpec.qualifiedName`
    /// builds.
    let tool: String
    let arguments: GmJsonValue?
    let identity: GmHarnessIdentity

    /// Creates an MCP_CALL request.
    /// - Parameters:
    ///   - tool: The unqualified tool name as spelled by the harness.
    ///   - identity: The harness identity.
    ///   - arguments: The tool arguments as a GmJsonValue; nil if not provided.
    init(tool: String, identity: GmHarnessIdentity, arguments: GmJsonValue? = nil) {
        self.tool = tool
        self.arguments = arguments
        self.identity = identity
    }
}

/// Result of an `MCP_CALL`.
///
/// RENDERED TEXT, NOT A STRUCTURED RESULT, and that is deliberate. Rendering
/// lives kernel-side with the tool bodies so `CdeResultBudget`'s per-tool
/// narrowing and degrade paths apply to the bytes that actually go back. If the
/// child rendered, the budget and the renderer would be in two processes and
/// free to drift — and the failure mode of that drift is a result that blows the
/// harness limit, which is exactly what the budget exists to prevent.
struct McpCallResponse: Codable, Hashable, Sendable {
    /// The rendered tool result, already budget-checked.
    ///
    /// THERE IS NO SEPARATE `budget` FIELD, and its absence is deliberate.
    /// `CdeResultBudget.render` returns the `gmcc_oversize` ENVELOPE on an
    /// over-budget result, which already carries both the note and the narrowed
    /// payload under `result`. A sibling field would duplicate this string or
    /// sit permanently nil, and a field nothing populates is a claim the wire
    /// does not honour.
    let text: String
    /// A tool-level failure.
    ///
    /// Rides the RESULT envelope rather than the protocol error, matching what the MCP server already does: a tool that
    /// fails is not a malformed request, and an MCP client is built to read the difference.
    let isError: Bool

    /// Creates an MCP_CALL response.
    /// - Parameters:
    ///   - text: The rendered tool result, already budget-checked.
    ///   - isError: True if this is a tool-level failure; defaults to false.
    init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

/// `HOOK_EVENT` — one Claude Code lifecycle hook, relayed to the kernel.
///
/// Logic compiles into kernel, takes cwd from payload not process; verb moves
/// CALL SITE, not logic. LAUNCHER STAYS SHELL-FORM `command` HOOK: `SessionStart`
/// accepts `command` and `mcp_tool` only; handler expects "not connected" error
/// on first run; shell form alone resolves `${GM_FS_ROOT:-$HOME/gmfs}` and
/// honours exit-0 no-op.
struct HookEventRequest: Codable, Hashable, Sendable {
    /// The lifecycle event name as the harness spells it (`PostToolUse`,
    /// `SessionStart`, `SubagentStart`, …).
    ///
    /// A raw string rather than an enum: the harness owns this vocabulary and
    /// adds to it, and an unknown event must be a recorded no-op here, never a
    /// decode failure that fails a hook.
    let event: String
    let payload: GmJsonValue?
    let identity: GmHarnessIdentity
    /// When true the daemon returns `ok` for a BUSINESS failure and reports the
    /// problem in `note` instead of throwing.
    ///
    /// A WIRE FIELD, NOT A CLIENT CONVENTION. A hook may never exit non-zero,
    /// since a non-zero PostToolUse is a blocked tool call. Putting the contract
    /// in the message means a caller cannot forget it. Transport-level failures
    /// still fail: a malformed envelope is not a business failure.
    let hookSafe: Bool

    /// Creates a HOOK_EVENT request.
    /// - Parameters:
    ///   - event: The lifecycle event name as spelled by the harness.
    ///   - identity: The harness identity.
    ///   - payload: Optional event payload as a GmJsonValue.
    ///   - hookSafe: Whether the daemon returns ok for business failures; defaults to true.
    init(event: String, identity: GmHarnessIdentity, payload: GmJsonValue? = nil, hookSafe: Bool = true) {
        self.event = event
        self.payload = payload
        self.identity = identity
        self.hookSafe = hookSafe
    }
}

/// Result of a `HOOK_EVENT`.
struct HookEventResponse: Codable, Hashable, Sendable {
    /// Whether the event produced a recorded write.
    let recorded: Bool
    /// Human-readable outcome.
    ///
    /// Under `hookSafe` this is where a suppressed business failure is reported,
    /// so a swallowed error is still SAID somewhere rather than vanishing.
    let note: String?
    /// Text the harness should inject as additional context, for the events that
    /// honour it (`SessionStart` provisioning being the one that matters).
    let additionalContext: String?

    /// Creates a HOOK_EVENT response.
    /// - Parameters:
    ///   - recorded: Whether the event produced a recorded write.
    ///   - note: Human-readable outcome; nil if not specified.
    ///   - additionalContext: Text for harness to inject; nil if not specified.
    init(recorded: Bool, note: String? = nil, additionalContext: String? = nil) {
        self.recorded = recorded
        self.note = note
        self.additionalContext = additionalContext
    }
}
