import Foundation

// Project wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

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

// MARK: - SESSION_RESOLVE / INSTANCE_CURRENT_SESSION

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
