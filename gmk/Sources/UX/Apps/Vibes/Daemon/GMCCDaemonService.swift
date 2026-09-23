import Foundation

/// The single off-main boundary for all daemon verb traffic.
///
/// Both transports conform to `GmVerbCaller`, so `adopt(inProcess:)` swaps the socket for the
/// in-process caller without touching a wrapper here or any UI source behind it.
/// The queue is load-bearing on BOTH: `DaemonClient` is blocking POSIX I/O, and in-process the
/// verb layer is SYNCHRONOUS, so handler, store boundary and SQLite write would run on the
/// caller's turn and stall MainActor. The probe client has autostart OFF so health checks
/// report true daemon state; `startDaemon()` is the app's only autostart path.
actor GMCCDaemonService {
    static let shared = GMCCDaemonService()

    /// The socket transport.
    ///
    /// Non-nil in CLIENT mode only — in-process there is no file descriptor,
    /// so there is nothing to redial and nothing to close. ONE object,
    /// referenced twice: `caller` is what verbs go through and `socketClient`
    /// is what the redial guard needs. Constructing two would give the app two
    /// connections and make the guard clear a descriptor the failing call never
    /// used.
    private var socketClient: DaemonClient?
    private var caller: any GmVerbCaller
    private let queue = DispatchQueue(label: "gmvibes.daemon.client", qos: .userInitiated)

    /// Creates a daemon service with a socket transport client.
    init() {
        let client = DaemonClient(clientName: "gmvibes", autostart: false)
        self.socketClient = client
        self.caller = client
    }

    /// Switch to the in-process transport.
    ///
    /// Called ONCE, by `GMVibesServices`, after arbitration finds this process
    /// holds the store. Adoption rather than injection at init because `shared`
    /// is a static singleton built eagerly, while arbitration happens later
    /// inside `App.init()`. A second call is a bug — two adoptions means two
    /// arbitrations, which means something ran the ownership dance twice.
    ///
    /// - Parameter newCaller: The in-process caller to replace the socket client.
    func adopt(inProcess newCaller: any GmVerbCaller) {
        assert(socketClient != nil, "adopt(inProcess:) called twice")
        socketClient?.close()
        socketClient = nil
        caller = newCaller
    }

    nonisolated static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.binDaemon.path)
    }

    /// Executes a verb body on the dispatch queue with error recovery.
    ///
    /// On transport failure, closes the socket client to force redialing on the next call.
    /// - Parameter body: A closure that executes a verb call on the caller.
    /// - Returns: The result of the verb execution.
    /// - Throws: `DaemonError` wrapping any error from the verb body.
    private func perform<T: Sendable>(
        _ body: @escaping @Sendable (any GmVerbCaller) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [caller, socketClient] in
                do {
                    continuation.resume(returning: try body(caller))
                } catch {
                    // A transport-level failure leaves a dead fd cached inside
                    // DaemonClient (nothing closes it on a thrown roundTrip),
                    // and the next call would skip redialing forever. Force a
                    // fresh dial; a server-reported domain error means the
                    // connection itself is healthy.
                    //
                    // Guarded on the SOCKET client: in-process there is no fd
                    // to go stale, and `GmVerbCaller` has no `close()`.
                    if let socketClient, let clientError = error as? DaemonClientError {
                        switch clientError {
                        case .wire, .unreachable, .protocolMismatch: socketClient.close()
                        case .server: break
                        }
                    }
                    continuation.resume(throwing: DaemonError(error))
                }
            }
        }
    }

    // MARK: - Infra

    /// Pings the daemon to check connectivity.
    /// - Returns: The ping response.
    /// - Throws: `DaemonError` on connection failure.
    func ping() async throws -> PingResponse { try await perform { try $0.ping() } }

    /// Fetches the daemon's current status.
    /// - Returns: The status response.
    /// - Throws: `DaemonError` on connection failure.
    func status() async throws -> StatusResponse { try await perform { try $0.status() } }

    /// Spawns the daemon or returns its local ping status.
    ///
    /// The only call site permitted to spawn the daemon. In writer mode, returns a local
    /// ping result instead since the daemon is already running in this process.
    /// - Returns: The ping response from the launched or local daemon.
    /// - Throws: `DaemonError` on connection or spawn failure.
    func startDaemon() async throws -> PingResponse {
        guard socketClient != nil else {
            return try await ping()
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let launcher = DaemonClient(clientName: "gmvibes-launch", autostart: true)
                do {
                    continuation.resume(returning: try launcher.ping())
                } catch {
                    continuation.resume(throwing: DaemonError(error))
                }
                launcher.close()
            }
        }
    }

    // MARK: - Listing

    /// Lists all projects.
    /// - Returns: An array of project rows.
    /// - Throws: `DaemonError` on connection failure.
    func listProjects() async throws -> [ProjectRow] {
        try await perform { try $0.listProjects().projects }
    }

    /// Lists instances, optionally filtered by project.
    /// - Parameter projectUuid: The project UUID to filter by, or nil for all instances.
    /// - Returns: An array of instance rows.
    /// - Throws: `DaemonError` on connection failure.
    func listInstances(projectUuid: String? = nil) async throws -> [InstanceRow] {
        let uuid = Self.normalized(projectUuid)
        return try await perform { try $0.listInstances(InstanceListRequest(projectUuid: uuid)).instances }
    }

    /// Lists sessions, optionally filtered by instance.
    /// - Parameter instanceUuid: The instance UUID to filter by, or nil for all sessions.
    /// - Returns: An array of session stubs.
    /// - Throws: `DaemonError` on connection failure.
    func listSessions(instanceUuid: String? = nil) async throws -> [SessionStub] {
        let uuid = Self.normalized(instanceUuid)
        return try await perform { try $0.listSessions(SessionListRequest(instanceUuid: uuid)).sessions }
    }

    // MARK: - Catalog search

    /// Searches the catalog by query.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - projectUuid: The project UUID to search within, or nil for all projects.
    ///   - limit: The maximum number of results, or nil for default limit.
    /// - Returns: The catalog search response.
    /// - Throws: `DaemonError` on connection failure.
    func searchCatalog(
        query: String,
        projectUuid: String? = nil,
        limit: Int? = nil
    ) async throws
        -> CatalogSearchResponse
    {
        let uuid = Self.normalized(projectUuid)
        return try await perform {
            try $0.searchCatalog(CatalogSearchRequest(query: query, projectUuid: uuid, limit: limit))
        }
    }

    // MARK: - Full-text search (v8)

    /// Searches prompts, clarifications and architecture by full-text query.
    ///
    /// An empty kind set is sent as nil, which the daemon reads as "every kind".
    /// - Parameters:
    ///   - query: The FTS5 search query string.
    ///   - sessionUuid: The session UUID to search within, or nil for current session.
    ///   - kinds: The search kinds to include, or nil for all kinds.
    ///   - limit: The maximum number of results, or nil for default limit.
    /// - Returns: An array of search hits.
    /// - Throws: `DaemonError` on connection failure.
    func search(
        query: String,
        sessionUuid: String? = nil,
        kinds: [SearchKind]? = nil,
        limit: Int? = nil
    ) async throws -> [SearchHit] {
        let uuid = Self.normalized(sessionUuid)
        let kindFilter = (kinds?.isEmpty ?? true) ? nil : kinds
        return try await perform {
            try $0.search(SearchRequest(query: query, sessionUuid: uuid, kinds: kindFilter, limit: limit)).hits
        }
    }

    // MARK: - Session

    /// Fetches the session by UUID.
    /// - Parameter sessionUuid: The session UUID.
    /// - Returns: The session response.
    /// - Throws: `DaemonError` on connection failure.
    func getSession(sessionUuid: String) async throws -> SessionGetResponse {
        let uuid = Self.normalized(sessionUuid)
        return try await perform { try $0.getSession(SessionGetRequest(sessionUuid: uuid)) }
    }

    /// Updates a project's mutable fields.
    ///
    /// The only project-level mutation. The request's optional fields mean an all-nil body
    /// is EMPTY_UPDATE server-side, so callers must have something to change.
    /// - Parameter request: The update request with normalized project UUID.
    /// - Returns: The updated project row.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func updateProject(_ request: ProjectUpdateRequest) async throws -> ProjectRow {
        let req = ProjectUpdateRequest(
            projectUuid: Self.normalized(request.projectUuid),
            expectedVersion: request.expectedVersion,
            primaryProjectBranch: request.primaryProjectBranch
        )
        return try await perform { try $0.updateProject(req).project }
    }

    /// Updates a session's name, backstory or goal.
    /// - Parameter request: The update request with normalized session UUID.
    /// - Returns: The updated session row.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func updateSession(_ request: SessionUpdateRequest) async throws -> SessionRow {
        let req = SessionUpdateRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            expectedVersion: request.expectedVersion,
            name: request.name,
            backstory: request.backstory,
            goal: request.goal
        )
        return try await perform { try $0.updateSession(req) }
    }

    // MARK: - Prompt

    /// Lists prompts for a session, optionally with clarification and architecture summaries.
    ///
    /// With `withReports: true`, enriches each stub with clarification/architecture summary
    /// stubs — one call replaces the per-prompt CLARIFY_GET/ARCH_GET fan-out.
    /// - Parameters:
    ///   - sessionUuid: The session UUID.
    ///   - withReports: Whether to include clarification and architecture summaries.
    /// - Returns: An array of prompt stubs.
    /// - Throws: `DaemonError` on connection failure.
    func listPrompts(sessionUuid: String, withReports: Bool = false) async throws -> [PromptStub] {
        let uuid = Self.normalized(sessionUuid)
        return try await perform {
            try $0.listPrompts(
                PromptListRequest(
                    sessionUuid: uuid,
                    withReports: withReports ? true : nil
                )
            )
            .prompts
        }
    }

    /// Fetches the prompt by UUID.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: The prompt response.
    /// - Throws: `DaemonError` on connection failure.
    func getPrompt(promptUuid: String) async throws -> PromptGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.getPrompt(PromptGetRequest(promptUuid: uuid)) }
    }

    // Request-taking wrappers rebuild the request with normalized uuids — the
    // service boundary is the SINGLE place the uppercase-uuid trap is fixed,
    // and the mutation paths are exactly where a silent NOT_FOUND costs most.

    /// Creates a new prompt in a session.
    /// - Parameter request: The create request with normalized UUIDs.
    /// - Returns: The created prompt row.
    /// - Throws: `DaemonError` on connection failure.
    func createPrompt(_ request: PromptCreateRequest) async throws -> PromptRow {
        let req = PromptCreateRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            name: request.name,
            uuid: Self.normalized(request.uuid),
            code: request.code,
            backstory: request.backstory,
            goal: request.goal,
            detail: request.detail,
            command: request.command,
            gmfsRelativeStoragePath: request.gmfsRelativeStoragePath
        )
        return try await perform { try $0.createPrompt(req) }
    }

    /// Updates a prompt's backstory, goal or detail.
    /// - Parameter request: The update request with normalized prompt UUID.
    /// - Returns: The updated prompt row.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func updatePromptContent(_ request: PromptUpdateContentRequest) async throws -> PromptRow {
        let req = PromptUpdateContentRequest(
            promptUuid: Self.normalized(request.promptUuid),
            expectedVersion: request.expectedVersion,
            backstory: request.backstory,
            goal: request.goal,
            detail: request.detail
        )
        return try await perform { try $0.updatePromptContent(req) }
    }

    /// Updates a prompt's status.
    /// - Parameter request: The status update request with normalized prompt UUID.
    /// - Returns: The updated prompt row.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func setPromptStatus(_ request: PromptSetStatusRequest) async throws -> PromptRow {
        let req = PromptSetStatusRequest(
            promptUuid: Self.normalized(request.promptUuid),
            expectedVersion: request.expectedVersion,
            status: request.status
        )
        return try await perform { try $0.setPromptStatus(req) }
    }

    // MARK: - Clarification / architecture (v7, read-only)

    /// Fetches clarification data for a prompt.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: The clarification response.
    /// - Throws: `DaemonError` on connection failure.
    func clarification(promptUuid: String) async throws -> ClarifyGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.clarifyGet(ClarifyGetRequest(promptUuid: uuid)) }
    }

    /// Fetches architecture data for a prompt.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: The architecture response.
    /// - Throws: `DaemonError` on connection failure.
    func architecture(promptUuid: String) async throws -> ArchGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.archGet(ArchGetRequest(promptUuid: uuid)) }
    }

    // MARK: - Clarification answering (m0025, the app's ONLY report write)

    /// Answers a clarification question for a prompt.
    ///
    /// The one report-subsystem write the app is permitted. Callers must send both
    /// answer text and selected options — incomplete submissions delete orphaned rows.
    /// - Parameter request: The answer request with normalized UUIDs.
    /// - Returns: The updated clarification question row.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func clarifyAnswer(_ request: ClarifyAnswerRequest) async throws -> ClarificationQuestionRow {
        let req = ClarifyAnswerRequest(
            questionUuid: Self.normalized(request.questionUuid),
            expectedVersion: request.expectedVersion,
            answerText: request.answerText,
            selectedOptionUuids: request.selectedOptionUuids.map { $0.map(Self.normalized) },
            skip: request.skip
        )
        return try await perform { try $0.clarifyAnswer(req).question }
    }

    // MARK: - Bot workflow (m0025, read-only)

    /// Advances the workflow to the next phase.
    ///
    /// The app's read onto the workflow machine, stamping `last_served_phase` and
    /// emitting WORKFLOW_CHANGE. Never steals a live terminal session's claim.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: The next workflow step.
    /// - Throws: `DaemonError` on connection failure.
    func botNext(promptUuid: String) async throws -> BotNextResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.botNext(BotNextRequest(promptUuid: uuid)) }
    }

    // MARK: - Exploration / review (v9, read-only)

    /// Fetches a windowed or complete set of exploration findings.
    ///
    /// Partitioned by default: `full: false` returns [0,99] plus unranked rows. `full: true`
    /// returns the entire set.
    /// - Parameters:
    ///   - promptUuid: The prompt UUID.
    ///   - full: Whether to return all findings or a window; default is false.
    /// - Returns: The exploration response.
    /// - Throws: `DaemonError` on connection failure.
    func exploration(promptUuid: String, full: Bool = false) async throws -> ExploreGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.exploreGet(ExploreGetRequest(promptUuid: uuid, full: full)) }
    }

    /// Fetches review findings for a prompt.
    /// - Parameters:
    ///   - promptUuid: The prompt UUID.
    ///   - full: Whether to return all findings or a window; default is false.
    /// - Returns: The review response.
    /// - Throws: `DaemonError` on connection failure.
    func review(promptUuid: String, full: Bool = false) async throws -> ReviewGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.reviewGet(ReviewGetRequest(promptUuid: uuid, full: full)) }
    }

    // MARK: - Briefing (v21, read-only)

    /// Lists briefing steps for a prompt.
    ///
    /// The step vocabulary is registry-governed daemon-side. An empty list is normal.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: The briefing list response.
    /// - Throws: `DaemonError` on connection failure.
    func briefings(promptUuid: String) async throws -> BriefingListResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.briefingList(BriefingListRequest(promptUuid: uuid)) }
    }

    /// Fetches a briefing step with staleness and drift metadata.
    ///
    /// Per-row fetch for the staleness report; drift and ghost dot-paths computed at read time.
    /// - Parameter uuid: The briefing UUID.
    /// - Returns: The briefing response.
    /// - Throws: `DaemonError` on connection failure.
    func briefing(uuid: String) async throws -> BriefingGetResponse {
        let normalized = Self.normalized(uuid)
        return try await perform { try $0.briefingGet(BriefingGetRequest(briefingUuid: normalized)) }
    }

    // MARK: - Git state / paths (v7)

    /// Fetches the current session for an instance.
    /// - Parameter instanceUuid: The instance UUID.
    /// - Returns: The current session response.
    /// - Throws: `DaemonError` on connection failure.
    func instanceCurrentSession(instanceUuid: String) async throws -> InstanceCurrentSessionResponse {
        let uuid = Self.normalized(instanceUuid)
        return try await perform { try $0.instanceCurrentSession(InstanceCurrentSessionRequest(instanceUuid: uuid)) }
    }

    /// Fetches the filesystem paths used by the daemon.
    /// - Returns: The paths response.
    /// - Throws: `DaemonError` on connection failure.
    func paths() async throws -> PathsGetResponse {
        try await perform { try $0.pathsGet() }
    }

    // MARK: - File change / artifact

    /// Lists file changes for a session or prompt.
    /// - Parameter request: The list request with normalized UUIDs.
    /// - Returns: An array of file change rows.
    /// - Throws: `DaemonError` on connection failure.
    func listFileChanges(_ request: FileChangeListRequest) async throws -> [FileChangeRow] {
        let req = FileChangeListRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid),
            relativePath: request.relativePath,
            limit: request.limit
        )
        return try await perform { try $0.listFileChanges(req).changes }
    }

    /// Lists artifacts created during a prompt workflow.
    /// - Parameter promptUuid: The prompt UUID.
    /// - Returns: An array of artifact rows.
    /// - Throws: `DaemonError` on connection failure.
    func listArtifacts(promptUuid: String) async throws -> [ArtifactRow] {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.listArtifacts(ArtifactListRequest(promptUuid: uuid)).artifacts }
    }

    // MARK: - Kbite

    /// Lists kbites in a scope or all accessible kbites.
    /// - Parameters:
    ///   - scope: The kbite scope.
    ///   - ownerUuid: The owner UUID (ignored when `all: true`).
    ///   - all: Whether to return all accessible kbites; default is false.
    /// - Returns: An array of kbite references.
    /// - Throws: `DaemonError` on connection failure.
    func listKbites(scope: KbiteScope, ownerUuid: String, all: Bool = false) async throws -> [KbiteRef] {
        let uuid = Self.normalized(ownerUuid)
        // Server short-circuits scope resolution when all == true, so the
        // owner uuid is ignored in that mode.
        return try await perform {
            try $0.listKbites(KbiteListRequest(scope: scope, ownerUuid: uuid, all: all ? true : nil)).kbites
        }
    }

    /// Adds a kbite to a scope.
    /// - Parameters:
    ///   - scope: The kbite scope.
    ///   - ownerUuid: The owner UUID.
    ///   - code: The kbite code.
    /// - Returns: The add response.
    /// - Throws: `DaemonError` on connection failure.
    func addKbite(scope: KbiteScope, ownerUuid: String, code: String) async throws -> KbiteAddResponse {
        let uuid = Self.normalized(ownerUuid)
        return try await perform { try $0.addKbite(KbiteAddRequest(scope: scope, ownerUuid: uuid, code: code)) }
    }

    /// Removes a kbite from a scope.
    /// - Parameters:
    ///   - scope: The kbite scope.
    ///   - ownerUuid: The owner UUID.
    ///   - code: The kbite code.
    /// - Returns: The remove response.
    /// - Throws: `DaemonError` on connection failure.
    func removeKbite(scope: KbiteScope, ownerUuid: String, code: String) async throws -> KbiteRemoveResponse {
        let uuid = Self.normalized(ownerUuid)
        return try await perform { try $0.removeKbite(KbiteRemoveRequest(scope: scope, ownerUuid: uuid, code: code)) }
    }

    /// Searches kbites by full-text query.
    /// - Parameters:
    ///   - query: The FTS search query string.
    ///   - kbiteUuids: The kbite UUIDs to search within, or nil for all.
    ///   - limit: The maximum number of results, or nil for default limit.
    /// - Returns: An array of search hits.
    /// - Throws: `DaemonError` on connection failure.
    func searchKbites(query: String, kbiteUuids: [String]? = nil, limit: Int? = nil) async throws -> [KbiteSearchHit] {
        let uuids = kbiteUuids.map { $0.map(Self.normalized) }
        return try await perform {
            try $0.searchKbites(KbiteSearchRequest(query: query, kbiteUuids: uuids, limit: limit)).hits
        }
    }

    /// Fetches a kbite resource file.
    /// - Parameter fileUuid: The file UUID.
    /// - Returns: The kbite resource file row.
    /// - Throws: `DaemonError` on connection failure.
    func getKbiteFile(fileUuid: String) async throws -> KbiteResourceFileRow {
        let uuid = Self.normalized(fileUuid)
        return try await perform { try $0.getKbiteFile(KbiteFileGetRequest(fileUuid: uuid)).file }
    }

    // MARK: - Dope (wire v12, read + init only)

    // Exactly four wrappers, deliberately: v0 is read-only-plus-init, and the
    // narrow boundary is itself the enforcement against reaching for the
    // kit’s in-process Store+Dope/DopeRepoSandbox (the kit ships the
    // daemon's server side inside this binary — bypassing the single-writer
    // daemon is one import away and forbidden). The remaining unwrapped verbs
    // are a four-line copy each when a prompt legitimately needs them.

    /// Lists dope scopes available in a session or for a prompt.
    ///
    /// With `promptUuid`: only that prompt's PROMPT scopes. Without it: the session's
    /// SESSION_BASE scopes. Never both — callers wanting both ask twice.
    /// - Parameters:
    ///   - sessionUuid: The session UUID.
    ///   - promptUuid: The prompt UUID for prompt-scoped scopes, or nil for session scopes.
    /// - Returns: The dope list response.
    /// - Throws: `DaemonError` on connection failure.
    func dopeList(sessionUuid: String, promptUuid: String? = nil) async throws -> DopeListResponse {
        let req = DopeListRequest(
            sessionUuid: Self.normalized(sessionUuid),
            promptUuid: Self.normalized(promptUuid)
        )
        return try await perform { try $0.dopeList(req) }
    }

    /// Fetches a dope scope by code in a session or prompt.
    /// - Parameters:
    ///   - sessionUuid: The session UUID.
    ///   - promptUuid: The prompt UUID, or nil for session-scoped access.
    ///   - code: The scope code, or nil to return the default scope.
    /// - Returns: The dope scope response.
    /// - Throws: `DaemonError` on connection failure.
    func dopeGet(
        sessionUuid: String,
        promptUuid: String? = nil,
        code: String? = nil
    ) async throws -> DopeGetResponse {
        let req = DopeGetRequest(
            sessionUuid: Self.normalized(sessionUuid),
            promptUuid: Self.normalized(promptUuid),
            code: code
        )
        return try await perform { try $0.dopeGet(req) }
    }

    /// Creates a new dope scope in a session.
    /// - Parameter request: The init request with normalized UUIDs.
    /// - Returns: The created dope scope response.
    /// - Throws: `DaemonError` on connection failure.
    func dopeInit(_ request: DopeInitRequest) async throws -> DopeScopeResponse {
        let req = DopeInitRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            code: request.code,
            name: request.name,
            promptUuid: Self.normalized(request.promptUuid),
            description: request.description,
            cloneFromSessionBase: request.cloneFromSessionBase
        )
        return try await perform { try $0.dopeInit(req) }
    }

    /// Fetches a project-tier dope scope by code.
    ///
    /// The only door to the tree behind a project-tier diagram, since projects have no session.
    /// - Parameters:
    ///   - projectUuid: The project UUID.
    ///   - code: The scope code, or nil to return the default scope.
    /// - Returns: The dope scope response.
    /// - Throws: `DaemonError` on connection failure.
    func dopeGet(projectUuid: String, code: String? = nil) async throws -> DopeGetResponse {
        let req = DopeGetRequest(
            projectUuid: Self.normalized(projectUuid),
            code: code
        )
        return try await perform { try $0.dopeGet(req) }
    }

    /// Reads a dope scope's repository snapshot.
    /// - Parameter scopeUuid: The scope UUID.
    /// - Returns: The repository read response.
    /// - Throws: `DaemonError` on connection failure.
    func dopeReadRepo(scopeUuid: String) async throws -> DopeReadRepoResponse {
        let uuid = Self.normalized(scopeUuid)
        return try await perform { try $0.dopeReadRepo(DopeReadRepoRequest(scopeUuid: uuid)) }
    }

    // MARK: - Diagram

    /// Lists diagrams for one tier and owner — never a union.
    ///
    /// Per-prompt counts require N calls, one per prompt.
    /// - Parameter request: The list request with normalized UUIDs.
    /// - Returns: An array of diagram rows.
    /// - Throws: `DaemonError` on connection failure.
    func diagramList(_ request: DiagramListRequest) async throws -> [DiagramRow] {
        let req = DiagramListRequest(
            projectUuid: Self.normalized(request.projectUuid),
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid)
        )
        return try await perform { try $0.diagramList(req).diagrams }
    }

    /// Fetches a diagram by UUID.
    /// - Parameter diagramUuid: The diagram UUID.
    /// - Returns: The diagram response.
    /// - Throws: `DaemonError` on connection failure.
    func diagramGet(diagramUuid: String) async throws -> DiagramGetResponse {
        let uuid = Self.normalized(diagramUuid)
        return try await perform { try $0.diagramGet(DiagramGetRequest(diagramUuid: uuid)) }
    }

    /// Creates a diagram or returns an existing one (idempotent).
    /// - Parameter request: The init request with normalized UUIDs.
    /// - Returns: The diagram response.
    /// - Throws: `DaemonError` on connection failure.
    func diagramInit(_ request: DiagramInitRequest) async throws -> DiagramResponse {
        let req = DiagramInitRequest(
            code: request.code,
            name: request.name,
            projectUuid: Self.normalized(request.projectUuid),
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid),
            description: request.description,
            gmccDiagramPath: request.gmccDiagramPath,
            dopeScopeCode: request.dopeScopeCode
        )
        return try await perform { try $0.diagramInit(req) }
    }

    /// Searches diagrams across a project by recency or full-text query.
    ///
    /// With no query, returns the project's diagrams by recency. With a query, performs
    /// full-text search. Deliberately separate from diagramList's one-owner contract.
    /// - Parameters:
    ///   - projectUuid: The project UUID.
    ///   - sessionUuid: The session UUID to filter by, or nil for all tiers.
    ///   - query: The FTS query, or nil to browse by recency.
    ///   - limit: The maximum number of results, or nil for default limit.
    /// - Returns: An array of diagram rows.
    /// - Throws: `DaemonError` on connection failure.
    func diagramSearch(
        projectUuid: String,
        sessionUuid: String? = nil,
        query: String? = nil,
        limit: Int? = nil
    ) async throws -> [DiagramRow] {
        let req = DiagramSearchRequest(
            projectUuid: Self.normalized(projectUuid),
            sessionUuid: Self.normalized(sessionUuid),
            query: query,
            limit: limit
        )
        return try await perform { try $0.diagramSearch(req).diagrams }
    }

    /// Deletes a diagram with optional optimistic concurrency control.
    ///
    /// Elements cascade and listeners are notified via DIAGRAM_CHANGE event.
    /// - Parameters:
    ///   - diagramUuid: The diagram UUID.
    ///   - expectedRevision: The expected revision for CAS, or nil to skip the gate.
    /// - Returns: The delete response.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func diagramDelete(
        diagramUuid: String,
        expectedRevision: Int64? = nil
    ) async throws -> DiagramDeleteResponse {
        let uuid = Self.normalized(diagramUuid)
        return try await perform {
            try $0.diagramDelete(
                DiagramDeleteRequest(
                    diagramUuid: uuid,
                    expectedRevision: expectedRevision
                )
            )
        }
    }

    /// Applies multiple mutations to a diagram in one transaction.
    ///
    /// Every editor mutation goes through here. The granular DIAGRAM_NODE_* verbs are
    /// deliberately not wrapped.
    /// - Parameters:
    ///   - diagramUuid: The diagram UUID.
    ///   - expectedRevision: The expected revision for CAS, or nil to skip the gate.
    ///   - mutations: The mutations to apply.
    /// - Returns: The batch apply response.
    /// - Throws: `DaemonError` on connection or `StoreError.versionConflict` on stale version.
    func diagramBatchApply(
        diagramUuid: String,
        expectedRevision: Int64?,
        mutations: [DiagramMutation]
    ) async throws -> DiagramBatchApplyResponse {
        let req = DiagramBatchApplyRequest(
            diagramUuid: Self.normalized(diagramUuid),
            mutations: mutations,
            expectedRevision: expectedRevision
        )
        return try await perform { try $0.diagramBatchApply(req) }
    }

    // MARK: - Helpers

    /// Lowercases an optional UUID string, or returns nil.
    /// - Parameter uuid: The UUID to normalize, or nil.
    /// - Returns: The lowercased UUID, or nil.
    private nonisolated static func normalized(_ uuid: String?) -> String? {
        uuid.map(normalized)
    }

    /// Lowercases a UUID string, logging a debug assertion if already uppercased.
    /// - Parameter uuid: The UUID to normalize.
    /// - Returns: The lowercased UUID.
    private nonisolated static func normalized(_ uuid: String) -> String {
        let lower = uuid.lowercased()
        if lower != uuid {
            assertionFailure("uuid crossed the service boundary uppercased: \(uuid)")
        }
        return lower
    }
}
