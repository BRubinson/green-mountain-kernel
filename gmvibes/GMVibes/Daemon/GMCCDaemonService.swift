import Foundation
import GMCCDaemonKit

/// The single off-main boundary for all daemon socket I/O.
///
/// `DaemonClient` is blocking POSIX I/O, so calls are trampolined onto a
/// dedicated serial DispatchQueue rather than run on a cooperative-pool
/// thread. The probe client has autostart OFF so health checks report true
/// daemon state instead of resurrecting a daemon the user killed;
/// `startDaemon()` is the only autostart path in the app.
actor GMCCDaemonService {
    static let shared = GMCCDaemonService()

    private let client = DaemonClient(clientName: "gmvibes", autostart: false)
    private let queue = DispatchQueue(label: "gmvibes.daemon.client", qos: .userInitiated)

    nonisolated static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.binDaemon.path)
    }

    private func perform<T: Sendable>(
        _ body: @escaping @Sendable (DaemonClient) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [client] in
                do {
                    continuation.resume(returning: try body(client))
                } catch {
                    // A transport-level failure leaves a dead fd cached inside
                    // DaemonClient (nothing closes it on a thrown roundTrip),
                    // and the next call would skip redialing forever. Force a
                    // fresh dial; a server-reported domain error means the
                    // connection itself is healthy.
                    if let clientError = error as? DaemonClientError {
                        switch clientError {
                        case .wire, .unreachable, .protocolMismatch: client.close()
                        case .server: break
                        }
                    }
                    continuation.resume(throwing: DaemonError(error))
                }
            }
        }
    }

    // MARK: - Infra

    func ping() async throws -> PingResponse { try await perform { try $0.ping() } }
    func status() async throws -> StatusResponse { try await perform { try $0.status() } }

    /// The ONLY call site permitted to spawn the daemon: a throwaway
    /// autostart-enabled client, reached exclusively from the explicit
    /// "Start daemon" affordance.
    func startDaemon() async throws -> PingResponse {
        try await withCheckedThrowingContinuation { continuation in
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

    func listProjects() async throws -> [ProjectRow] {
        try await perform { try $0.listProjects().projects }
    }

    func listInstances(projectUuid: String? = nil) async throws -> [InstanceRow] {
        let uuid = Self.normalized(projectUuid)
        return try await perform { try $0.listInstances(InstanceListRequest(projectUuid: uuid)).instances }
    }

    func listSessions(instanceUuid: String? = nil) async throws -> [SessionStub] {
        let uuid = Self.normalized(instanceUuid)
        return try await perform { try $0.listSessions(SessionListRequest(instanceUuid: uuid)).sessions }
    }

    // MARK: - Catalog search

    func searchCatalog(query: String, projectUuid: String? = nil, limit: Int? = nil) async throws -> CatalogSearchResponse {
        let uuid = Self.normalized(projectUuid)
        return try await perform { try $0.searchCatalog(CatalogSearchRequest(query: query, projectUuid: uuid, limit: limit)) }
    }

    // MARK: - Full-text search (v8)

    /// FTS5 search over prompt/clarification/architecture text. An empty kind
    /// set is sent as nil — the daemon reads nil as "every kind".
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

    func getSession(sessionUuid: String) async throws -> SessionGetResponse {
        let uuid = Self.normalized(sessionUuid)
        return try await perform { try $0.getSession(SessionGetRequest(sessionUuid: uuid)) }
    }

    /// PROJECT_UPDATE — the only project-level mutation. The request's
    /// optional fields mean an all-nil body is EMPTY_UPDATE server-side, so
    /// callers must have something to change before calling.
    func updateProject(_ request: ProjectUpdateRequest) async throws -> ProjectRow {
        let req = ProjectUpdateRequest(
            projectUuid: Self.normalized(request.projectUuid),
            expectedVersion: request.expectedVersion,
            primaryProjectBranch: request.primaryProjectBranch
        )
        return try await perform { try $0.updateProject(req).project }
    }

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

    /// `withReports` enriches each stub with clarification/architecture
    /// summary stubs — one call replaces the per-prompt CLARIFY_GET/ARCH_GET
    /// fan-out for gate precomputation.
    func listPrompts(sessionUuid: String, withReports: Bool = false) async throws -> [PromptStub] {
        let uuid = Self.normalized(sessionUuid)
        return try await perform {
            try $0.listPrompts(PromptListRequest(
                sessionUuid: uuid,
                withReports: withReports ? true : nil
            )).prompts
        }
    }

    func getPrompt(promptUuid: String) async throws -> PromptGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.getPrompt(PromptGetRequest(promptUuid: uuid)) }
    }

    // Request-taking wrappers rebuild the request with normalized uuids — the
    // service boundary is the SINGLE place the uppercase-uuid trap is fixed,
    // and the mutation paths are exactly where a silent NOT_FOUND costs most.

    func createPrompt(_ request: PromptCreateRequest) async throws -> PromptRow {
        let req = PromptCreateRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            uuid: Self.normalized(request.uuid),
            code: request.code,
            name: request.name,
            backstory: request.backstory,
            goal: request.goal,
            detail: request.detail,
            command: request.command,
            ckfsRelativeStoragePath: request.ckfsRelativeStoragePath
        )
        return try await perform { try $0.createPrompt(req) }
    }

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

    func setPromptStatus(_ request: PromptSetStatusRequest) async throws -> PromptRow {
        let req = PromptSetStatusRequest(
            promptUuid: Self.normalized(request.promptUuid),
            expectedVersion: request.expectedVersion,
            status: request.status
        )
        return try await perform { try $0.setPromptStatus(req) }
    }

    // MARK: - Clarification / architecture (v7, read-only)

    func clarification(promptUuid: String) async throws -> ClarifyGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.clarifyGet(ClarifyGetRequest(promptUuid: uuid)) }
    }

    func architecture(promptUuid: String) async throws -> ArchGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.archGet(ArchGetRequest(promptUuid: uuid)) }
    }

    // MARK: - Clarification answering (m0025, the app's ONLY report write)

    /// CLARIFY_ANSWER — the one report-subsystem write the app is permitted.
    /// Write-wrapper shape copied from `setPromptStatus`: rebuild the request
    /// with normalized uuids, pass `expectedVersion` straight through (it
    /// targets the QUESTION row, never the summary), unwrap the row.
    ///
    /// Callers must always send BOTH axes — `answer()` DELETEs every
    /// `user_clarification_answer` row and rewrites `answer_text` wholesale on
    /// each call, so omitting the axis the user didn't touch destroys it.
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

    /// BOT_NEXT — the app's read onto the workflow machine. Treated honestly
    /// as a write (it stamps `last_served_phase` and emits WORKFLOW_CHANGE),
    /// but it is the ONLY bot verb wrapped here: botStart / botResume /
    /// botSetBaseline stay unwrapped because the app must not drive the
    /// machine. No `botGet` wrapper either — BOT_NEXT always.
    ///
    /// NEVER passes `clientKey`. `BotWorkflowRepository.resolve()` treats a
    /// clientKey as a CLAIM on the workflow, and the app must not steal a live
    /// terminal session's claim. `promptUuid` is `resolve()`'s FIRST branch, so
    /// clientKey is never even consulted on this path.
    func botNext(promptUuid: String) async throws -> BotNextResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.botNext(BotNextRequest(promptUuid: uuid)) }
    }

    // MARK: - Exploration / review (v9, read-only)

    /// Partitioned by default: `full: false` ⇒ the daemon's [0,99] window plus
    /// EVERY unranked row (NULL ratings are always in-window — the ranking
    /// agent's work queue). `full: true` returns the whole set; rating bounds
    /// are deliberately not exposed (the wire rejects them alongside full, and
    /// no surface here needs a custom window).
    func exploration(promptUuid: String, full: Bool = false) async throws -> ExploreGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.exploreGet(ExploreGetRequest(promptUuid: uuid, full: full)) }
    }

    func review(promptUuid: String, full: Bool = false) async throws -> ReviewGetResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.reviewGet(ReviewGetRequest(promptUuid: uuid, full: full)) }
    }

    // MARK: - Briefing (v21, read-only)

    /// One LIST returns every step row the doper has opened for the prompt —
    /// the step vocabulary is registry-governed daemon-side, so the app never
    /// enumerates it. An empty list is NORMAL (no SUMMARY_ABSENT on LIST).
    func briefings(promptUuid: String) async throws -> BriefingListResponse {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.briefingList(BriefingListRequest(promptUuid: uuid)) }
    }

    /// Per-row fetch for the staleness report — drift and ghost dot-paths are
    /// computed at read time and never stored, so LIST alone can't carry them.
    func briefing(uuid: String) async throws -> BriefingGetResponse {
        let normalized = Self.normalized(uuid)
        return try await perform { try $0.briefingGet(BriefingGetRequest(briefingUuid: normalized)) }
    }

    // MARK: - Git state / paths (v7)

    func instanceCurrentSession(instanceUuid: String) async throws -> InstanceCurrentSessionResponse {
        let uuid = Self.normalized(instanceUuid)
        return try await perform { try $0.instanceCurrentSession(InstanceCurrentSessionRequest(instanceUuid: uuid)) }
    }

    func paths() async throws -> PathsGetResponse {
        try await perform { try $0.pathsGet() }
    }

    // MARK: - File change / artifact

    // Retained for session prompt 2 (annotated diffs) even though SESSION_GET's
    // summaries cover today's rendering — the clarified goal lands this
    // plumbing deliberately.
    func listFileChanges(_ request: FileChangeListRequest) async throws -> [FileChangeRow] {
        let req = FileChangeListRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid),
            relativePath: request.relativePath,
            limit: request.limit
        )
        return try await perform { try $0.listFileChanges(req).changes }
    }

    func listArtifacts(promptUuid: String) async throws -> [ArtifactRow] {
        let uuid = Self.normalized(promptUuid)
        return try await perform { try $0.listArtifacts(ArtifactListRequest(promptUuid: uuid)).artifacts }
    }

    // MARK: - Kbite

    func listKbites(scope: KbiteScope, ownerUuid: String, all: Bool = false) async throws -> [KbiteRef] {
        let uuid = Self.normalized(ownerUuid)
        // Server short-circuits scope resolution when all == true, so the
        // owner uuid is ignored in that mode.
        return try await perform { try $0.listKbites(KbiteListRequest(scope: scope, ownerUuid: uuid, all: all ? true : nil)).kbites }
    }

    func addKbite(scope: KbiteScope, ownerUuid: String, code: String) async throws -> KbiteAddResponse {
        let uuid = Self.normalized(ownerUuid)
        return try await perform { try $0.addKbite(KbiteAddRequest(scope: scope, ownerUuid: uuid, code: code)) }
    }

    func removeKbite(scope: KbiteScope, ownerUuid: String, code: String) async throws -> KbiteRemoveResponse {
        let uuid = Self.normalized(ownerUuid)
        return try await perform { try $0.removeKbite(KbiteRemoveRequest(scope: scope, ownerUuid: uuid, code: code)) }
    }

    func searchKbites(query: String, kbiteUuids: [String]? = nil, limit: Int? = nil) async throws -> [KbiteSearchHit] {
        let uuids = kbiteUuids.map { $0.map(Self.normalized) }
        return try await perform { try $0.searchKbites(KbiteSearchRequest(query: query, kbiteUuids: uuids, limit: limit)).hits }
    }

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

    /// Scope enumeration for the picker. With `promptUuid`: ONLY that prompt's
    /// PROMPT scopes. Without it: the session's SESSION_BASE scopes. Never a
    /// union — a caller wanting both (a prompt surface, whose DOPE_GET falls
    /// back) asks twice. Zero scopes is an empty array, never SUMMARY_ABSENT.
    func dopeList(sessionUuid: String, promptUuid: String? = nil) async throws -> DopeListResponse {
        let req = DopeListRequest(
            sessionUuid: Self.normalized(sessionUuid),
            promptUuid: Self.normalized(promptUuid)
        )
        return try await perform { try $0.dopeList(req) }
    }

    func dopeGet(sessionUuid: String, promptUuid: String? = nil,
                 code: String? = nil) async throws -> DopeGetResponse {
        let req = DopeGetRequest(
            sessionUuid: Self.normalized(sessionUuid),
            promptUuid: Self.normalized(promptUuid),
            code: code
        )
        return try await perform { try $0.dopeGet(req) }
    }

    func dopeInit(_ request: DopeInitRequest) async throws -> DopeScopeResponse {
        let req = DopeInitRequest(
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid),
            code: request.code,
            name: request.name,
            description: request.description,
            cloneFromSessionBase: request.cloneFromSessionBase
        )
        return try await perform { try $0.dopeInit(req) }
    }

    /// PROJECT-tier dope read (the additive `projectUuid` addressing on
    /// DOPE_GET): the PROJECT_ITEM overlay, else the BASE_PROJECT scope
    /// `gm dope promote` maintains. A project has no session, so this is the
    /// ONLY door to the tree behind a project-tier diagram.
    func dopeGet(projectUuid: String, code: String? = nil) async throws -> DopeGetResponse {
        let req = DopeGetRequest(
            projectUuid: Self.normalized(projectUuid), code: code)
        return try await perform { try $0.dopeGet(req) }
    }

    func dopeReadRepo(scopeUuid: String) async throws -> DopeReadRepoResponse {
        let uuid = Self.normalized(scopeUuid)
        return try await perform { try $0.dopeReadRepo(DopeReadRepoRequest(scopeUuid: uuid)) }
    }

    // MARK: - Diagram

    /// One tier's rows for one owner — never a union and never a cross-tier
    /// ladder (the DIAGRAM_LIST contract, inherited verbatim from dopeList).
    /// A per-prompt count is therefore N calls, one per prompt; widening the
    /// message to fold prompt rows in under a session would break that
    /// invariant for every other caller.
    func diagramList(_ request: DiagramListRequest) async throws -> [DiagramRow] {
        let req = DiagramListRequest(
            projectUuid: Self.normalized(request.projectUuid),
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid)
        )
        return try await perform { try $0.diagramList(req).diagrams }
    }

    func diagramGet(diagramUuid: String) async throws -> DiagramGetResponse {
        let uuid = Self.normalized(diagramUuid)
        return try await perform { try $0.diagramGet(DiagramGetRequest(diagramUuid: uuid)) }
    }

    /// Create-or-return, idempotent per (owner, code).
    func diagramInit(_ request: DiagramInitRequest) async throws -> DiagramResponse {
        let req = DiagramInitRequest(
            projectUuid: Self.normalized(request.projectUuid),
            sessionUuid: Self.normalized(request.sessionUuid),
            promptUuid: Self.normalized(request.promptUuid),
            code: request.code,
            name: request.name,
            description: request.description,
            gmccDiagramPath: request.gmccDiagramPath,
            dopeScopeCode: request.dopeScopeCode
        )
        return try await perform { try $0.diagramInit(req) }
    }

    /// Cross-tier browse AND search for the galleries (v23). nil/empty query
    /// = the project's diagrams across tiers by recency; non-empty = FTS.
    /// Deliberately separate from diagramList's one-owner contract.
    func diagramSearch(projectUuid: String, sessionUuid: String? = nil,
                       query: String? = nil, limit: Int? = nil) async throws -> [DiagramRow] {
        let req = DiagramSearchRequest(
            projectUuid: Self.normalized(projectUuid),
            sessionUuid: Self.normalized(sessionUuid),
            query: query, limit: limit)
        return try await perform { try $0.diagramSearch(req).diagrams }
    }

    /// Row delete with an optional whole-diagram CAS gate; elements cascade
    /// server-side and DIAGRAM_CHANGE (action "deleted") wakes the galleries.
    func diagramDelete(diagramUuid: String,
                       expectedRevision: Int64? = nil) async throws -> DiagramDeleteResponse {
        let uuid = Self.normalized(diagramUuid)
        return try await perform {
            try $0.diagramDelete(DiagramDeleteRequest(
                diagramUuid: uuid, expectedRevision: expectedRevision))
        }
    }

    /// THE interactive write: one transaction, one revision, one
    /// DIAGRAM_CHANGE. Every editor mutation goes through here — the
    /// granular DIAGRAM_NODE_* verbs are deliberately not wrapped, since a
    /// one-mutation batch is the same call.
    func diagramBatchApply(diagramUuid: String, expectedRevision: Int64?,
                           mutations: [DiagramMutation]) async throws -> DiagramBatchApplyResponse {
        let req = DiagramBatchApplyRequest(
            diagramUuid: Self.normalized(diagramUuid),
            expectedRevision: expectedRevision,
            mutations: mutations)
        return try await perform { try $0.diagramBatchApply(req) }
    }

    // MARK: - Helpers

    private nonisolated static func normalized(_ uuid: String?) -> String? {
        uuid.map(normalized)
    }

    // Non-fatal guard: flag the drift in debug, but always self-correct — a
    // trapped assert on a path that lowercases one line later helps nobody.
    private nonisolated static func normalized(_ uuid: String) -> String {
        let lower = uuid.lowercased()
        if lower != uuid {
            assertionFailure("uuid crossed the service boundary uppercased: \(uuid)")
        }
        return lower
    }
}
