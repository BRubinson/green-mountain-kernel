import Foundation

// Typed read-side DTOs — the row shapes GMVibes and gm_hook render from.
// Same lowering conventions as Messages.swift.

// MARK: - Project

struct ProjectRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let gitRepoName: String
    let code: String
    let name: String
    let gmfsRelativeStoragePath: String
    /// BASE_DOPED_BRANCH — the branch whose SESSION_INSTANCE dope scope may
    /// promote into this project's BASE_PROJECT scope.
    ///
    /// Defaults to "main" (m0011 backfills every existing row); user-configured
    /// through PROJECT_UPDATE or GMVibes' project view.
    ///
    /// Defaulted rather than Optional so a stale peer that omits the key
    /// still decodes — the additive-OPTIONAL wire convention.
    let primaryProjectBranch: String
    let createdAt: String
    let updatedAt: String

    /// Creates a ProjectRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - gitRepoName: The repository name.
    ///   - code: The project code.
    ///   - name: The human-readable name.
    ///   - gmfsRelativeStoragePath: Path under the gmfs root.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - primaryProjectBranch: The branch for dope promotion; defaults to "main".
    init(
        uuid: String,
        version: Int64,
        gitRepoName: String,
        code: String,
        name: String,
        gmfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String,
        primaryProjectBranch: String = "main"
    ) {
        self.uuid = uuid
        self.version = version
        self.gitRepoName = gitRepoName
        self.code = code
        self.name = name
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.primaryProjectBranch = primaryProjectBranch
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Creates a ProjectRow from JSON, defaulting a missing branch to "main".
    ///
    /// Hand-rolled so an absent `primary_project_branch` decodes to "main"
    /// instead of throwing: GMVibes and any pinned Kit may still be sending
    /// the pre-m0011 shape.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` if any required field is missing or malformed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uuid = try c.decode(String.self, forKey: .uuid)
        self.version = try c.decode(Int64.self, forKey: .version)
        self.gitRepoName = try c.decode(String.self, forKey: .gitRepoName)
        self.code = try c.decode(String.self, forKey: .code)
        self.name = try c.decode(String.self, forKey: .name)
        self.gmfsRelativeStoragePath =
            try c.decode(String.self, forKey: .gmfsRelativeStoragePath)
        self.primaryProjectBranch =
            try c.decodeIfPresent(String.self, forKey: .primaryProjectBranch) ?? "main"
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - Instance

struct InstanceRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let projectUuid: String
    let code: String
    let name: String
    let absoluteFileSystemPath: String
    let gmfsRelativeStoragePath: String
    let createdAt: String
    let updatedAt: String

    /// Creates an InstanceRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - projectUuid: The parent project's identifier.
    ///   - code: The instance code.
    ///   - name: The human-readable name.
    ///   - absoluteFileSystemPath: The instance's absolute file system path.
    ///   - gmfsRelativeStoragePath: Path under the gmfs root.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        projectUuid: String,
        code: String,
        name: String,
        absoluteFileSystemPath: String,
        gmfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.projectUuid = projectUuid
        self.code = code
        self.name = name
        self.absoluteFileSystemPath = absoluteFileSystemPath
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Session

/// Session listing shape — full scalars minus the backstory/goal prose
/// bodies, which stay behind SESSION_GET. `status` was retired from the wire
/// at v7 (the column survives but every row has read 'active' forever;
/// checked-out state is git-derived via SESSION_RESOLVE instead).
/// `lastActivityAt` is the latest of the session's own updated_at, its
/// prompts' updated_at, and its file changes' created_at (item 1).
struct SessionStub: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let instanceUuid: String
    let code: String
    let name: String
    let gmfsRelativeStoragePath: String
    let createdAt: String
    let updatedAt: String
    let lastActivityAt: String

    /// Creates a SessionStub from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - instanceUuid: The parent instance's identifier.
    ///   - code: The session code.
    ///   - name: The human-readable name.
    ///   - gmfsRelativeStoragePath: Path under the gmfs root.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - lastActivityAt: Latest activity timestamp from session, prompts, or file changes.
    init(
        uuid: String,
        version: Int64,
        instanceUuid: String,
        code: String,
        name: String,
        gmfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String,
        lastActivityAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.instanceUuid = instanceUuid
        self.code = code
        self.name = name
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
    }
}

struct SessionRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let code: String
    let name: String
    let backstory: String
    let goal: String
    let createdAt: String
    let updatedAt: String
    /// v21-era additive OPTIONAL field: this session's activation registry —
    /// one entry per running Claude Code instance (client key → prompt).
    ///
    /// Several prompts are routinely active at once, so this is a LIST, never
    /// a single pointer. nil from a pre-v21 peer.
    let activations: [PromptActivationRow]?

    /// Creates a SessionRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - code: The session code.
    ///   - name: The human-readable name.
    ///   - backstory: The session backstory prose.
    ///   - goal: The session goal prose.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - activations: The list of running Claude Code instances, or nil from pre-v21 peers.
    init(
        uuid: String,
        version: Int64,
        code: String,
        name: String,
        backstory: String,
        goal: String,
        createdAt: String,
        updatedAt: String,
        activations: [PromptActivationRow]?
    ) {
        self.uuid = uuid
        self.version = version
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activations = activations
    }
}

/// One activation claim: a running Claude Code instance, keyed by the
/// client_key resolved from process ancestry, is working prompt X. Claimed at
/// `initiated`, which BRIEFING_OPEN stamps, and released at done — so briefing,
/// exploration and architecture all run under it.
struct PromptActivationRow: Codable, Hashable, Sendable {
    let uuid: String
    let sessionUuid: String
    let promptUuid: String
    let clientKey: String
    let createdAt: String

    /// Creates a PromptActivationRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - sessionUuid: The parent session's identifier.
    ///   - promptUuid: The active prompt's identifier.
    ///   - clientKey: The running Claude Code instance's client key.
    ///   - createdAt: Activation timestamp in ISO 8601 format.
    init(
        uuid: String,
        sessionUuid: String,
        promptUuid: String,
        clientKey: String,
        createdAt: String
    ) {
        self.uuid = uuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.clientKey = clientKey
        self.createdAt = createdAt
    }
}

// MARK: - Prompt

