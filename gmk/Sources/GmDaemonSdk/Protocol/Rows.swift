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
    /// promote into this project's BASE_PROJECT scope. Defaults to "main"
    /// (m0011 backfills every existing row); user-configured through
    /// PROJECT_UPDATE or GMVibes' project view.
    ///
    /// Defaulted rather than Optional so a stale peer that omits the key
    /// still decodes — the additive-OPTIONAL wire convention.
    let primaryProjectBranch: String
    let createdAt: String
    let updatedAt: String

    init(
        uuid: String,
        version: Int64,
        gitRepoName: String,
        code: String,
        name: String,
        gmfsRelativeStoragePath: String,
        primaryProjectBranch: String = "main",
        createdAt: String,
        updatedAt: String
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

    /// Hand-rolled so an absent `primary_project_branch` decodes to "main"
    /// instead of throwing: GMVibes and any pinned Kit may still be sending
    /// the pre-m0011 shape.
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
    /// Several prompts are routinely active at once, so this is a LIST, never
    /// a single pointer. nil from a pre-v21 peer.
    let activations: [PromptActivationRow]?

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
/// prompts: list). Carries its parent session uuid so whole-db listings
/// (PROMPT_LIST with no session filter) stay interpretable — seq is only
/// unique per session.
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

    init(
        uuid: String,
        sessionUuid: String,
        seq: Int64,
        code: String,
        name: String,
        status: String,
        version: Int64,
        gmfsRelativeStoragePath: String,
        reports: PromptReportsStub? = nil,
        createdAt: String,
        updatedAt: String
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
/// report machine. A nil member means that summary was never opened.
struct PromptReportsStub: Codable, Hashable, Sendable {
    let clarification: ClarificationReportStub?
    let architecture: ArchitectureReportStub?
    let exploration: ExplorationReportStub?
    let review: ReviewReportStub?

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

/// Clarification summary stub for the enrichment block. Carries the summary
/// version so the caller can mutate immediately without a confirming fetch.
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

/// One ranked SEARCH result. Stubs-not-content discipline: `excerpt` is a
/// bounded FTS5 snippet, never a full body; full prompt lineage rides along
/// so the caller never needs a follow-up fetch to know what it found.
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
    /// `FileChangeOrigin` — provenance honesty (defaulted 'hook'). Rows
    /// written under a wider vocabulary keep their stored value.
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
    /// NULL for a PRIMARY write — the primary carries no agent_id at all, and
    /// that absence is the primary/subagent discriminator.
    let agentRegistrationUuid: String?
    let createdAt: String
    let ranges: [ChangeRangeRow]

    init(
        uuid: String,
        sessionUuid: String,
        promptUuid: String?,
        relativePath: String,
        changeKind: String,
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
        agentRegistrationUuid: String? = nil,
        createdAt: String,
        ranges: [ChangeRangeRow]
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

    init(
        uuid: String,
        version: Int64,
        agentId: String,
        claudeSessionId: String? = nil,
        claudeTurnId: String? = nil,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        agentType: String? = nil,
        role: String? = nil,
        methodology: String? = nil,
        workflowPhase: String? = nil,
        createdAt: String,
        updatedAt: String
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

/// A user-facing clarification question. The selected answer(s) live in
/// `selectedOptionUuids` (junction rows) — empty + non-nil answerText means
/// the user typed a free answer; both may coexist (select AND elaborate).
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

    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        body: String,
        status: String,
        decisionRationale: String? = nil,
        createdAt: String,
        updatedAt: String
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

    init(
        uuid: String,
        seq: Int64,
        className: String,
        filePath: String,
        reasonBrief: String,
        changeKind: String? = nil,
        dopeRef: String? = nil,
        fields: [ArchPersistenceFieldChangeRow],
        implementation: ChangeImplementationState
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
/// the first architect pen). Only the SELECTED option expands into change
/// rows; losers persist as feature-graft offers.
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

/// The daemon-held workflow state machine row. Phase is DERIVED from db
/// evidence at every BOT_NEXT; lastServedPhase is observability only.
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
    /// The synthesis-type row is the prompt-level seal/synthesis home.
    let agentType: String
    let agentId: String?
    let status: String
    let overview: String
    let createdAt: String
    let updatedAt: String

    var explorationStatus: ExplorationStatus? { ExplorationStatus(rawValue: status) }

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
/// briefer agent assembles for a phase. The old body/dope_refs/kbite_refs TEXT
/// columns are gone — refs are typed child rows.
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

    init(
        uuid: String,
        version: Int64,
        promptUuid: String,
        status: String,
        verdict: String?,
        overview: String,
        agentId: String? = nil,
        createdAt: String,
        updatedAt: String
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
        agentId: String? = nil,
        findingRating: Int?,
        status: String
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
    /// nil for the two project tiers. Use `requireSessionUuid()` wherever a
    /// session is structurally required (the repo verbs, touchSession).
    let sessionUuid: String?
    let promptUuid: String?
    let scopeType: String
    /// Soft delete (m0012/m0013). Reads deliberately do NOT filter on it.
    let deletedOn: String?
    let code: String
    let name: String
    let description: String
    /// The whole-tree content counter — IS the .doped.json version field.
    let revision: Int64
    let createdAt: String
    let updatedAt: String

    init(
        uuid: String,
        version: Int64,
        projectUuid: String = "",
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
        updatedAt: String
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

    /// Tolerant decode: a pre-m0013 peer omits the ladder columns entirely.
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

    /// Session-owned tiers always carry a session. The repo verbs, boot sync
    /// and touchSession are structurally session-only, so they assert here
    /// rather than silently no-op on a project-tier scope.
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
    /// (m0016). A ghost-tolerant CODE, resolved at read time, restricted on
    /// write to the masking tiers.
    ///
    /// Distinct from the per-element diagram_dope_scope / diagram_dope_entity
    /// bindings: those answer "which node does this one shape point at",
    /// this answers "which scope is this canvas over". Both coexist.
    let dopeScopeCode: String?
    /// The whole-tree content counter (bumpDiagramRevision; never the row's
    /// optimistic-lock version).
    let revision: Int64
    /// PRIVATE (db-only) | PUBLIC (repo-serializable; SESSION tier only).
    /// Decodes absent as PRIVATE so pre-m0024 snapshots read unchanged.
    let visibility: String
    let createdAt: String
    let updatedAt: String

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
        visibility: String = DiagramVisibility.private.rawValue,
        createdAt: String,
        updatedAt: String
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
