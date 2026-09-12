import Foundation

// Typed read-side DTOs — the row shapes GMVibes and gmcc_hook render from.
// Same lowering conventions as Messages.swift.

// MARK: - Project

public struct ProjectRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let gitRepoName: String
    public let code: String
    public let name: String
    public let ckfsRelativeStoragePath: String
    /// BASE_DOPED_BRANCH — the branch whose SESSION_INSTANCE dope scope may
    /// promote into this project's BASE_PROJECT scope. Defaults to "main"
    /// (m0011 backfills every existing row); user-configured through
    /// PROJECT_UPDATE or GMVibes' project view.
    ///
    /// Defaulted rather than Optional so a stale peer that omits the key
    /// still decodes — the additive-OPTIONAL wire convention.
    public let primaryProjectBranch: String
    public let createdAt: String
    public let updatedAt: String

    public init(
        uuid: String,
        version: Int64,
        gitRepoName: String,
        code: String,
        name: String,
        ckfsRelativeStoragePath: String,
        primaryProjectBranch: String = "main",
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.gitRepoName = gitRepoName
        self.code = code
        self.name = name
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.primaryProjectBranch = primaryProjectBranch
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Hand-rolled so an absent `primary_project_branch` decodes to "main"
    /// instead of throwing: GMVibes and any pinned Kit may still be sending
    /// the pre-m0011 shape.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uuid = try c.decode(String.self, forKey: .uuid)
        self.version = try c.decode(Int64.self, forKey: .version)
        self.gitRepoName = try c.decode(String.self, forKey: .gitRepoName)
        self.code = try c.decode(String.self, forKey: .code)
        self.name = try c.decode(String.self, forKey: .name)
        self.ckfsRelativeStoragePath =
            try c.decode(String.self, forKey: .ckfsRelativeStoragePath)
        self.primaryProjectBranch =
            try c.decodeIfPresent(String.self, forKey: .primaryProjectBranch) ?? "main"
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - Instance

public struct InstanceRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let projectUuid: String
    public let code: String
    public let name: String
    public let absoluteFileSystemPath: String
    public let ckfsRelativeStoragePath: String
    public let createdAt: String
    public let updatedAt: String

    public init(
        uuid: String,
        version: Int64,
        projectUuid: String,
        code: String,
        name: String,
        absoluteFileSystemPath: String,
        ckfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.projectUuid = projectUuid
        self.code = code
        self.name = name
        self.absoluteFileSystemPath = absoluteFileSystemPath
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
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
public struct SessionStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let instanceUuid: String
    public let code: String
    public let name: String
    public let ckfsRelativeStoragePath: String
    public let createdAt: String
    public let updatedAt: String
    public let lastActivityAt: String

    public init(
        uuid: String,
        version: Int64,
        instanceUuid: String,
        code: String,
        name: String,
        ckfsRelativeStoragePath: String,
        createdAt: String,
        updatedAt: String,
        lastActivityAt: String
    ) {
        self.uuid = uuid
        self.version = version
        self.instanceUuid = instanceUuid
        self.code = code
        self.name = name
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
    }
}

public struct SessionRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let code: String
    public let name: String
    public let backstory: String
    public let goal: String
    public let createdAt: String
    public let updatedAt: String
    /// v21-era additive OPTIONAL field: this session's activation registry —
    /// one entry per running Claude Code instance (client key → prompt).
    /// Several prompts are routinely active at once, so this is a LIST, never
    /// a single pointer. nil from a pre-v21 peer.
    public let activations: [PromptActivationRow]?

    public init(
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

/// One activation claim (v21): a running Claude Code instance (client_key,
/// resolved from process ancestry by gm) is working prompt X. Claimed by
/// set-status implementing, released at done.
public struct PromptActivationRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let sessionUuid: String
    public let promptUuid: String
    public let clientKey: String
    public let createdAt: String

    public init(
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

public struct PromptRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let sessionUuid: String
    public let seq: Int64
    public let code: String
    public let name: String
    public let backstory: String
    public let goal: String
    public let detail: String
    public let command: String
    public let status: String
    public let ckfsRelativeStoragePath: String
    public let createdAt: String
    public let updatedAt: String

    public var promptStatus: PromptStatus? { PromptStatus(rawValue: status) }

    public init(
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
        ckfsRelativeStoragePath: String,
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
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Lightweight prompt listing shape (replaces reading the session_data
/// prompts: list). Carries its parent session uuid so whole-db listings
/// (PROMPT_LIST with no session filter) stay interpretable — seq is only
/// unique per session.
public struct PromptStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let sessionUuid: String
    public let seq: Int64
    public let code: String
    public let name: String
    public let status: String
    public let version: Int64
    public let ckfsRelativeStoragePath: String
    /// Present only when PROMPT_LIST was called with `with_reports` — nested
    /// so "not requested" (nil) and "requested, none exists" (present with
    /// nil members) stay distinguishable.
    public let reports: PromptReportsStub?
    public let createdAt: String
    public let updatedAt: String

    public init(
        uuid: String,
        sessionUuid: String,
        seq: Int64,
        code: String,
        name: String,
        status: String,
        version: Int64,
        ckfsRelativeStoragePath: String,
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
        self.ckfsRelativeStoragePath = ckfsRelativeStoragePath
        self.reports = reports
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The PROMPT_LIST `with_reports` enrichment block: one summary stub per
/// report machine. A nil member means that summary was never opened.
public struct PromptReportsStub: Codable, Hashable, Sendable {
    public let clarification: ClarificationReportStub?
    public let architecture: ArchitectureReportStub?
    public let exploration: ExplorationReportStub?
    public let review: ReviewReportStub?

    public init(
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
public struct ExplorationReportStub: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let version: Int64
    public let status: String
    public let keyFileCount: Int
    public let findingCount: Int
    /// Findings under the read threshold (rating < 100).
    public let sub100FindingCount: Int
    /// Resume signal: >0 means the exploration stalled before ranking.
    public let unrankedFindingCount: Int

    public init(
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
public struct ReviewReportStub: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let version: Int64
    public let status: String
    public let verdict: String?
    public let findingCount: Int
    public let sub100FindingCount: Int
    public let unrankedFindingCount: Int
    /// Resume signal for the fix loop: unresolved findings.
    public let openFindingCount: Int

    public init(
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
public struct ClarificationReportStub: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let version: Int64
    public let status: String
    public let questionCount: Int
    /// Resume signal: >0 means the clarification stalled mid-answering.
    public let openQuestionCount: Int
    /// m0025: internal notes replace the retired summary text fields.
    public let noteCount: Int
    /// m0025: whether a ready care package exists (the clarified intent).
    public let carePackageReady: Bool

    public init(
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
public struct ArchitectureReportStub: Codable, Hashable, Sendable {
    public let summaryUuid: String
    public let version: Int64
    public let status: String
    public let persistenceChangeCount: Int
    public let generalChangeCount: Int

    public init(
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
public struct SearchHit: Codable, Hashable, Sendable {
    /// Raw kind string (same forward-compat rule as event kinds/error codes).
    public let kind: String
    /// The matched row's own uuid.
    public let subjectUuid: String
    public let promptUuid: String
    public let promptSeq: Int64
    public let promptName: String
    public let promptStatus: String
    public let sessionUuid: String
    public let sessionCode: String
    /// Short label per kind: prompt name / question / file path / "architecture summary".
    public let title: String
    /// Bounded snippet from the best-matching column.
    public let excerpt: String
    /// bm25-derived; negative, smaller = better; comparable WITHIN a kind only.
    public let score: Double

    public init(
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

public struct ArtifactRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let promptUuid: String
    public let filePath: String
    public let note: String?
    public let createdAt: String

    public init(uuid: String, promptUuid: String, filePath: String, note: String?, createdAt: String) {
        self.uuid = uuid
        self.promptUuid = promptUuid
        self.filePath = filePath
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - File change

public struct ChangeRangeRow: Codable, Hashable, Sendable {
    public let lineStart: Int
    public let lineEnd: Int

    public init(lineStart: Int, lineEnd: Int) {
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

public struct FileChangeRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let sessionUuid: String
    public let promptUuid: String?
    public let relativePath: String
    public let changeKind: String
    /// Attribution axis (all OPTIONAL — additive decode both ways).
    public let agentId: String?
    public let agentName: String?
    /// Server-stamped from the attributed prompt's active bot_workflow.
    public let workflowPhase: String?
    /// `FileChangeOrigin` — provenance honesty (defaulted 'hook'). Rows
    /// written under a wider vocabulary keep their stored value.
    public let origin: String?
    /// The captured tool call. claudeTurnId is Claude Code's TURN id (payload
    /// field `prompt_id`) and is NOT a gmcc prompt uuid.
    public let claudeSessionId: String?
    public let claudeTurnId: String?
    public let toolUseId: String?
    public let toolName: String?
    public let agentType: String?
    public let permissionMode: String?
    public let durationMs: Int?
    public let transcriptPath: String?
    /// The authoritative link to the identity that made the change; `agentId`
    /// above is the denormalized form for queries that do not want the join.
    /// NULL for a PRIMARY write — the primary carries no agent_id at all, and
    /// that absence is the primary/subagent discriminator.
    public let agentRegistrationUuid: String?
    public let createdAt: String
    public let ranges: [ChangeRangeRow]

    public init(
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
/// The identity half (agentType, the Claude ids, the resolved session and
/// prompt) comes from the SubagentStart payload; the authority half (role,
/// methodology, workflowPhase) comes from the spawner's AGENT_REGISTER. Each
/// half is written independently and either may arrive first, so any field
/// can legitimately be nil.
///
/// NOT an agent_briefing: a briefing answers "what refs did this agent get"
/// and is keyed per (prompt, step), which cannot hold four same-typed
/// explorers — the exact case this row exists for.
public struct AgentRegistrationRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    /// Opaque, never parsed.
    public let agentId: String
    public let claudeSessionId: String?
    public let claudeTurnId: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    /// The payload's LABEL for the agent, never authoritative: it is
    /// overloaded by spawn shape — a plain subagent reports its
    /// subagent_type, a bare workflow agent the literal workflow-subagent, a
    /// named teammate its NAME.
    public let agentType: String?
    public let role: String?
    public let methodology: String?
    public let workflowPhase: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
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
public struct KbiteRef: Codable, Hashable, Sendable {
    public let uuid: String
    public let code: String

    public init(uuid: String, code: String) {
        self.uuid = uuid
        self.code = code
    }
}

public struct KbiteRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let code: String
    public let createdAt: String
    public let updatedAt: String

    public init(uuid: String, version: Int64, code: String, createdAt: String, updatedAt: String) {
        self.uuid = uuid
        self.version = version
        self.code = code
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A consumed source within a kbite, carrying its file stubs. resource_summary
/// is the full chewed analysis body — the per-resource synthesis.
public struct KbiteResourceRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let kbiteUuid: String
    public let resourceName: String
    public let resourceSummary: String
    public let resourceType: String
    public let resourceTrust: Int
    public let files: [KbiteResourceFileStub]

    public init(
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
public struct KbiteResourceFileStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let resourceFileName: String
    public let resourceFileSummary: String
    public let hasContent: Bool

    public init(uuid: String, resourceFileName: String, resourceFileSummary: String, hasContent: Bool) {
        self.uuid = uuid
        self.resourceFileName = resourceFileName
        self.resourceFileSummary = resourceFileSummary
        self.hasContent = hasContent
    }
}

/// Full file row including content (nil for images/binaries the filesystem
/// keeps raw).
public struct KbiteResourceFileRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let kbiteResourceUuid: String
    public let resourceFileName: String
    public let resourceFileSummary: String
    public let resourceFileContent: String?
    public let createdAt: String

    public init(
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
public struct KbiteSearchHit: Codable, Hashable, Sendable {
    public let kbiteCode: String
    public let kbiteUuid: String
    public let resourceName: String
    public let fileUuid: String
    public let fileName: String
    public let fileSummary: String
    public let matchedKeywords: [String]
    public let score: Double

    public init(
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

public struct ChangeSummary: Codable, Hashable, Sendable {
    public let changeCount: Int
    public let distinctFiles: Int
    public let totalLineSpan: Int

    public init(changeCount: Int, distinctFiles: Int, totalLineSpan: Int) {
        self.changeCount = changeCount
        self.distinctFiles = distinctFiles
        self.totalLineSpan = totalLineSpan
    }
}

public struct PromptChangeSummary: Codable, Hashable, Sendable {
    /// nil = changes not attributed to any prompt.
    public let promptUuid: String?
    public let summary: ChangeSummary

    public init(promptUuid: String?, summary: ChangeSummary) {
        self.promptUuid = promptUuid
        self.summary = summary
    }
}

// MARK: - Clarification (m0025 split)

public struct ClarificationSummaryRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let promptUuid: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String

    public var clarificationStatus: ClarificationStatus? { ClarificationStatus(rawValue: status) }

    public init(
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
public struct ClarificationQuestionRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let clarificationSummaryUuid: String
    public let seq: Int64
    public let question: String
    public let status: String
    public let answerText: String?
    public let agentId: String?
    public let agentName: String?
    public let options: [ClarificationOptionRow]
    public let selectedOptionUuids: [String]

    public init(
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

public struct ClarificationOptionRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let seq: Int64
    public let body: String

    public init(uuid: String, seq: Int64, body: String) {
        self.uuid = uuid
        self.seq = seq
        self.body = body
    }
}

/// An agent-authored internal note clarifying something that confused
/// exploration or the clarifier itself. weight uses the finding_rating
/// polarity: 0 = critical, 999 = ignore.
public struct ClarificationNoteRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let clarificationSummaryUuid: String
    public let body: String
    public let confusedEntityUuid: String?
    public let confusedEntityType: String?
    public let weight: Int?
    public let questionUuid: String?
    public let agentId: String?
    public let agentName: String?

    public init(
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
public struct CarePackageRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let clarificationSummaryUuid: String
    public let clarifiedIntent: String
    public let status: String
    public let dopeScopeUuid: String?
    public let dopeScopeRevision: Int64?
    public let dopeRefs: [CarePackageDopeRefRow]
    public let kbiteRefs: [CarePackageKbiteRefRow]
    public let explorationRefs: [CarePackageExplorationRefRow]
    public let createdAt: String
    public let updatedAt: String

    public init(
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

public struct CarePackageDopeRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let dopeCode: String
    public let note: String?
    public let seq: Int

    public init(uuid: String, dopeCode: String, note: String?, seq: Int) {
        self.uuid = uuid
        self.dopeCode = dopeCode
        self.note = note
        self.seq = seq
    }
}

public struct CarePackageKbiteRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let kbiteResourceFileUuid: String
    public let brief: String?
    public let seq: Int

    public init(uuid: String, kbiteResourceFileUuid: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.kbiteResourceFileUuid = kbiteResourceFileUuid
        self.brief = brief
        self.seq = seq
    }
}

/// A curated COPY of exploration output (never re-explored); the soft
/// provenance ref survives source pruning via SET NULL.
public struct CarePackageExplorationRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let curatedTitle: String
    public let curatedBody: String
    public let filePath: String?
    public let sourceFindingUuid: String?
    public let seq: Int

    public init(
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

public struct ArchitectureSummaryRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let promptUuid: String
    public let body: String
    public let status: String
    /// m0025: why the selected option won (empty when no options flow ran).
    public let decisionRationale: String?
    public let createdAt: String
    public let updatedAt: String

    public var architectureStatus: ArchitectureStatus? { ArchitectureStatus(rawValue: status) }

    public init(
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
public struct ChangeImplementationState: Codable, Hashable, Sendable {
    public let fileChangeCount: Int
    public let firstChangedAt: String?
    public let lastChangedAt: String?

    public init(fileChangeCount: Int, firstChangedAt: String?, lastChangedAt: String?) {
        self.fileChangeCount = fileChangeCount
        self.firstChangedAt = firstChangedAt
        self.lastChangedAt = lastChangedAt
    }
}

public struct ArchPersistenceFieldChangeRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let seq: Int64
    public let fieldName: String
    public let changeReason: String
    public let changePurpose: String
    public let dataType: String
    public let nullable: Bool
    public let isForeignKey: Bool
    public let fkTarget: String?
    public let isIndexed: Bool
    /// m0025: add|modify|rename|delete.
    public let changeKind: String?
    /// m0025: old field name when changeKind == rename.
    public let renamedFrom: String?
    /// m0025: domain.entity.property dot-path CODE (ghost-legal).
    public let dopePropertyRef: String?

    public init(
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

public struct ArchPersistenceChangeRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let seq: Int64
    public let className: String
    public let filePath: String
    public let reasonBrief: String
    /// m0025: add|modify|rename|delete — negative changes are first-class.
    public let changeKind: String?
    /// m0025: domain.entity dot-path CODE (ghost-legal), never a uuid.
    public let dopeRef: String?
    public let fields: [ArchPersistenceFieldChangeRow]
    public let implementation: ChangeImplementationState

    public init(
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
public struct ArchitectureOptionRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let architectureSummaryUuid: String
    public let agentName: String
    public let agentId: String?
    public let body: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String

    public init(
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
public struct BotWorkflowRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let sessionUuid: String
    public let promptUuid: String
    public let variant: String
    public let status: String
    public let clientKey: String?
    public let lastServedPhase: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
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

public struct ArchGeneralChangeRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let seq: Int64
    public let filePath: String
    public let className: String?
    public let reasonBrief: String
    public let changeDepth: String
    public let changeCode: String
    public let implementation: ChangeImplementationState

    public init(
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
public struct UnplannedChangeRow: Codable, Hashable, Sendable {
    public let path: String
    public let changeCount: Int
    public let firstChangedAt: String
    public let lastChangedAt: String

    public init(path: String, changeCount: Int, firstChangedAt: String, lastChangedAt: String) {
        self.path = path
        self.changeCount = changeCount
        self.firstChangedAt = firstChangedAt
        self.lastChangedAt = lastChangedAt
    }
}

// MARK: - Exploration (v9)

public struct ExplorationSummaryRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let promptUuid: String
    /// m0025: aggressive|conservative|pragmatic|alternative|general|synthesis.
    /// The synthesis-type row is the prompt-level seal/synthesis home.
    public let agentType: String
    public let agentId: String?
    public let status: String
    public let overview: String
    public let createdAt: String
    public let updatedAt: String

    public var explorationStatus: ExplorationStatus? { ExplorationStatus(rawValue: status) }

    public init(
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
/// doper agent assembles for a phase. The old body/dope_refs/kbite_refs TEXT
/// columns are gone — refs are typed child rows.
public struct AgentBriefingRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let sessionUuid: String
    /// nil = task-owned (a /gm_task run, no prompt row).
    public let promptUuid: String?
    public let briefingForStep: String
    public let status: String
    public let agentId: String?
    public let dopeScopeUuid: String?
    public let dopeScopeRevision: Int64?
    public let dopeRefs: [AgentBriefingDopeRefRow]
    public let kbiteRefs: [AgentBriefingKbiteRefRow]
    public let fileChangeRefs: [AgentBriefingFileChangeRefRow]
    public let createdAt: String
    public let updatedAt: String

    public init(
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
public struct AgentBriefingDopeRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let dopeCode: String
    public let brief: String?
    public let seq: Int

    public init(uuid: String, dopeCode: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.dopeCode = dopeCode
        self.brief = brief
        self.seq = seq
    }
}

public struct AgentBriefingKbiteRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let kbiteResourceFileUuid: String
    public let brief: String?
    public let seq: Int

    public init(uuid: String, kbiteResourceFileUuid: String, brief: String?, seq: Int) {
        self.uuid = uuid
        self.kbiteResourceFileUuid = kbiteResourceFileUuid
        self.brief = brief
        self.seq = seq
    }
}

public struct AgentBriefingFileChangeRefRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let fileChangeUuid: String
    public let seq: Int

    public init(uuid: String, fileChangeUuid: String, seq: Int) {
        self.uuid = uuid
        self.fileChangeUuid = fileChangeUuid
        self.seq = seq
    }
}

public struct ExplorationKeyFileRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let explorationSummaryUuid: String
    public let filePath: String

    public init(uuid: String, version: Int64, explorationSummaryUuid: String, filePath: String) {
        self.uuid = uuid
        self.version = version
        self.explorationSummaryUuid = explorationSummaryUuid
        self.filePath = filePath
    }
}

public struct ExplorationFindingRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let explorationSummaryUuid: String
    public let kind: String
    public let title: String
    public let body: String
    /// m0025: the merged key-file half of the finding/file pair.
    public let filePath: String?
    public let agentName: String
    public let agentId: String?
    /// nil = unranked (work-in-progress; blocks COMPLETE).
    public let findingRating: Int?

    public init(
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
public struct ExplorationFindingStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let kind: String
    public let title: String
    public let findingRating: Int?
    public let agentName: String

    public init(uuid: String, kind: String, title: String, findingRating: Int?, agentName: String) {
        self.uuid = uuid
        self.kind = kind
        self.title = title
        self.findingRating = findingRating
        self.agentName = agentName
    }
}

// MARK: - Review (v9)

public struct ReviewSummaryRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let promptUuid: String
    public let status: String
    public let verdict: String?
    public let overview: String
    /// m0025 agent_id sweep (additive optional).
    public let agentId: String?
    public let createdAt: String
    public let updatedAt: String

    public var reviewStatus: ReviewSummaryStatus? { ReviewSummaryStatus(rawValue: status) }

    public init(
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

public struct ReviewFindingRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let reviewSummaryUuid: String
    public let kind: String
    public let title: String
    public let body: String
    public let filePath: String?
    public let lineStart: Int?
    public let lineEnd: Int?
    public let agentName: String
    /// m0025 agent_id sweep (additive optional).
    public let agentId: String?
    public let findingRating: Int?
    public let status: String

    public init(
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
public struct ReviewFindingStub: Codable, Hashable, Sendable {
    public let uuid: String
    public let kind: String
    public let title: String
    public let findingRating: Int?
    public let agentName: String
    public let status: String

    public init(uuid: String, kind: String, title: String, findingRating: Int?, agentName: String, status: String) {
        self.uuid = uuid
        self.kind = kind
        self.title = title
        self.findingRating = findingRating
        self.agentName = agentName
        self.status = status
    }
}

public struct DopeScopeRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    /// m0013's chain-non-null tier ladder (mirrors DiagramRow): every tier
    /// fills its own FK and every ancestor's. project_uuid is ALWAYS present;
    /// the project tiers (BASE_PROJECT / PROJECT_ITEM) carry nothing below it.
    ///
    /// Defaulted in the memberwise init and decoded with decodeIfPresent so a
    /// pre-m0013 peer still decodes — the additive-OPTIONAL wire convention.
    public let projectUuid: String
    public let instanceUuid: String?
    /// nil for the two project tiers. Use `requireSessionUuid()` wherever a
    /// session is structurally required (the repo verbs, touchSession).
    public let sessionUuid: String?
    public let promptUuid: String?
    public let scopeType: String
    /// Soft delete (m0012/m0013). Reads deliberately do NOT filter on it.
    public let deletedOn: String?
    public let code: String
    public let name: String
    public let description: String
    /// The whole-tree content counter — IS the .doped.json version field.
    public let revision: Int64
    public let createdAt: String
    public let updatedAt: String

    public init(
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
    public init(from decoder: Decoder) throws {
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
    public var tier: DopeScopeType? { DopeScopeType(fromWire: scopeType) }

    /// Session-owned tiers always carry a session. The repo verbs, boot sync
    /// and touchSession are structurally session-only, so they assert here
    /// rather than silently no-op on a project-tier scope.
    public func requireSessionUuid() throws -> String {
        guard let sessionUuid else {
            throw StoreError.badRequest(
                detail: "scope \(uuid) is tier \(scopeType), which has no session; "
                      + "this operation is session-tier only")
        }
        return sessionUuid
    }
}

public struct DiagramRow: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let tier: String
    public let projectUuid: String
    public let instanceUuid: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    public let code: String
    public let name: String
    public let description: String
    public let gmccDiagramPath: String?
    /// Which dope scope this WHOLE diagram reads and writes through
    /// (m0016). A ghost-tolerant CODE, resolved at read time, restricted on
    /// write to the masking tiers.
    ///
    /// Distinct from the per-element diagram_dope_scope / diagram_dope_entity
    /// bindings: those answer "which node does this one shape point at",
    /// this answers "which scope is this canvas over". Both coexist.
    public let dopeScopeCode: String?
    /// The whole-tree content counter (bumpDiagramRevision; never the row's
    /// optimistic-lock version).
    public let revision: Int64
    /// PRIVATE (db-only) | PUBLIC (repo-serializable; SESSION tier only).
    /// Decodes absent as PRIVATE so pre-m0024 snapshots read unchanged.
    public let visibility: String
    public let createdAt: String
    public let updatedAt: String

    public init(
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

    public init(from decoder: Decoder) throws {
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
        visibility = try c.decodeIfPresent(String.self, forKey: .visibility)
            ?? DiagramVisibility.private.rawValue
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}