struct PromptRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let sessionUuid: String
    let seq: Int64
    let code: String
    let name: String
    let backstory: String
    let goal: String
    let detail: String
    let command: String
    let status: String
    let gmfsRelativeStoragePath: String
    let createdAt: String
    let updatedAt: String

    var promptStatus: PromptStatus? { PromptStatus(rawValue: status) }

    /// Creates a PromptRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - sessionUuid: The parent session's identifier.
    ///   - seq: The sequence number within the session.
    ///   - code: The prompt code.
    ///   - name: The human-readable name.
    ///   - backstory: The prompt backstory prose.
    ///   - goal: The prompt goal prose.
    ///   - detail: The prompt detail prose.
    ///   - command: The execution command.
    ///   - status: The prompt status (e.g., "active", "done").
    ///   - gmfsRelativeStoragePath: Path under the gmfs root.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        sessionUuid: String,
        seq: Int64,
        code: String,
        name: String,
        backstory: String,
        goal: String,
        detail: String,
        command: String,
        status: String,
        gmfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.sessionUuid = sessionUuid
        self.seq = seq
        self.code = code
        self.name = name
        self.backstory = backstory
        self.goal = goal
        self.detail = detail
        self.command = command
        self.status = status
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Lightweight prompt listing shape (replaces reading the session_data
/// prompts: list).
///
/// Carries its parent session uuid so whole-db listings (PROMPT_LIST with no
/// session filter) stay interpretable — seq is only unique per session.
struct PromptStub: Codable, Hashable, Sendable {
    let uuid: String
    let sessionUuid: String
    let seq: Int64
    let code: String
    let name: String
    let status: String
    let version: Int64
    let gmfsRelativeStoragePath: String
    /// Present only when PROMPT_LIST was called with `with_reports` — nested
    /// so "not requested" (nil) and "requested, none exists" (present with
    /// nil members) stay distinguishable.
    let reports: PromptReportsStub?
    let createdAt: String
    let updatedAt: String

    /// Creates a PromptStub from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - sessionUuid: The parent session's identifier.
    ///   - seq: The sequence number within the session.
    ///   - code: The prompt code.
    ///   - name: The human-readable name.
    ///   - status: The prompt status.
    ///   - version: The row version for optimistic locking.
    ///   - gmfsRelativeStoragePath: Path under the gmfs root.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - reports: Report summaries from the four machines, or nil if not requested.
    init(
        uuid: String,
        sessionUuid: String,
        seq: Int64,
        code: String,
        name: String,
        status: String,
        version: Int64,
        gmfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String,
        reports: PromptReportsStub? = nil
    ) {
        self.uuid = uuid
        self.sessionUuid = sessionUuid
        self.seq = seq
        self.code = code
        self.name = name
        self.status = status
        self.version = version
        self.gmfsRelativeStoragePath = gmfsRelativeStoragePath
        self.reports = reports
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The PROMPT_LIST `with_reports` enrichment block: one summary stub per
/// report machine.
///
/// A nil member means that summary was never opened.
struct PromptReportsStub: Codable, Hashable, Sendable {
    let clarification: ClarificationReportStub?
    let architecture: ArchitectureReportStub?
    let exploration: ExplorationReportStub?
    let review: ReviewReportStub?

    /// Creates a PromptReportsStub from the given report stubs.
    /// - Parameters:
    ///   - clarification: Clarification summary stub, or nil if not opened.
    ///   - architecture: Architecture summary stub, or nil if not opened.
    ///   - exploration: Exploration summary stub, or nil if not opened.
    ///   - review: Review summary stub, or nil if not opened.
    init(
        clarification: ClarificationReportStub?,
        architecture: ArchitectureReportStub?,
        exploration: ExplorationReportStub? = nil,
        review: ReviewReportStub? = nil
    ) {
        self.clarification = clarification
        self.architecture = architecture
        self.exploration = exploration
        self.review = review
    }
}

/// Exploration summary stub for the enrichment block.
struct ExplorationReportStub: Codable, Hashable, Sendable {
    let summaryUuid: String
    let version: Int64
    let status: String
    let keyFileCount: Int
    let findingCount: Int
    /// Findings under the read threshold (rating < 100).
    let sub100FindingCount: Int
    /// Resume signal: >0 means the exploration stalled before ranking.
    let unrankedFindingCount: Int

    /// Creates an ExplorationReportStub from the given scalar values.
    /// - Parameters:
    ///   - summaryUuid: The exploration summary's identifier.
    ///   - version: The row version for optimistic locking.
    ///   - status: The summary status.
    ///   - keyFileCount: Count of files in the search scope.
    ///   - findingCount: Total count of findings.
    ///   - sub100FindingCount: Count of findings with rating below 100.
    ///   - unrankedFindingCount: Count of findings not yet ranked.
    init(
        summaryUuid: String,
        version: Int64,
        status: String,
        keyFileCount: Int,
        findingCount: Int,
        sub100FindingCount: Int,
        unrankedFindingCount: Int
    ) {
        self.summaryUuid = summaryUuid
        self.version = version
        self.status = status
        self.keyFileCount = keyFileCount
        self.findingCount = findingCount
        self.sub100FindingCount = sub100FindingCount
        self.unrankedFindingCount = unrankedFindingCount
    }
}

/// Review summary stub for the enrichment block.
struct ReviewReportStub: Codable, Hashable, Sendable {
    let summaryUuid: String
    let version: Int64
    let status: String
    let verdict: String?
    let findingCount: Int
    let sub100FindingCount: Int
    let unrankedFindingCount: Int
    /// Resume signal for the fix loop: unresolved findings.
    let openFindingCount: Int

    /// Creates a ReviewReportStub from the given scalar values.
    /// - Parameters:
    ///   - summaryUuid: The review summary's identifier.
    ///   - version: The row version for optimistic locking.
    ///   - status: The summary status.
    ///   - verdict: The review verdict, or nil if not yet issued.
    ///   - findingCount: Total count of findings.
    ///   - sub100FindingCount: Count of findings with rating below 100.
    ///   - unrankedFindingCount: Count of findings not yet ranked.
    ///   - openFindingCount: Count of findings not yet resolved.
    init(
        summaryUuid: String,
        version: Int64,
        status: String,
        verdict: String?,
        findingCount: Int,
        sub100FindingCount: Int,
        unrankedFindingCount: Int,
        openFindingCount: Int
    ) {
        self.summaryUuid = summaryUuid
        self.version = version
        self.status = status
        self.verdict = verdict
        self.findingCount = findingCount
        self.sub100FindingCount = sub100FindingCount
        self.unrankedFindingCount = unrankedFindingCount
        self.openFindingCount = openFindingCount
    }
}

/// Clarification summary stub for the enrichment block.
///
/// Carries the summary version so the caller can mutate immediately without
/// a confirming fetch.
struct ClarificationReportStub: Codable, Hashable, Sendable {
    let summaryUuid: String
    let version: Int64
    let status: String
    let questionCount: Int
    /// Resume signal: >0 means the clarification stalled mid-answering.
    let openQuestionCount: Int
    /// m0025: internal notes replace the retired summary text fields.
    let noteCount: Int
    /// m0025: whether a ready care package exists (the clarified intent).
    let carePackageReady: Bool

    /// Creates a ClarificationReportStub from the given scalar values.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary's identifier.
    ///   - version: The row version for optimistic locking.
    ///   - status: The summary status.
    ///   - questionCount: Total count of questions.
    ///   - openQuestionCount: Count of questions not yet answered.
    ///   - noteCount: Count of internal notes; defaults to 0.
    ///   - carePackageReady: Whether a clarified intent package exists; defaults to false.
    init(
        summaryUuid: String,
        version: Int64,
        status: String,
        questionCount: Int,
        openQuestionCount: Int,
        noteCount: Int = 0,
        carePackageReady: Bool = false
    ) {
        self.summaryUuid = summaryUuid
        self.version = version
        self.status = status
        self.questionCount = questionCount
        self.openQuestionCount = openQuestionCount
        self.noteCount = noteCount
        self.carePackageReady = carePackageReady
    }
}

/// Architecture summary stub for the enrichment block.
struct ArchitectureReportStub: Codable, Hashable, Sendable {
    let summaryUuid: String
    let version: Int64
    let status: String
    let persistenceChangeCount: Int
    let generalChangeCount: Int

    /// Creates an ArchitectureReportStub from the given scalar values.
    /// - Parameters:
    ///   - summaryUuid: The architecture summary's identifier.
    ///   - version: The row version for optimistic locking.
    ///   - status: The summary status.
    ///   - persistenceChangeCount: Count of persistence-layer changes.
    ///   - generalChangeCount: Count of general-layer changes.
    init(
        summaryUuid: String,
        version: Int64,
        status: String,
        persistenceChangeCount: Int,
        generalChangeCount: Int
    ) {
        self.summaryUuid = summaryUuid
        self.version = version
        self.status = status
        self.persistenceChangeCount = persistenceChangeCount
        self.generalChangeCount = generalChangeCount
    }
}

/// One ranked SEARCH result.
///
/// Stubs-not-content discipline: `excerpt` is a bounded FTS5 snippet, never
/// a full body; full prompt lineage rides along so the caller never needs a
/// follow-up fetch to know what it found.
struct SearchHit: Codable, Hashable, Sendable {
    /// Raw kind string (same forward-compat rule as event kinds/error codes).
    let kind: String
    /// The matched row's own uuid.
    let subjectUuid: String
    let promptUuid: String
    let promptSeq: Int64
    let promptName: String
    let promptStatus: String
    let sessionUuid: String
    let sessionCode: String
    /// Short label per kind: prompt name / question / file path / "architecture summary".
    let title: String
    /// Bounded snippet from the best-matching column.
    let excerpt: String
    /// bm25-derived; negative, smaller = better; comparable WITHIN a kind only.
    let score: Double

    /// Creates a SearchHit from the given scalar values.
    /// - Parameters:
    ///   - kind: The result kind (prompt, question, file path, etc.).
    ///   - subjectUuid: The matched row's unique identifier.
    ///   - promptUuid: The containing prompt's identifier.
    ///   - promptSeq: The prompt's sequence number in its session.
    ///   - promptName: The prompt's human-readable name.
    ///   - promptStatus: The prompt's current status.
    ///   - sessionUuid: The containing session's identifier.
    ///   - sessionCode: The session's code.
    ///   - title: A short label for the match.
    ///   - excerpt: A bounded snippet from the best-matching column.
    ///   - score: A bm25 relevance score; negative, smaller is better.
    init(
        kind: String,
        subjectUuid: String,
        promptUuid: String,
        promptSeq: Int64,
        promptName: String,
        promptStatus: String,
        sessionUuid: String,
        sessionCode: String,
        title: String,
        excerpt: String,
        score: Double
    ) {
        self.kind = kind
        self.subjectUuid = subjectUuid
        self.promptUuid = promptUuid
        self.promptSeq = promptSeq
        self.promptName = promptName
        self.promptStatus = promptStatus
        self.sessionUuid = sessionUuid
        self.sessionCode = sessionCode
        self.title = title
        self.excerpt = excerpt
        self.score = score
    }
}

// MARK: - Artifact

struct ArtifactRow: Codable, Hashable, Sendable {
    let uuid: String
    let promptUuid: String
    let filePath: String
    let note: String?
    let createdAt: String

    /// Creates an ArtifactRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - promptUuid: The source prompt's identifier.
    ///   - filePath: The artifact file path.
    ///   - note: Optional notes about the artifact.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    init(uuid: String, promptUuid: String, filePath: String, note: String?, createdAt: String) {
        self.uuid = uuid
        self.promptUuid = promptUuid
        self.filePath = filePath
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - File change

struct ChangeRangeRow: Codable, Hashable, Sendable {
    let lineStart: Int
    let lineEnd: Int

    /// Creates a ChangeRangeRow from the given line boundaries.
    /// - Parameters:
    ///   - lineStart: The starting line number (inclusive).
    ///   - lineEnd: The ending line number (inclusive).
    init(lineStart: Int, lineEnd: Int) {
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

struct FileChangeRow: Codable, Hashable, Sendable {
    let uuid: String
    let sessionUuid: String
    let promptUuid: String?
    let relativePath: String
    let changeKind: String
    /// Attribution axis (all OPTIONAL — additive decode both ways).
    let agentId: String?
    let agentName: String?
    /// Server-stamped from the attributed prompt's active bot_workflow.
    let workflowPhase: String?
    /// `FileChangeOrigin` — provenance honesty (defaulted 'hook').
    ///
    /// Rows written under a wider vocabulary keep their stored value.
    let origin: String?
    /// The captured tool call. claudeTurnId is Claude Code's TURN id (payload
    /// field `prompt_id`) and is NOT a gmcc prompt uuid.
    let claudeSessionId: String?
    let claudeTurnId: String?
    let toolUseId: String?
    let toolName: String?
    let agentType: String?
    let permissionMode: String?
    let durationMs: Int?
    let transcriptPath: String?
    /// The authoritative link to the identity that made the change; `agentId`
    /// above is the denormalized form for queries that do not want the join.
    ///
    /// NULL for a PRIMARY write — the primary carries no agent_id at all, and
    /// that absence is the primary/subagent discriminator.
    let agentRegistrationUuid: String?
    let createdAt: String
    let ranges: [ChangeRangeRow]

    /// Creates a FileChangeRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - sessionUuid: The containing session's identifier.
    ///   - promptUuid: The source prompt's identifier, or nil if not attributed.
    ///   - relativePath: The file path relative to the repo root.
    ///   - changeKind: The type of change (create, delete, edit, etc.).
    ///   - createdAt: Capture timestamp in ISO 8601 format.
    ///   - ranges: Line ranges affected by the change.
    ///   - agentId: The agent's identifier, or nil for a primary write.
    ///   - agentName: The agent's human-readable name.
    ///   - workflowPhase: The workflow phase at capture time.
    ///   - origin: The change origin (hook, tool call, etc.); defaults to 'hook'.
    ///   - claudeSessionId: Claude Code's session identifier.
    ///   - claudeTurnId: Claude Code's turn identifier (not a gmcc prompt uuid).
    ///   - toolUseId: The tool use identifier from the transcript.
    ///   - toolName: The tool being used.
    ///   - agentType: The agent type (subagent, teammate, etc.).
    ///   - permissionMode: The permission mode in effect at capture.
    ///   - durationMs: Duration of the operation in milliseconds.
    ///   - transcriptPath: Path to the captured transcript.
    ///   - agentRegistrationUuid: The agent's registration identifier, or nil for primary.
    init(
        uuid: String,
        sessionUuid: String,
        promptUuid: String?,
        relativePath: String,
        changeKind: String,
        createdAt: String,
        ranges: [ChangeRangeRow],
        agentId: String? = nil,
        agentName: String? = nil,
        workflowPhase: String? = nil,
        origin: String? = nil,
        claudeSessionId: String? = nil,
        claudeTurnId: String? = nil,
        toolUseId: String? = nil,
        toolName: String? = nil,
        agentType: String? = nil,
        permissionMode: String? = nil,
        durationMs: Int? = nil,
        transcriptPath: String? = nil,
        agentRegistrationUuid: String? = nil
    ) {
        self.uuid = uuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.relativePath = relativePath
        self.changeKind = changeKind
        self.agentId = agentId
        self.agentName = agentName
        self.workflowPhase = workflowPhase
        self.origin = origin
        self.claudeSessionId = claudeSessionId
        self.claudeTurnId = claudeTurnId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.agentType = agentType
        self.permissionMode = permissionMode
        self.durationMs = durationMs
        self.transcriptPath = transcriptPath
        self.agentRegistrationUuid = agentRegistrationUuid
        self.createdAt = createdAt
        self.ranges = ranges
    }
}

// MARK: - Agent registration

/// One row per agent_id: the merged answer to "who is agent X".
///
/// The identity half comes from the SubagentStart payload and the authority
/// half from the spawner's AGENT_REGISTER. Each is written independently and
/// either may arrive first, so any field can legitimately be nil. NOT an
/// agent_briefing: a briefing is keyed per (prompt, step), which cannot hold
/// four same-typed explorers — the case this row exists for.
struct AgentRegistrationRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    /// Opaque, never parsed.
    let agentId: String
    let claudeSessionId: String?
    let claudeTurnId: String?
    let sessionUuid: String?
    let promptUuid: String?
    /// The payload's LABEL for the agent, never authoritative: it is
    /// overloaded by spawn shape — a plain subagent reports its
    /// subagent_type, a bare workflow agent the literal workflow-subagent, a
    /// named teammate its NAME.
    let agentType: String?
    let role: String?
    let methodology: String?
    let workflowPhase: String?
    let createdAt: String
    let updatedAt: String

    /// Creates an AgentRegistrationRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - agentId: The opaque agent identifier.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - claudeSessionId: Claude Code's session identifier if known.
    ///   - claudeTurnId: Claude Code's turn identifier if known.
    ///   - sessionUuid: The gmcc session identifier if known.
    ///   - promptUuid: The prompt identifier if known.
    ///   - agentType: The agent type if known.
    ///   - role: The agent's role if known.
    ///   - methodology: The agent's methodology if known.
    ///   - workflowPhase: The workflow phase at creation if known.
    init(
        uuid: String,
        version: Int64,
        agentId: String,
        createdAt: String,
        updatedAt: String,
        claudeSessionId: String? = nil,
        claudeTurnId: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        agentType: String? = nil,
        role: String? = nil,
        methodology: String? = nil,
        workflowPhase: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.agentId = agentId
        self.claudeSessionId = claudeSessionId
        self.claudeTurnId = claudeTurnId
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.role = role
        self.methodology = methodology
        self.workflowPhase = workflowPhase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Kbite

/// Minimal kbite handle for registry listings.
struct KbiteRef: Codable, Hashable, Sendable {
    let uuid: String
    let code: String

    /// Creates a KbiteRef from the given identifier and code.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - code: The kbite code.
    init(uuid: String, code: String) {
        self.uuid = uuid
        self.code = code
    }
}

struct KbiteRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let code: String
    let createdAt: String
    let updatedAt: String

    /// Creates a KbiteRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - code: The kbite code.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(uuid: String, version: Int64, code: String, createdAt: String, updatedAt: String) {
        self.uuid = uuid
        self.version = version
        self.code = code
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A consumed source within a kbite, carrying its file stubs. resource_summary
/// is the full chewed analysis body — the per-resource synthesis.
struct KbiteResourceRow: Codable, Hashable, Sendable {
    let uuid: String
    let kbiteUuid: String
    let resourceName: String
    let resourceSummary: String
    let resourceType: String
    let resourceTrust: Int
    let files: [KbiteResourceFileStub]

    /// Creates a KbiteResourceRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kbiteUuid: The parent kbite's identifier.
    ///   - resourceName: The resource name.
    ///   - resourceSummary: The synthesized analysis of the resource.
    ///   - resourceType: The resource type.
    ///   - resourceTrust: The trust level of this resource.
    ///   - files: The files within this resource.
    init(
        uuid: String,
        kbiteUuid: String,
        resourceName: String,
        resourceSummary: String,
        resourceType: String,
        resourceTrust: Int,
        files: [KbiteResourceFileStub]
    ) {
        self.uuid = uuid
        self.kbiteUuid = kbiteUuid
        self.resourceName = resourceName
        self.resourceSummary = resourceSummary
        self.resourceType = resourceType
        self.resourceTrust = resourceTrust
        self.files = files
    }
}

/// File listing shape — name + summary only; content stays behind
/// KBITE_FILE_GET (the targeted load).
struct KbiteResourceFileStub: Codable, Hashable, Sendable {
    let uuid: String
    let resourceFileName: String
    let resourceFileSummary: String
    let hasContent: Bool

    /// Creates a KbiteResourceFileStub from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - resourceFileName: The file name.
    ///   - resourceFileSummary: A summary of the file.
    ///   - hasContent: True if the file has text content; false for binary/images.
    init(uuid: String, resourceFileName: String, resourceFileSummary: String, hasContent: Bool) {
        self.uuid = uuid
        self.resourceFileName = resourceFileName
        self.resourceFileSummary = resourceFileSummary
        self.hasContent = hasContent
    }
}

/// Full file row including content (nil for images/binaries the filesystem
/// keeps raw).
struct KbiteResourceFileRow: Codable, Hashable, Sendable {
    let uuid: String
    let kbiteResourceUuid: String
    let resourceFileName: String
    let resourceFileSummary: String
    let resourceFileContent: String?
    let createdAt: String

    /// Creates a KbiteResourceFileRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kbiteResourceUuid: The parent resource's identifier.
    ///   - resourceFileName: The file name.
    ///   - resourceFileSummary: A summary of the file.
    ///   - resourceFileContent: The file content for text files; nil for binary/images.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    init(
        uuid: String,
        kbiteResourceUuid: String,
        resourceFileName: String,
        resourceFileSummary: String,
        resourceFileContent: String?,
        createdAt: String
    ) {
        self.uuid = uuid
        self.kbiteResourceUuid = kbiteResourceUuid
        self.resourceFileName = resourceFileName
        self.resourceFileSummary = resourceFileSummary
        self.resourceFileContent = resourceFileContent
        self.createdAt = createdAt
    }
}

/// One KBITE_SEARCH result: file-level stub with its kbite/resource lineage,
/// bm25 score (smaller = more relevant), and the file's attached keywords.
struct KbiteSearchHit: Codable, Hashable, Sendable {
    let kbiteCode: String
    let kbiteUuid: String
    let resourceName: String
    let fileUuid: String
    let fileName: String
    let fileSummary: String
    let matchedKeywords: [String]
    let score: Double

    /// Creates a KbiteSearchHit from the given scalar values.
    /// - Parameters:
    ///   - kbiteCode: The kbite code.
    ///   - kbiteUuid: The kbite's unique identifier.
    ///   - resourceName: The resource name within the kbite.
    ///   - fileUuid: The file's unique identifier.
    ///   - fileName: The file name.
    ///   - fileSummary: A summary of the file.
    ///   - matchedKeywords: Keywords matched in the search.
    ///   - score: A bm25 relevance score; negative, smaller is better.
    init(
        kbiteCode: String,
        kbiteUuid: String,
        resourceName: String,
        fileUuid: String,
        fileName: String,
        fileSummary: String,
        matchedKeywords: [String],
        score: Double
    ) {
        self.kbiteCode = kbiteCode
        self.kbiteUuid = kbiteUuid
        self.resourceName = resourceName
        self.fileUuid = fileUuid
        self.fileName = fileName
        self.fileSummary = fileSummary
        self.matchedKeywords = matchedKeywords
        self.score = score
    }
}

// MARK: - Change summaries

struct ChangeSummary: Codable, Hashable, Sendable {
    let changeCount: Int
    let distinctFiles: Int
    let totalLineSpan: Int

    /// Creates a ChangeSummary from the given counts.
    /// - Parameters:
    ///   - changeCount: Total number of changes.
    ///   - distinctFiles: Count of distinct files affected.
    ///   - totalLineSpan: Total span of lines affected.
    init(changeCount: Int, distinctFiles: Int, totalLineSpan: Int) {
        self.changeCount = changeCount
        self.distinctFiles = distinctFiles
        self.totalLineSpan = totalLineSpan
    }
}

struct PromptChangeSummary: Codable, Hashable, Sendable {
    /// nil = changes not attributed to any prompt.
    let promptUuid: String?
    let summary: ChangeSummary

    /// Creates a PromptChangeSummary from the given identifierand summary.
    /// - Parameters:
    ///   - promptUuid: The prompt's identifier, or nil if unattributed.
    ///   - summary: The change summary.
    init(promptUuid: String?, summary: ChangeSummary) {
        self.promptUuid = promptUuid
        self.summary = summary
    }
}

// MARK: - Clarification (m0025 split)

struct ClarificationSummaryRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let status: String
    let createdAt: String
    let updatedAt: String

    var clarificationStatus: ClarificationStatus? { ClarificationStatus(rawValue: status) }

    /// Creates a ClarificationSummaryRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - promptUuid: The parent prompt's identifier.
    ///   - status: The clarification status.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        status: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.promptUuid = promptUuid
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A user-facing clarification question.
///
/// The selected answer(s) live in `selectedOptionUuids` (junction rows) —
/// empty + non-nil answerText means the user typed a free answer; both may
/// coexist (select AND elaborate).
struct ClarificationQuestionRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let clarificationSummaryUuid: String
    let seq: Int64
    let question: String
    let status: String
    let answerText: String?
    let agentId: String?
    let agentName: String?
    let options: [ClarificationOptionRow]
    let selectedOptionUuids: [String]

    /// Creates a ClarificationQuestionRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - clarificationSummaryUuid: The parent clarification summary's identifier.
    ///   - seq: The sequence number within the summary.
    ///   - question: The question text.
    ///   - status: The question status.
    ///   - answerText: Free-text answer if provided; nil for option-only answers.
    ///   - agentId: The answering agent's identifier if known.
    ///   - agentName: The answering agent's human-readable name.
    ///   - options: The available answer options.
    ///   - selectedOptionUuids: Uuids of selected options.
    init(
        uuid: String,
        version: Int64,
        clarificationSummaryUuid: String,
        seq: Int64,
        question: String,
        status: String,
        answerText: String?,
        agentId: String?,
        agentName: String?,
        options: [ClarificationOptionRow],
        selectedOptionUuids: [String]
    ) {
        self.uuid = uuid
        self.version = version
        self.clarificationSummaryUuid = clarificationSummaryUuid
        self.seq = seq
        self.question = question
        self.status = status
        self.answerText = answerText
        self.agentId = agentId
        self.agentName = agentName
        self.options = options
        self.selectedOptionUuids = selectedOptionUuids
    }
}

struct ClarificationOptionRow: Codable, Hashable, Sendable {
    let uuid: String
    let seq: Int64
    let body: String

    /// Creates a ClarificationOptionRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - seq: The sequence number within the question.
    ///   - body: The option text.
    init(uuid: String, seq: Int64, body: String) {
        self.uuid = uuid
        self.seq = seq
        self.body = body
    }
}

/// An agent-authored internal note clarifying something that confused
/// exploration or the clarifier itself. weight uses the finding_rating
/// polarity: 0 = critical, 999 = ignore.
struct ClarificationNoteRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let clarificationSummaryUuid: String
    let body: String
    let confusedEntityUuid: String?
    let confusedEntityType: String?
    let weight: Int?
    let questionUuid: String?
    let agentId: String?
    let agentName: String?

    /// Creates a ClarificationNoteRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - clarificationSummaryUuid: The parent clarification summary's identifier.
    ///   - body: The note body.
    ///   - confusedEntityUuid: The entity (finding, question, etc.) being clarified.
    ///   - confusedEntityType: The type of the confused entity.
    ///   - weight: Finding rating (0 = critical, 999 = ignore).
    ///   - questionUuid: The question clarifying this entity, if known.
    ///   - agentId: The authoring agent's identifier.
    ///   - agentName: The authoring agent's human-readable name.
    init(
        uuid: String,
        version: Int64,
        clarificationSummaryUuid: String,
        body: String,
        confusedEntityUuid: String?,
        confusedEntityType: String?,
        weight: Int?,
        questionUuid: String?,
        agentId: String?,
        agentName: String?
    ) {
        self.uuid = uuid
        self.version = version
        self.clarificationSummaryUuid = clarificationSummaryUuid
        self.body = body
        self.confusedEntityUuid = confusedEntityUuid
        self.confusedEntityType = confusedEntityType
        self.weight = weight
        self.questionUuid = questionUuid
        self.agentId = agentId
        self.agentName = agentName
    }
}

// MARK: - Care package (m0025)

/// The standalone clarified-intent bundle on a clarification summary.
///
/// NEVER written back to the prompt row — the prompt triple is human input.
struct CarePackageRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let clarificationSummaryUuid: String
    let clarifiedIntent: String
    let status: String
    let dopeScopeUuid: String?
    let dopeScopeRevision: Int64?
    let dopeRefs: [CarePackageDopeRefRow]
    let kbiteRefs: [CarePackageKbiteRefRow]
    let explorationRefs: [CarePackageExplorationRefRow]
    let createdAt: String
    let updatedAt: String

    /// Creates a CarePackageRow from the given scalar values and reference lists.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - clarificationSummaryUuid: The parent clarification summary's identifier.
    ///   - clarifiedIntent: The clarified intent prose.
    ///   - status: The care package status.
    ///   - dopeScopeUuid: The dope scope identifier if linked.
    ///   - dopeScopeRevision: The dope scope revision if linked.
    ///   - dopeRefs: References to dope entities.
    ///   - kbiteRefs: References to kbite files.
    ///   - explorationRefs: References to curated exploration output.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        clarificationSummaryUuid: String,
        clarifiedIntent: String,
        status: String,
        dopeScopeUuid: String?,
        dopeScopeRevision: Int64?,
        dopeRefs: [CarePackageDopeRefRow],
        kbiteRefs: [CarePackageKbiteRefRow],
        explorationRefs: [CarePackageExplorationRefRow],
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.clarificationSummaryUuid = clarificationSummaryUuid
        self.clarifiedIntent = clarifiedIntent
        self.status = status
        self.dopeScopeUuid = dopeScopeUuid
        self.dopeScopeRevision = dopeScopeRevision
        self.dopeRefs = dopeRefs
        self.kbiteRefs = kbiteRefs
        self.explorationRefs = explorationRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CarePackageDopeRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let dopeCode: String
    let note: String?
    let seq: Int

    /// Creates a CarePackageDopeRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - dopeCode: The dope entity code.
    ///   - note: Optional note about this reference.
    ///   - seq: The sequence number within the care package.
    init(uuid: String, dopeCode: String, note: String?, seq: Int) {
        self.uuid = uuid
        self.dopeCode = dopeCode
        self.note = note
        self.seq = seq
    }
}

struct CarePackageKbiteRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let kbiteResourceFileUuid: String
    let brief: String?
    let seq: Int

    /// Creates a CarePackageKbiteRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kbiteResourceFileUuid: The referenced kbite file's identifier.
    ///   - brief: Optional brief note about this reference.
    ///   - seq: The sequence number within the care package.
    init(uuid: String, kbiteResourceFileUuid: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.kbiteResourceFileUuid = kbiteResourceFileUuid
        self.brief = brief
        self.seq = seq
    }
}

/// A curated COPY of exploration output (never re-explored); the soft
/// provenance ref survives source pruning via SET NULL.
struct CarePackageExplorationRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let curatedTitle: String
    let curatedBody: String
    let filePath: String?
    let sourceFindingUuid: String?
    let seq: Int

    /// Creates a CarePackageExplorationRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - curatedTitle: The curated title for this item.
    ///   - curatedBody: The curated body content.
    ///   - filePath: The file path this finding relates to, if any.
    ///   - sourceFindingUuid: The original finding's identifier, if known.
    ///   - seq: The sequence number within the care package.
    init(
        uuid: String,
        curatedTitle: String,
        curatedBody: String,
        filePath: String?,
        sourceFindingUuid: String?,
        seq: Int
    ) {
        self.uuid = uuid
        self.curatedTitle = curatedTitle
        self.curatedBody = curatedBody
        self.filePath = filePath
        self.sourceFindingUuid = sourceFindingUuid
        self.seq = seq
    }
}

// MARK: - Architecture (v7)

struct ArchitectureSummaryRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let body: String
    let status: String
    /// m0025: why the selected option won (empty when no options flow ran).
    let decisionRationale: String?
    let createdAt: String
    let updatedAt: String

    var architectureStatus: ArchitectureStatus? { ArchitectureStatus(rawValue: status) }

    /// Creates an ArchitectureSummaryRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - promptUuid: The parent prompt's identifier.
    ///   - body: The architecture summary body prose.
    ///   - status: The summary status.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - decisionRationale: Why the selected option won; nil if no options ran.
    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        body: String,
        status: String,
        createdAt: String,
        updatedAt: String,
        decisionRationale: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.promptUuid = promptUuid
        self.body = body
        self.status = status
        self.decisionRationale = decisionRationale
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Implementation-state decoration on a planned change row — DERIVED from the
/// path join against file_change at read time, never stored, so it can never
/// go stale. fileChangeCount 0 = planned but untouched.
struct ChangeImplementationState: Codable, Hashable, Sendable {
    let fileChangeCount: Int
    let firstChangedAt: String?
    let lastChangedAt: String?

    /// Creates a ChangeImplementationState from the given counts and timestamps.
    /// - Parameters:
    ///   - fileChangeCount: Number of file changes implementing this planned change.
    ///   - firstChangedAt: Timestamp of the first implementing change, if any.
    ///   - lastChangedAt: Timestamp of the latest implementing change, if any.
    init(fileChangeCount: Int, firstChangedAt: String?, lastChangedAt: String?) {
        self.fileChangeCount = fileChangeCount
        self.firstChangedAt = firstChangedAt
        self.lastChangedAt = lastChangedAt
    }
}

struct ArchPersistenceFieldChangeRow: Codable, Hashable, Sendable {
    let uuid: String
    let seq: Int64
    let fieldName: String
    let changeReason: String
    let changePurpose: String
    let dataType: String
    let nullable: Bool
    let isForeignKey: Bool
    let fkTarget: String?
    let isIndexed: Bool
    /// m0025: add|modify|rename|delete.
    let changeKind: String?
    /// m0025: old field name when changeKind == rename.
    let renamedFrom: String?
    /// m0025: domain.entity.property dot-path CODE (ghost-legal).
    let dopePropertyRef: String?

    /// Creates an ArchPersistenceFieldChangeRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - seq: The sequence number within the persistence change.
    ///   - fieldName: The field name.
    ///   - changeReason: Why the field changed.
    ///   - changePurpose: The purpose of the change.
    ///   - dataType: The field's data type.
    ///   - nullable: True if the field allows null.
    ///   - isForeignKey: True if this is a foreign key.
    ///   - fkTarget: The foreign key target table, if applicable.
    ///   - isIndexed: True if the field is indexed.
    ///   - changeKind: add|modify|rename|delete.
    ///   - renamedFrom: Old field name if changeKind == rename.
    ///   - dopePropertyRef: Domain.entity.property dope code reference.
    init(
        uuid: String,
        seq: Int64,
        fieldName: String,
        changeReason: String,
        changePurpose: String,
        dataType: String,
        nullable: Bool,
        isForeignKey: Bool,
        fkTarget: String?,
        isIndexed: Bool,
        changeKind: String? = nil,
        renamedFrom: String? = nil,
        dopePropertyRef: String? = nil
    ) {
        self.uuid = uuid
        self.seq = seq
        self.fieldName = fieldName
        self.changeReason = changeReason
        self.changePurpose = changePurpose
        self.dataType = dataType
        self.nullable = nullable
        self.isForeignKey = isForeignKey
        self.fkTarget = fkTarget
        self.isIndexed = isIndexed
        self.changeKind = changeKind
        self.renamedFrom = renamedFrom
        self.dopePropertyRef = dopePropertyRef
    }
}

struct ArchPersistenceChangeRow: Codable, Hashable, Sendable {
    let uuid: String
    let seq: Int64
    let className: String
    let filePath: String
    let reasonBrief: String
    /// m0025: add|modify|rename|delete — negative changes are first-class.
    let changeKind: String?
    /// m0025: domain.entity dot-path CODE (ghost-legal), never a uuid.
    let dopeRef: String?
    let fields: [ArchPersistenceFieldChangeRow]
    let implementation: ChangeImplementationState

    /// Creates an ArchPersistenceChangeRow from the given scalar and reference values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - seq: The sequence number within the architecture summary.
    ///   - className: The class/table name being changed.
    ///   - filePath: The file path for this entity.
    ///   - reasonBrief: Brief explanation for the change.
    ///   - fields: The field-level changes.
    ///   - implementation: The implementation state decoration.
    ///   - changeKind: add|modify|rename|delete.
    ///   - dopeRef: Domain.entity dope code reference.
    init(
        uuid: String,
        seq: Int64,
        className: String,
        filePath: String,
        reasonBrief: String,
        fields: [ArchPersistenceFieldChangeRow],
        implementation: ChangeImplementationState,
        changeKind: String? = nil,
        dopeRef: String? = nil
    ) {
        self.uuid = uuid
        self.seq = seq
        self.className = className
        self.filePath = filePath
        self.reasonBrief = reasonBrief
        self.changeKind = changeKind
        self.dopeRef = dopeRef
        self.fields = fields
        self.implementation = implementation
    }
}

/// One methodology's persisted architecture proposal (m0025 pen inversion —
/// the first architect pen).
///
/// Only the SELECTED option expands into change rows; losers persist as
/// feature-graft offers.
struct ArchitectureOptionRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let architectureSummaryUuid: String
    let agentName: String
    let agentId: String?
    let body: String
    let status: String
    let createdAt: String
    let updatedAt: String

    /// Creates an ArchitectureOptionRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - architectureSummaryUuid: The parent architecture summary's identifier.
    ///   - agentName: The methodology/agent name.
    ///   - agentId: The agent's identifier, if known.
    ///   - body: The architecture option prose.
    ///   - status: The option status.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        architectureSummaryUuid: String,
        agentName: String,
        agentId: String?,
        body: String,
        status: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.architectureSummaryUuid = architectureSummaryUuid
        self.agentName = agentName
        self.agentId = agentId
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Bot workflow (m0025)

/// The daemon-held workflow state machine row.
///
/// Phase is DERIVED from db evidence at every BOT_NEXT; lastServedPhase is
/// observability only.
struct BotWorkflowRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let sessionUuid: String
    let promptUuid: String
    let variant: String
    let status: String
    let clientKey: String?
    let lastServedPhase: String?
    let createdAt: String
    let updatedAt: String

    /// Creates a BotWorkflowRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - sessionUuid: The parent session's identifier.
    ///   - promptUuid: The parent prompt's identifier.
    ///   - variant: The workflow variant (bot, rpi, team, etc.).
    ///   - status: The workflow status.
    ///   - clientKey: The active Claude Code instance's client key, if any.
    ///   - lastServedPhase: The last workflow phase served; observability only.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        sessionUuid: String,
        promptUuid: String,
        variant: String,
        status: String,
        clientKey: String?,
        lastServedPhase: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.variant = variant
        self.status = status
        self.clientKey = clientKey
        self.lastServedPhase = lastServedPhase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ArchGeneralChangeRow: Codable, Hashable, Sendable {
    let uuid: String
    let seq: Int64
    let filePath: String
    let className: String?
    let reasonBrief: String
    let changeDepth: String
    let changeCode: String
    let implementation: ChangeImplementationState

    /// Creates an ArchGeneralChangeRow from the given scalar and reference values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - seq: The sequence number within the architecture summary.
    ///   - filePath: The file path for this change.
    ///   - className: The class name being changed, if applicable.
    ///   - reasonBrief: Brief explanation for the change.
    ///   - changeDepth: The scope of the change (function, class, file, etc.).
    ///   - changeCode: A code describing the type of change.
    ///   - implementation: The implementation state decoration.
    init(
        uuid: String,
        seq: Int64,
        filePath: String,
        className: String?,
        reasonBrief: String,
        changeDepth: String,
        changeCode: String,
        implementation: ChangeImplementationState
    ) {
        self.uuid = uuid
        self.seq = seq
        self.filePath = filePath
        self.className = className
        self.reasonBrief = reasonBrief
        self.changeDepth = changeDepth
        self.changeCode = changeCode
        self.implementation = implementation
    }
}

/// A file this prompt touched that no architecture change row planned —
/// scope drift, the bucket that accelerates debugging.
struct UnplannedChangeRow: Codable, Hashable, Sendable {
    let path: String
    let changeCount: Int
    let firstChangedAt: String
    let lastChangedAt: String

    /// Creates an UnplannedChangeRow from the given scalar values.
    /// - Parameters:
    ///   - path: The file path.
    ///   - changeCount: Total number of changes to the file.
    ///   - firstChangedAt: Timestamp of the first change.
    ///   - lastChangedAt: Timestamp of the latest change.
    init(path: String, changeCount: Int, firstChangedAt: String, lastChangedAt: String) {
        self.path = path
        self.changeCount = changeCount
        self.firstChangedAt = firstChangedAt
        self.lastChangedAt = lastChangedAt
    }
}

// MARK: - Exploration (v9)

struct ExplorationSummaryRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    /// m0025: aggressive|conservative|pragmatic|alternative|general|synthesis.
    ///
    /// The synthesis-type row is the prompt-level seal/synthesis home.
    let agentType: String
    let agentId: String?
    let status: String
    let overview: String
    let createdAt: String
    let updatedAt: String

    var explorationStatus: ExplorationStatus? { ExplorationStatus(rawValue: status) }

    /// Creates an ExplorationSummaryRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - promptUuid: The parent prompt's identifier.
    ///   - agentType: aggressive|conservative|pragmatic|alternative|general|synthesis.
    ///   - agentId: The agent's identifier, if known.
    ///   - status: The summary status.
    ///   - overview: The exploration overview prose.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        agentType: String,
        agentId: String?,
        status: String,
        overview: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.promptUuid = promptUuid
        self.agentType = agentType
        self.agentId = agentId
        self.status = status
        self.overview = overview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One agent briefing (m0025 shape): an opinion-free ref pre-selection a
/// briefer agent assembles for a phase.
///
/// The old body/dope_refs/kbite_refs TEXT columns are gone — refs are typed
/// child rows.
struct AgentBriefingRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let sessionUuid: String
    /// nil = task-owned (a /gm_task run, no prompt row).
    let promptUuid: String?
    let briefingForStep: String
    let status: String
    let agentId: String?
    let dopeScopeUuid: String?
    let dopeScopeRevision: Int64?
    let dopeRefs: [AgentBriefingDopeRefRow]
    let kbiteRefs: [AgentBriefingKbiteRefRow]
    let fileChangeRefs: [AgentBriefingFileChangeRefRow]
    let createdAt: String
    let updatedAt: String

    /// Creates an AgentBriefingRow from the given scalar and reference values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - sessionUuid: The parent session's identifier.
    ///   - promptUuid: The parent prompt's identifier, or nil for task-owned briefings.
    ///   - briefingForStep: The workflow step this briefing supports.
    ///   - status: The briefing status.
    ///   - agentId: The briefing agent's identifier, if known.
    ///   - dopeScopeUuid: The linked dope scope's identifier, if known.
    ///   - dopeScopeRevision: The linked dope scope's revision, if known.
    ///   - dopeRefs: References to dope entities.
    ///   - kbiteRefs: References to kbite files.
    ///   - fileChangeRefs: References to recent file changes.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    init(
        uuid: String,
        version: Int64,
        sessionUuid: String,
        promptUuid: String?,
        briefingForStep: String,
        status: String,
        agentId: String?,
        dopeScopeUuid: String?,
        dopeScopeRevision: Int64?,
        dopeRefs: [AgentBriefingDopeRefRow],
        kbiteRefs: [AgentBriefingKbiteRefRow],
        fileChangeRefs: [AgentBriefingFileChangeRefRow],
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.briefingForStep = briefingForStep
        self.status = status
        self.agentId = agentId
        self.dopeScopeUuid = dopeScopeUuid
        self.dopeScopeRevision = dopeScopeRevision
        self.dopeRefs = dopeRefs
        self.kbiteRefs = kbiteRefs
        self.fileChangeRefs = fileChangeRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Dope refs are dot-path CODES, never uuids (ghost-binding precedent).
struct AgentBriefingDopeRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let dopeCode: String
    let brief: String?
    let seq: Int

    /// Creates an AgentBriefingDopeRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - dopeCode: The dope entity code.
    ///   - brief: Optional brief note about this reference.
    ///   - seq: The sequence number within the briefing.
    init(uuid: String, dopeCode: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.dopeCode = dopeCode
        self.brief = brief
        self.seq = seq
    }
}

