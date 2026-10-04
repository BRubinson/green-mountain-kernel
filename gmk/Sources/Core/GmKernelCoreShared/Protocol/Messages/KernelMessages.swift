import Foundation

// Kernel wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
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
enum KernelEventKind: String, Codable, Hashable, CaseIterable, Sendable {
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

/// What an exploration finding is about. `keyFile` is the merged
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

/// Per-agent exploration summary vocabulary.
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

    var eventKind: KernelEventKind? { KernelEventKind(rawValue: kind) }

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

// MARK: - PATHS_GET / CONFIG_SET

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

// MARK: - Agent test mutual exclusion

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

// MARK: - The harness envelope

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
