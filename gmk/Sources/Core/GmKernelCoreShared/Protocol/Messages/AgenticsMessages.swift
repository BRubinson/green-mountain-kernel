import Foundation

// Agentics wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

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

// MARK: - CLARIFY_*

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

/// Insert a user-facing question while the summary is `building`.
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

/// Insert an internal clarification note: the agent's own record of
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

// MARK: - CARE_PACKAGE_*

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

// MARK: - ARCH_*

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

// MARK: - ARCH_OPTION_* (the architect pen inversion)

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

// MARK: - BOT_* (the daemon-held workflow state machine)

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
    /// Compiled-in instruction text for (variant, phase).
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

// MARK: - EXPLORE_* (literal per-agent summaries)

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

// MARK: - REVIEW_*

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

// MARK: - BRIEFING_*

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