struct AgentBriefingKbiteRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let kbiteResourceFileUuid: String
    let brief: String?
    let seq: Int

    /// Creates an AgentBriefingKbiteRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kbiteResourceFileUuid: The referenced kbite file's identifier.
    ///   - brief: Optional brief note about this reference.
    ///   - seq: The sequence number within the briefing.
    init(uuid: String, kbiteResourceFileUuid: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.kbiteResourceFileUuid = kbiteResourceFileUuid
        self.brief = brief
        self.seq = seq
    }
}

struct AgentBriefingFileChangeRefRow: Codable, Hashable, Sendable {
    let uuid: String
    let fileChangeUuid: String
    let seq: Int

    /// Creates an AgentBriefingFileChangeRefRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - fileChangeUuid: The referenced file change's identifier.
    ///   - seq: The sequence number within the briefing.
    init(uuid: String, fileChangeUuid: String, seq: Int) {
        self.uuid = uuid
        self.fileChangeUuid = fileChangeUuid
        self.seq = seq
    }
}

struct ExplorationKeyFileRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let explorationSummaryUuid: String
    let filePath: String

    /// Creates an ExplorationKeyFileRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - explorationSummaryUuid: The parent exploration summary's identifier.
    ///   - filePath: The key file path.
    init(uuid: String, version: Int64, explorationSummaryUuid: String, filePath: String) {
        self.uuid = uuid
        self.version = version
        self.explorationSummaryUuid = explorationSummaryUuid
        self.filePath = filePath
    }
}

struct ExplorationFindingRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let explorationSummaryUuid: String
    let kind: String
    let title: String
    let body: String
    /// m0025: the merged key-file half of the finding/file pair.
    let filePath: String?
    let agentName: String
    let agentId: String?
    /// nil = unranked (work-in-progress; blocks COMPLETE).
    let findingRating: Int?

    /// Creates an ExplorationFindingRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - explorationSummaryUuid: The parent exploration summary's identifier.
    ///   - kind: The finding kind/category.
    ///   - title: The finding title.
    ///   - body: The finding body prose.
    ///   - filePath: The file path this finding relates to, if any.
    ///   - agentName: The finding agent's human-readable name.
    ///   - agentId: The finding agent's identifier, if known.
    ///   - findingRating: The finding's rating (0 = critical, 999 = ignore); nil if unranked.
    init(
        uuid: String,
        version: Int64,
        explorationSummaryUuid: String,
        kind: String,
        title: String,
        body: String,
        filePath: String?,
        agentName: String,
        agentId: String?,
        findingRating: Int?
    ) {
        self.uuid = uuid
        self.version = version
        self.explorationSummaryUuid = explorationSummaryUuid
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.agentName = agentName
        self.agentId = agentId
        self.findingRating = findingRating
    }
}

/// Lightweight finding shape for the at-or-above-threshold partition of
/// EXPLORE_GET (stubs-not-content discipline: no body).
struct ExplorationFindingStub: Codable, Hashable, Sendable {
    let uuid: String
    let kind: String
    let title: String
    let findingRating: Int?
    let agentName: String

    /// Creates an ExplorationFindingStub from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kind: The finding kind/category.
    ///   - title: The finding title.
    ///   - findingRating: The finding's rating (0 = critical, 999 = ignore); nil if unranked.
    ///   - agentName: The finding agent's human-readable name.
    init(uuid: String, kind: String, title: String, findingRating: Int?, agentName: String) {
        self.uuid = uuid
        self.kind = kind
        self.title = title
        self.findingRating = findingRating
        self.agentName = agentName
    }
}

// MARK: - Review (v9)

struct ReviewSummaryRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let status: String
    let verdict: String?
    let overview: String
    /// m0025 agent_id sweep (additive optional).
    let agentId: String?
    let createdAt: String
    let updatedAt: String

    var reviewStatus: ReviewSummaryStatus? { ReviewSummaryStatus(rawValue: status) }

    /// Creates a ReviewSummaryRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - promptUuid: The parent prompt's identifier.
    ///   - status: The review status.
    ///   - verdict: The review verdict, or nil if not yet issued.
    ///   - overview: The review overview prose.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - agentId: The review agent's identifier, if known.
    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        status: String,
        verdict: String?,
        overview: String,
        createdAt: String,
        updatedAt: String,
        agentId: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.promptUuid = promptUuid
        self.status = status
        self.verdict = verdict
        self.overview = overview
        self.agentId = agentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ReviewFindingRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let reviewSummaryUuid: String
    let kind: String
    let title: String
    let body: String
    let filePath: String?
    let lineStart: Int?
    let lineEnd: Int?
    let agentName: String
    /// m0025 agent_id sweep (additive optional).
    let agentId: String?
    let findingRating: Int?
    let status: String

    /// Creates a ReviewFindingRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - reviewSummaryUuid: The parent review summary's identifier.
    ///   - kind: The finding kind/category.
    ///   - title: The finding title.
    ///   - body: The finding body prose.
    ///   - filePath: The file path this finding relates to, if any.
    ///   - lineStart: The starting line number, if applicable.
    ///   - lineEnd: The ending line number, if applicable.
    ///   - agentName: The finding agent's human-readable name.
    ///   - findingRating: The finding's rating (0 = critical, 999 = ignore); nil if unranked.
    ///   - status: The finding status (e.g., open, resolved).
    ///   - agentId: The finding agent's identifier, if known.
    init(
        uuid: String,
        version: Int64,
        reviewSummaryUuid: String,
        kind: String,
        title: String,
        body: String,
        filePath: String?,
        lineStart: Int?,
        lineEnd: Int?,
        agentName: String,
        findingRating: Int?,
        status: String,
        agentId: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.reviewSummaryUuid = reviewSummaryUuid
        self.kind = kind
        self.title = title
        self.body = body
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.agentName = agentName
        self.agentId = agentId
        self.findingRating = findingRating
        self.status = status
    }
}

/// Review counterpart of ExplorationFindingStub; carries `status` so the fix
/// loop sees resolution state even for stubbed findings.
struct ReviewFindingStub: Codable, Hashable, Sendable {
    let uuid: String
    let kind: String
    let title: String
    let findingRating: Int?
    let agentName: String
    let status: String

    /// Creates a ReviewFindingStub from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - kind: The finding kind/category.
    ///   - title: The finding title.
    ///   - findingRating: The finding's rating (0 = critical, 999 = ignore); nil if unranked.
    ///   - agentName: The finding agent's human-readable name.
    ///   - status: The finding status (e.g., open, resolved).
    init(uuid: String, kind: String, title: String, findingRating: Int?, agentName: String, status: String) {
        self.uuid = uuid
        self.kind = kind
        self.title = title
        self.findingRating = findingRating
        self.agentName = agentName
        self.status = status
    }
}

struct DopeScopeRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    /// m0013's chain-non-null tier ladder (mirrors DiagramRow): every tier
    /// fills its own FK and every ancestor's. project_uuid is ALWAYS present;
    /// the project tiers (BASE_PROJECT / PROJECT_ITEM) carry nothing below it.
    ///
    /// Defaulted in the memberwise init and decoded with decodeIfPresent so a
    /// pre-m0013 peer still decodes — the additive-OPTIONAL wire convention.
    let projectUuid: String
    let instanceUuid: String?
    /// nil for the two project tiers.
    ///
    /// Use `requireSessionUuid()` wherever a session is structurally required
    /// (the repo verbs, touchSession).
    let sessionUuid: String?
    let promptUuid: String?
    let scopeType: String
    /// Soft delete (m0012/m0013).
    ///
    /// Reads deliberately do NOT filter on it.
    let deletedOn: String?
    let code: String
    let name: String
    let description: String
    /// The whole-tree content counter — IS the .doped.json version field.
    let revision: Int64
    let createdAt: String
    let updatedAt: String

    /// Creates a DopeScopeRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - instanceUuid: The instance identifier in the tier ladder.
    ///   - sessionUuid: The session identifier in the tier ladder.
    ///   - promptUuid: The prompt identifier in the tier ladder.
    ///   - scopeType: The dope scope type.
    ///   - code: The dope code.
    ///   - name: The human-readable name.
    ///   - description: The description prose.
    ///   - revision: The whole-tree content counter.
    ///   - deletedOn: Soft-delete timestamp if deleted.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - projectUuid: The project identifier in the tier ladder; defaults to empty.
    init(
        uuid: String,
        version: Int64,
        instanceUuid: String?,
        sessionUuid: String?,
        promptUuid: String?,
        scopeType: String,
        code: String,
        name: String,
        description: String,
        revision: Int64,
        deletedOn: String?,
        createdAt: String,
        updatedAt: String,
        projectUuid: String = ""
    ) {
        self.uuid = uuid
        self.version = version
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.scopeType = scopeType
        self.code = code
        self.name = name
        self.description = description
        self.revision = revision
        self.deletedOn = deletedOn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Creates a DopeScopeRow from JSON, tolerant of the pre-m0013 wire format.
    ///
    /// A pre-m0013 peer omits the ladder columns entirely; this decoder
    /// provides defaults for backward compatibility.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` if any required field is missing or malformed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uuid = try c.decode(String.self, forKey: .uuid)
        self.version = try c.decode(Int64.self, forKey: .version)
        self.projectUuid = try c.decodeIfPresent(String.self, forKey: .projectUuid) ?? ""
        self.instanceUuid = try c.decodeIfPresent(String.self, forKey: .instanceUuid)
        self.sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid)
        self.promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        self.scopeType = try c.decode(String.self, forKey: .scopeType)
        self.code = try c.decode(String.self, forKey: .code)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decode(String.self, forKey: .description)
        self.revision = try c.decode(Int64.self, forKey: .revision)
        self.deletedOn = try c.decodeIfPresent(String.self, forKey: .deletedOn)
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    /// The typed tier, tolerant of the retired SESSION_BASE/PROMPT spellings.
    var tier: DopeScopeType? { DopeScopeType(fromWire: scopeType) }

    /// Session-owned tiers always carry a session.
    ///
    /// The repo verbs, boot sync and touchSession are structurally
    /// session-only, so they assert here rather than silently no-op on a
    /// project-tier scope.
    ///
    /// - Returns: The session UUID.
    /// - Throws: `StoreError.badRequest` if this scope is not session-tier.
    func requireSessionUuid() throws -> String {
        guard let sessionUuid else {
            throw StoreError.badRequest(
                detail: "scope \(uuid) is tier \(scopeType), which has no session; "
                    + "this operation is session-tier only"
            )
        }
        return sessionUuid
    }
}

struct DiagramRow: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let tier: String
    let projectUuid: String
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String
    let name: String
    let description: String
    let gmccDiagramPath: String?
    /// Which dope scope this WHOLE diagram reads and writes through
    /// (m0016).
    ///
    /// A ghost-tolerant CODE, resolved at read time, restricted to masking
    /// tiers. Distinct from per-element diagram_dope_scope bindings (those
    /// answer "which node?"; this answers "which canvas scope?").
    let dopeScopeCode: String?
    /// The whole-tree content counter (bumpDiagramRevision; never the row's
    /// optimistic-lock version).
    let revision: Int64
    /// PRIVATE (db-only) | PUBLIC (repo-serializable; SESSION tier only).
    ///
    /// Decodes absent as PRIVATE so pre-m0024 snapshots read unchanged.
    let visibility: String
    let createdAt: String
    let updatedAt: String

    /// Creates a DiagramRow from the given scalar values.
    /// - Parameters:
    ///   - uuid: A unique identifier.
    ///   - version: The row version for optimistic locking.
    ///   - tier: The dope tier this diagram belongs to.
    ///   - projectUuid: The project identifier.
    ///   - instanceUuid: The instance identifier, if applicable.
    ///   - sessionUuid: The session identifier, if applicable.
    ///   - promptUuid: The prompt identifier, if applicable.
    ///   - code: The diagram code.
    ///   - name: The human-readable name.
    ///   - description: The description prose.
    ///   - gmccDiagramPath: Path to the diagram in the gmcc store, if any.
    ///   - dopeScopeCode: The dope scope this diagram reads/writes through.
    ///   - revision: The whole-tree content counter.
    ///   - createdAt: Creation timestamp in ISO 8601 format.
    ///   - updatedAt: Last update timestamp in ISO 8601 format.
    ///   - visibility: PRIVATE (default) or PUBLIC (SESSION tier only).
    init(
        uuid: String,
        version: Int64,
        tier: String,
        projectUuid: String,
        instanceUuid: String?,
        sessionUuid: String?,
        promptUuid: String?,
        code: String,
        name: String,
        description: String,
        gmccDiagramPath: String?,
        dopeScopeCode: String?,
        revision: Int64,
        createdAt: String,
        updatedAt: String,
        visibility: String = DiagramVisibility.private.rawValue
    ) {
        self.uuid = uuid
        self.version = version
        self.tier = tier
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.gmccDiagramPath = gmccDiagramPath
        self.dopeScopeCode = dopeScopeCode
        self.revision = revision
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, version, tier, projectUuid, instanceUuid, sessionUuid,
            promptUuid, code, name, description, gmccDiagramPath,
            dopeScopeCode, revision, visibility, createdAt, updatedAt
    }

    /// Creates a DiagramRow from JSON, defaulting `visibility` for pre-m0024 peers.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` if any required field is missing or malformed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        version = try c.decode(Int64.self, forKey: .version)
        tier = try c.decode(String.self, forKey: .tier)
        projectUuid = try c.decode(String.self, forKey: .projectUuid)
        instanceUuid = try c.decodeIfPresent(String.self, forKey: .instanceUuid)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid)
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        gmccDiagramPath = try c.decodeIfPresent(String.self, forKey: .gmccDiagramPath)
        dopeScopeCode = try c.decodeIfPresent(String.self, forKey: .dopeScopeCode)
        revision = try c.decode(Int64.self, forKey: .revision)
        visibility =
            try c.decodeIfPresent(String.self, forKey: .visibility)
            ?? DiagramVisibility.private.rawValue
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}
