import Foundation

// Typed one-method-per-message facade — the entire integration surface for
// gm_hook, gm_mcp and GMVibes. Callers never touch MessageType or responseType.
//
// HUNG OFF `GmVerbCaller`, NOT `DaemonClient`. Every method below is the same
// one-liner over `request(type:payload:responseType:)`, so binding them to the
// protocol hands this whole surface to the kernel's in-process caller too,
// which is what lets MCP and hook bodies run kernel-side instead of dialing
// the daemon they are already inside.

extension GmVerbCaller {
    // MARK: - Infra

    /// Confirms the kernel is responsive.
    /// - Returns: The ping response from the kernel.
    /// - Throws: Any error the kernel reports.
    func ping() throws -> PingResponse {
        try request(type: .ping, payload: PingRequest(), responseType: PingResponse.self)
    }

    /// Retrieves the kernel's current operational status.
    /// - Returns: The status response from the kernel.
    /// - Throws: Any error the kernel reports.
    func status() throws -> StatusResponse {
        try request(type: .status, payload: StatusRequest(), responseType: StatusResponse.self)
    }

    /// Initiates a controlled shutdown of the kernel.
    /// - Returns: The shutdown response from the kernel.
    /// - Throws: Any error the kernel reports.
    func shutdown() throws -> ShutdownResponse {
        try request(type: .shutdown, payload: ShutdownRequest(), responseType: ShutdownResponse.self)
    }

    /// Creates a backup of the kernel's persistent state.
    /// - Returns: The backup response from the kernel.
    /// - Throws: Any error the kernel reports.
    func backup() throws -> BackupResponse {
        try request(type: .backup, payload: BackupRequest(), responseType: BackupResponse.self)
    }

    // MARK: - Context

    /// Ensures a context exists for the given request.
    /// - Parameter req: The context ensure request.
    /// - Returns: The context ensure response.
    /// - Throws: Any error the kernel reports.
    func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        try request(type: .contextEnsure, payload: req, responseType: ContextEnsureResponse.self)
    }

    /// Retrieves the current context.
    /// - Parameter req: The context get request.
    /// - Returns: The context get response.
    /// - Throws: Any error the kernel reports.
    func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        try request(type: .contextGet, payload: req, responseType: ContextGetResponse.self)
    }

    // MARK: - Listing

    /// Lists all projects.
    /// - Returns: The project list response.
    /// - Throws: Any error the kernel reports.
    func listProjects() throws -> ProjectListResponse {
        try request(type: .projectList, payload: ProjectListRequest(), responseType: ProjectListResponse.self)
    }

    /// Updates an existing project.
    /// - Parameter req: The project update request.
    /// - Returns: The updated project response.
    /// - Throws: Any error the kernel reports.
    func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectResponse {
        try request(type: .projectUpdate, payload: req, responseType: ProjectResponse.self)
    }

    /// Lists all instances.
    /// - Parameter req: The instance list request.
    /// - Returns: The instance list response.
    /// - Throws: Any error the kernel reports.
    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try request(type: .instanceList, payload: req, responseType: InstanceListResponse.self)
    }

    /// Lists all sessions.
    /// - Parameter req: The session list request.
    /// - Returns: The session list response.
    /// - Throws: Any error the kernel reports.
    func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try request(type: .sessionList, payload: req, responseType: SessionListResponse.self)
    }

    // MARK: - Catalog search

    /// Searches the catalog for entries matching the request.
    /// - Parameter req: The catalog search request.
    /// - Returns: The catalog search response.
    /// - Throws: Any error the kernel reports.
    func searchCatalog(_ req: CatalogSearchRequest) throws -> CatalogSearchResponse {
        try request(type: .catalogSearch, payload: req, responseType: CatalogSearchResponse.self)
    }

    // MARK: - Full-text search (v8)

    /// Performs a full-text search.
    /// - Parameter req: The search request.
    /// - Returns: The search response.
    /// - Throws: Any error the kernel reports.
    func search(_ req: SearchRequest) throws -> SearchResponse {
        try request(type: .search, payload: req, responseType: SearchResponse.self)
    }

    // MARK: - Session

    /// Retrieves a session by its identifier.
    /// - Parameter req: The session get request.
    /// - Returns: The session get response.
    /// - Throws: Any error the kernel reports.
    func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        try request(type: .sessionGet, payload: req, responseType: SessionGetResponse.self)
    }

    /// Updates an existing session.
    /// - Parameter req: The session update request.
    /// - Returns: The updated session row.
    /// - Throws: Any error the kernel reports.
    func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        try request(type: .sessionUpdate, payload: req, responseType: SessionRow.self)
    }

    // MARK: - Prompt

    /// Creates a new prompt.
    /// - Parameter req: The prompt create request.
    /// - Returns: The created prompt row.
    /// - Throws: Any error the kernel reports.
    func createPrompt(_ req: PromptCreateRequest) throws -> PromptRow {
        try request(type: .promptCreate, payload: req, responseType: PromptRow.self)
    }

    /// Lists all prompts.
    /// - Parameter req: The prompt list request.
    /// - Returns: The prompt list response.
    /// - Throws: Any error the kernel reports.
    func listPrompts(_ req: PromptListRequest) throws -> PromptListResponse {
        try request(type: .promptList, payload: req, responseType: PromptListResponse.self)
    }

    /// Retrieves a prompt by its identifier.
    /// - Parameter req: The prompt get request.
    /// - Returns: The prompt get response.
    /// - Throws: Any error the kernel reports.
    func getPrompt(_ req: PromptGetRequest) throws -> PromptGetResponse {
        try request(type: .promptGet, payload: req, responseType: PromptGetResponse.self)
    }

    /// Updates the content of an existing prompt.
    /// - Parameter req: The prompt update content request.
    /// - Returns: The updated prompt row.
    /// - Throws: Any error the kernel reports.
    func updatePromptContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        try request(type: .promptUpdateContent, payload: req, responseType: PromptRow.self)
    }

    /// Sets the status of a prompt.
    /// - Parameter req: The prompt set status request.
    /// - Returns: The updated prompt row.
    /// - Throws: Any error the kernel reports.
    func setPromptStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        try request(type: .promptSetStatus, payload: req, responseType: PromptRow.self)
    }

    // MARK: - Artifact

    /// Adds a new artifact.
    /// - Parameter req: The artifact add request.
    /// - Returns: The created artifact row.
    /// - Throws: Any error the kernel reports.
    func addArtifact(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        try request(type: .artifactAdd, payload: req, responseType: ArtifactRow.self)
    }

    /// Lists all artifacts.
    /// - Parameter req: The artifact list request.
    /// - Returns: The artifact list response.
    /// - Throws: Any error the kernel reports.
    func listArtifacts(_ req: ArtifactListRequest) throws -> ArtifactListResponse {
        try request(type: .artifactList, payload: req, responseType: ArtifactListResponse.self)
    }

    // MARK: - Prompt-qualified diagrams

    /// Qualifies a diagram for a prompt.
    /// - Parameter req: The prompt diagram qualify request.
    /// - Returns: The qualified diagram row.
    /// - Throws: Any error the kernel reports.
    func promptDiagramQualify(
        _ req: PromptDiagramQualifyRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(
            type: .promptDiagramQualify,
            payload: req,
            responseType: PromptQualifiedDiagramRow.self
        )
    }

    /// Retrieves a prompt-qualified diagram.
    /// - Parameter req: The prompt diagram get request.
    /// - Returns: The qualified diagram row.
    /// - Throws: Any error the kernel reports.
    func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(
            type: .promptDiagramGet,
            payload: req,
            responseType: PromptQualifiedDiagramRow.self
        )
    }

    /// Lists prompt-qualified diagrams.
    /// - Parameter req: The prompt diagram list request.
    /// - Returns: The prompt diagram list response.
    /// - Throws: Any error the kernel reports.
    func promptDiagramList(
        _ req: PromptDiagramListRequest
    ) throws -> PromptDiagramListResponse {
        try request(
            type: .promptDiagramList,
            payload: req,
            responseType: PromptDiagramListResponse.self
        )
    }

    // MARK: - File change

    /// Records a file change.
    /// - Parameter req: The file change add request.
    /// - Returns: The file change add response.
    /// - Throws: Any error the kernel reports.
    func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        try request(type: .fileChangeAdd, payload: req, responseType: FileChangeAddResponse.self)
    }

    /// Lists all file changes.
    /// - Parameter req: The file change list request.
    /// - Returns: The file change list response.
    /// - Throws: Any error the kernel reports.
    func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try request(type: .fileChangeList, payload: req, responseType: FileChangeListResponse.self)
    }

    // MARK: - Kbite

    /// Lists all knowledge bites.
    /// - Parameter req: The kbite list request.
    /// - Returns: The kbite list response.
    /// - Throws: Any error the kernel reports.
    func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        try request(type: .kbiteList, payload: req, responseType: KbiteListResponse.self)
    }

    /// Adds a new knowledge bite.
    /// - Parameter req: The kbite add request.
    /// - Returns: The kbite add response.
    /// - Throws: Any error the kernel reports.
    func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try request(type: .kbiteAdd, payload: req, responseType: KbiteAddResponse.self)
    }

    /// Removes an existing knowledge bite.
    /// - Parameter req: The kbite remove request.
    /// - Returns: The kbite remove response.
    /// - Throws: Any error the kernel reports.
    func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try request(type: .kbiteRemove, payload: req, responseType: KbiteRemoveResponse.self)
    }

    /// Opens a knowledge bite maw for source collection.
    /// - Parameter req: The kbite maw open request.
    /// - Returns: The kbite maw open response.
    /// - Throws: Any error the kernel reports.
    func openKbiteMaw(_ req: KbiteMawOpenRequest) throws -> KbiteMawOpenResponse {
        try request(type: .kbiteMawOpen, payload: req, responseType: KbiteMawOpenResponse.self)
    }

    /// Digests collected sources into a knowledge bite.
    /// - Parameter req: The kbite digest request.
    /// - Returns: The kbite digest response.
    /// - Throws: Any error the kernel reports.
    func digestKbite(_ req: KbiteDigestRequest) throws -> KbiteDigestResponse {
        try request(type: .kbiteDigest, payload: req, responseType: KbiteDigestResponse.self)
    }

    /// Retrieves a knowledge bite by its identifier.
    /// - Parameter req: The kbite get request.
    /// - Returns: The kbite get response.
    /// - Throws: Any error the kernel reports.
    func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        try request(type: .kbiteGet, payload: req, responseType: KbiteGetResponse.self)
    }

    /// Retrieves a file from a knowledge bite.
    /// - Parameter req: The kbite file get request.
    /// - Returns: The kbite file get response.
    /// - Throws: Any error the kernel reports.
    func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        try request(type: .kbiteFileGet, payload: req, responseType: KbiteFileGetResponse.self)
    }

    /// Searches knowledge bites.
    /// - Parameter req: The kbite search request.
    /// - Returns: The kbite search response.
    /// - Throws: Any error the kernel reports.
    func searchKbites(_ req: KbiteSearchRequest) throws -> KbiteSearchResponse {
        try request(type: .kbiteSearch, payload: req, responseType: KbiteSearchResponse.self)
    }

    /// Tags a knowledge bite with a keyword.
    /// - Parameter req: The kbite keyword tag request.
    /// - Returns: The kbite keyword tag response.
    /// - Throws: Any error the kernel reports.
    func tagKbiteKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        try request(type: .kbiteKeywordTag, payload: req, responseType: KbiteKeywordTagResponse.self)
    }

    /// Exports a knowledge bite.
    /// - Parameter req: The kbite export request.
    /// - Returns: The kbite export response.
    /// - Throws: Any error the kernel reports.
    func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        try request(type: .kbiteExport, payload: req, responseType: KbiteExportResponse.self)
    }

    /// Imports a knowledge bite.
    /// - Parameter req: The kbite import request.
    /// - Returns: The kbite import response.
    /// - Throws: Any error the kernel reports.
    func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        try request(type: .kbiteImport, payload: req, responseType: KbiteImportResponse.self)
    }

    /// Deletes a knowledge bite.
    /// - Parameter req: The kbite delete request.
    /// - Returns: The kbite delete response.
    /// - Throws: Any error the kernel reports.
    func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try request(type: .kbiteDelete, payload: req, responseType: KbiteDeleteResponse.self)
    }

    // MARK: - Audit

    /// Lists all audit events.
    /// - Parameter req: The event list request.
    /// - Returns: The event list response.
    /// - Throws: Any error the kernel reports.
    func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        try request(type: .eventList, payload: req, responseType: EventListResponse.self)
    }
}

// MARK: - Clarification (v7)

extension GmVerbCaller {
    /// Opens a clarification workflow.
    /// - Parameter req: The clarify open request.
    /// - Returns: The clarification summary response.
    /// - Throws: Any error the kernel reports.
    func clarifyOpen(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyOpen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    /// Adds a question to a clarification workflow.
    /// - Parameter req: The clarify question add request.
    /// - Returns: The clarify question row response.
    /// - Throws: Any error the kernel reports.
    func clarifyQuestionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyQuestionAdd, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    /// Adds a note to a clarification workflow.
    /// - Parameter req: The clarify note add request.
    /// - Returns: The clarify note row response.
    /// - Throws: Any error the kernel reports.
    func clarifyNoteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        try request(type: .clarifyNoteAdd, payload: req, responseType: ClarifyNoteRowResponse.self)
    }

    /// Seals a clarification workflow.
    /// - Parameter req: The clarify seal request.
    /// - Returns: The clarification summary response.
    /// - Throws: Any error the kernel reports.
    func clarifySeal(_ req: ClarifySealRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifySeal, payload: req, responseType: ClarifySummaryResponse.self)
    }

    /// Records an answer to a clarification question.
    /// - Parameter req: The clarify answer request.
    /// - Returns: The clarify question row response.
    /// - Throws: Any error the kernel reports.
    func clarifyAnswer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyAnswer, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    /// Opens a care package for context gathering.
    /// - Parameter req: The care package open request.
    /// - Returns: The care package response.
    /// - Throws: Any error the kernel reports.
    func carePackageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        try request(type: .carePackageOpen, payload: req, responseType: CarePackageResponse.self)
    }

    /// Adds a reference to a care package.
    /// - Parameter req: The care package ref add request.
    /// - Returns: The care package response.
    /// - Throws: Any error the kernel reports.
    func carePackageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        try request(type: .carePackageRefAdd, payload: req, responseType: CarePackageResponse.self)
    }

    /// Completes a care package.
    /// - Parameter req: The care package complete request.
    /// - Returns: The care package response.
    /// - Throws: Any error the kernel reports.
    func carePackageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        try request(type: .carePackageComplete, payload: req, responseType: CarePackageResponse.self)
    }

    /// Retrieves a care package.
    /// - Parameter req: The care package get request.
    /// - Returns: The care package response.
    /// - Throws: Any error the kernel reports.
    func carePackageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        try request(type: .carePackageGet, payload: req, responseType: CarePackageResponse.self)
    }

    /// Reopens a clarification workflow.
    /// - Parameter req: The clarify reopen request.
    /// - Returns: The clarification summary response.
    /// - Throws: Any error the kernel reports.
    func clarifyReopen(_ req: ClarifyReopenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyReopen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    /// Finalizes a clarification workflow.
    /// - Parameter req: The clarify finalize request.
    /// - Returns: The clarify finalize response.
    /// - Throws: Any error the kernel reports.
    func clarifyFinalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        try request(type: .clarifyFinalize, payload: req, responseType: ClarifyFinalizeResponse.self)
    }

    /// Retrieves a clarification workflow.
    /// - Parameter req: The clarify get request.
    /// - Returns: The clarify get response.
    /// - Throws: Any error the kernel reports.
    func clarifyGet(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        try request(type: .clarifyGet, payload: req, responseType: ClarifyGetResponse.self)
    }
}

// MARK: - Exploration (v9)

extension GmVerbCaller {
    /// Opens an exploration workflow.
    /// - Parameter req: The explore open request.
    /// - Returns: The explore summary response.
    /// - Throws: Any error the kernel reports.
    func exploreOpen(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreOpen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    /// Adds a key file to an exploration workflow.
    /// - Parameter req: The explore key file add request.
    /// - Returns: The explore key file add response.
    /// - Throws: Any error the kernel reports.
    func exploreKeyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        try request(type: .exploreKeyFileAdd, payload: req, responseType: ExploreKeyFileAddResponse.self)
    }

    /// Adds a finding to an exploration workflow.
    /// - Parameter req: The explore finding add request.
    /// - Returns: The explore finding row response.
    /// - Throws: Any error the kernel reports.
    func exploreFindingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        try request(type: .exploreFindingAdd, payload: req, responseType: ExploreFindingRowResponse.self)
    }

    /// Ranks findings in an exploration workflow.
    /// - Parameter req: The explore rank request.
    /// - Returns: The explore rank response.
    /// - Throws: Any error the kernel reports.
    func exploreRank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        try request(type: .exploreRank, payload: req, responseType: ExploreRankResponse.self)
    }

    /// Completes an exploration workflow.
    /// - Parameter req: The explore complete request.
    /// - Returns: The explore summary response.
    /// - Throws: Any error the kernel reports.
    func exploreComplete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreComplete, payload: req, responseType: ExploreSummaryResponse.self)
    }

    /// Reopens an exploration workflow.
    /// - Parameter req: The explore reopen request.
    /// - Returns: The explore summary response.
    /// - Throws: Any error the kernel reports.
    func exploreReopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreReopen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    /// Retrieves an exploration workflow.
    /// - Parameter req: The explore get request.
    /// - Returns: The explore get response.
    /// - Throws: Any error the kernel reports.
    func exploreGet(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        try request(type: .exploreGet, payload: req, responseType: ExploreGetResponse.self)
    }
}

// MARK: - Review (v9)

extension GmVerbCaller {
    /// Opens a review workflow.
    /// - Parameter req: The review open request.
    /// - Returns: The review summary response.
    /// - Throws: Any error the kernel reports.
    func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewOpen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    /// Adds a finding to a review workflow.
    /// - Parameter req: The review finding add request.
    /// - Returns: The review finding row response.
    /// - Throws: Any error the kernel reports.
    func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewFindingAdd, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    /// Ranks findings in a review workflow.
    /// - Parameter req: The review rank request.
    /// - Returns: The review rank response.
    /// - Throws: Any error the kernel reports.
    func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try request(type: .reviewRank, payload: req, responseType: ReviewRankResponse.self)
    }

    /// Resolves a finding in a review workflow.
    /// - Parameter req: The review resolve request.
    /// - Returns: The review finding row response.
    /// - Throws: Any error the kernel reports.
    func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewResolve, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    /// Completes a review workflow.
    /// - Parameter req: The review complete request.
    /// - Returns: The review summary response.
    /// - Throws: Any error the kernel reports.
    func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewComplete, payload: req, responseType: ReviewSummaryResponse.self)
    }

    /// Reopens a review workflow.
    /// - Parameter req: The review reopen request.
    /// - Returns: The review summary response.
    /// - Throws: Any error the kernel reports.
    func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewReopen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    /// Retrieves a review workflow.
    /// - Parameter req: The review get request.
    /// - Returns: The review get response.
    /// - Throws: Any error the kernel reports.
    func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try request(type: .reviewGet, payload: req, responseType: ReviewGetResponse.self)
    }
}

// MARK: - Briefing (v21)

extension GmVerbCaller {
    /// Opens a briefing workflow.
    /// - Parameter req: The briefing open request.
    /// - Returns: The briefing row response.
    /// - Throws: Any error the kernel reports.
    func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try request(type: .briefingOpen, payload: req, responseType: BriefingRowResponse.self)
    }

    /// Completes a briefing workflow.
    /// - Parameter req: The briefing complete request.
    /// - Returns: The briefing row response.
    /// - Throws: Any error the kernel reports.
    func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try request(type: .briefingComplete, payload: req, responseType: BriefingRowResponse.self)
    }

    /// Retrieves a briefing workflow.
    /// - Parameter req: The briefing get request.
    /// - Returns: The briefing get response.
    /// - Throws: Any error the kernel reports.
    func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try request(type: .briefingGet, payload: req, responseType: BriefingGetResponse.self)
    }

    /// Lists briefing workflows.
    /// - Parameter req: The briefing list request.
    /// - Returns: The briefing list response.
    /// - Throws: Any error the kernel reports.
    func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try request(type: .briefingList, payload: req, responseType: BriefingListResponse.self)
    }

    /// Retrieves a briefing stub.
    /// - Parameter req: The briefing stub request.
    /// - Returns: The briefing stub response.
    /// - Throws: Any error the kernel reports.
    func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try request(type: .briefingStub, payload: req, responseType: BriefingStubResponse.self)
    }
}

// MARK: - Architecture (v7)

extension GmVerbCaller {
    /// Opens an architecture workflow.
    /// - Parameter req: The architecture open request.
    /// - Returns: The architecture summary response.
    /// - Throws: Any error the kernel reports.
    func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try request(type: .archOpen, payload: req, responseType: ArchSummaryResponse.self)
    }

    /// Summarizes an architecture workflow.
    /// - Parameter req: The architecture summarize request.
    /// - Returns: The architecture summary response.
    /// - Throws: Any error the kernel reports.
    func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try request(type: .archSummarize, payload: req, responseType: ArchSummaryResponse.self)
    }

    /// Adds a persistence option to an architecture workflow.
    /// - Parameter req: The architecture persist add request.
    /// - Returns: The architecture persist add response.
    /// - Throws: Any error the kernel reports.
    func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try request(type: .archPersistAdd, payload: req, responseType: ArchPersistAddResponse.self)
    }

    /// Adds a field option to an architecture workflow.
    /// - Parameter req: The architecture field add request.
    /// - Returns: The architecture field add response.
    /// - Throws: Any error the kernel reports.
    func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try request(type: .archFieldAdd, payload: req, responseType: ArchFieldAddResponse.self)
    }

    /// Adds a general option to an architecture workflow.
    /// - Parameter req: The architecture general add request.
    /// - Returns: The architecture general add response.
    /// - Throws: Any error the kernel reports.
    func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try request(type: .archGeneralAdd, payload: req, responseType: ArchGeneralAddResponse.self)
    }

    /// Proposes an architecture option in a workflow.
    /// - Parameter req: The architecture propose request.
    /// - Returns: The architecture summary response.
    /// - Throws: Any error the kernel reports.
    func archPropose(_ req: ArchProposeRequest) throws -> ArchSummaryResponse {
        try request(type: .archPropose, payload: req, responseType: ArchSummaryResponse.self)
    }

    /// Approves an architecture option in a workflow.
    /// - Parameter req: The architecture approve request.
    /// - Returns: The architecture summary response.
    /// - Throws: Any error the kernel reports.
    func archApprove(_ req: ArchApproveRequest) throws -> ArchSummaryResponse {
        try request(type: .archApprove, payload: req, responseType: ArchSummaryResponse.self)
    }

    /// Revises an architecture option in a workflow.
    /// - Parameter req: The architecture revise request.
    /// - Returns: The architecture summary response.
    /// - Throws: Any error the kernel reports.
    func archRevise(_ req: ArchReviseRequest) throws -> ArchSummaryResponse {
        try request(type: .archRevise, payload: req, responseType: ArchSummaryResponse.self)
    }

    /// Adds an option to an architecture workflow.
    /// - Parameter req: The architecture option add request.
    /// - Returns: The architecture option row response.
    /// - Throws: Any error the kernel reports.
    func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try request(type: .archOptionAdd, payload: req, responseType: ArchOptionRowResponse.self)
    }

    /// Decides on an architecture option in a workflow.
    /// - Parameter req: The architecture decide request.
    /// - Returns: The architecture decide response.
    /// - Throws: Any error the kernel reports.
    func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try request(type: .archDecide, payload: req, responseType: ArchDecideResponse.self)
    }

    /// Starts a prompt workflow.
    /// - Parameter req: The prompt start request.
    /// - Returns: The bot workflow response.
    /// - Throws: Any error the kernel reports.
    func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try request(type: .promptStart, payload: req, responseType: BotWorkflowResponse.self)
    }

    /// Resumes a prompt workflow.
    /// - Parameter req: The prompt resume request.
    /// - Returns: The bot workflow response.
    /// - Throws: Any error the kernel reports.
    func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try request(type: .promptResume, payload: req, responseType: BotWorkflowResponse.self)
    }

    /// Advances to the next step in a bot workflow.
    /// - Parameter req: The bot next request.
    /// - Returns: The bot next response.
    /// - Throws: Any error the kernel reports.
    func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try request(type: .botNext, payload: req, responseType: BotNextResponse.self)
    }

    /// Retrieves a bot workflow.
    /// - Parameter req: The bot get request.
    /// - Returns: The bot workflow response.
    /// - Throws: Any error the kernel reports.
    func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try request(type: .botGet, payload: req, responseType: BotWorkflowResponse.self)
    }

    /// Registers an agent.
    /// - Parameter req: The agent register request.
    /// - Returns: The agent register response.
    /// - Throws: Any error the kernel reports.
    func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try request(type: .agentRegister, payload: req, responseType: AgentRegisterResponse.self)
    }

    /// Retrieves an architecture workflow.
    /// - Parameter req: The architecture get request.
    /// - Returns: The architecture get response.
    /// - Throws: Any error the kernel reports.
    func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try request(type: .archGet, payload: req, responseType: ArchGetResponse.self)
    }
}

// MARK: - Git state + config (v7)

extension GmVerbCaller {
    /// Resolves a session.
    /// - Parameter req: The session resolve request.
    /// - Returns: The session resolve response.
    /// - Throws: Any error the kernel reports.
    func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        try request(type: .sessionResolve, payload: req, responseType: SessionResolveResponse.self)
    }

    /// Retrieves the current session for an instance.
    /// - Parameter req: The instance current session request.
    /// - Returns: The instance current session response.
    /// - Throws: Any error the kernel reports.
    func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        try request(
            type: .instanceCurrentSession,
            payload: req,
            responseType: InstanceCurrentSessionResponse.self
        )
    }

    /// Retrieves all paths.
    /// - Returns: The paths get response.
    /// - Throws: Any error the kernel reports.
    func pathsGet() throws -> PathsGetResponse {
        try request(type: .pathsGet, payload: PathsGetRequest(), responseType: PathsGetResponse.self)
    }

    /// Sets configuration values.
    /// - Parameter req: The config set request.
    /// - Returns: The config set response.
    /// - Throws: Any error the kernel reports.
    func configSet(_ req: ConfigSetRequest) throws -> ConfigSetResponse {
        try request(type: .configSet, payload: req, responseType: ConfigSetResponse.self)
    }
}

// MARK: - Dope (v11)

extension GmVerbCaller {
    /// Initializes a dope scope.
    /// - Parameter req: The dope init request.
    /// - Returns: The dope scope response.
    /// - Throws: Any error the kernel reports.
    func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try request(type: .dopeInit, payload: req, responseType: DopeScopeResponse.self)
    }

    /// Lists dope scopes.
    /// - Parameter req: The dope list request.
    /// - Returns: The dope list response.
    /// - Throws: Any error the kernel reports.
    func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try request(type: .dopeList, payload: req, responseType: DopeListResponse.self)
    }

    /// Retrieves a dope scope.
    /// - Parameter req: The dope get request.
    /// - Returns: The dope get response.
    /// - Throws: Any error the kernel reports.
    func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        try request(type: .dopeGet, payload: req, responseType: DopeGetResponse.self)
    }

    /// Promotes a dope scope.
    /// - Parameter req: The dope promote request.
    /// - Returns: The dope promote response.
    /// - Throws: Any error the kernel reports.
    func dopePromote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        try request(type: .dopePromote, payload: req, responseType: DopePromoteResponse.self)
    }

    /// Adds a cog to a dope scope.
    /// - Parameter r: The dope cog add request.
    /// - Returns: The dope cog response.
    /// - Throws: Any error the kernel reports.
    func dopeCogAdd(_ r: DopeCogAddRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogAdd, payload: r, responseType: DopeCogResponse.self)
    }

    /// Updates a cog in a dope scope.
    /// - Parameter r: The dope cog update request.
    /// - Returns: The dope cog response.
    /// - Throws: Any error the kernel reports.
    func dopeCogUpdate(_ r: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogUpdate, payload: r, responseType: DopeCogResponse.self)
    }

    /// Deletes a cog from a dope scope.
    /// - Parameter r: The dope cog delete request.
    /// - Returns: The dope cog delete response.
    /// - Throws: Any error the kernel reports.
    func dopeCogDelete(_ r: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try request(type: .dopeCogDelete, payload: r, responseType: DopeCogDeleteResponse.self)
    }

    /// Retrieves a cog from a dope scope.
    /// - Parameter r: The dope cog get request.
    /// - Returns: The dope cog get response.
    /// - Throws: Any error the kernel reports.
    func dopeCogGet(_ r: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try request(type: .dopeCogGet, payload: r, responseType: DopeCogGetResponse.self)
    }

    /// Adds an element to a dope cog.
    /// - Parameter r: The dope cog element add request.
    /// - Returns: The dope cog element response.
    /// - Throws: Any error the kernel reports.
    func dopeCogElementAdd(_ r: DopeCogElementAddRequest) throws -> DopeCogElementResponse {
        try request(type: .dopeCogElementAdd, payload: r, responseType: DopeCogElementResponse.self)
    }

    /// Updates an element in a dope cog.
    /// - Parameter r: The dope cog element update request.
    /// - Returns: The dope cog element response.
    /// - Throws: Any error the kernel reports.
    func dopeCogElementUpdate(
        _ r: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try request(
            type: .dopeCogElementUpdate,
            payload: r,
            responseType: DopeCogElementResponse.self
        )
    }

    /// Deletes an element from a dope cog.
    /// - Parameter r: The dope cog element delete request.
    /// - Returns: The dope cog delete response.
    /// - Throws: Any error the kernel reports.
    func dopeCogElementDelete(
        _ r: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try request(
            type: .dopeCogElementDelete,
            payload: r,
            responseType: DopeCogDeleteResponse.self
        )
    }

    /// Searches a dope scope.
    /// - Parameter req: The dope search request.
    /// - Returns: The dope search response.
    /// - Throws: Any error the kernel reports.
    func dopeSearch(_ req: DopeSearchRequest) throws -> DopeSearchResponse {
        try request(type: .dopeSearch, payload: req, responseType: DopeSearchResponse.self)
    }

    /// Adds a node to a dope scope.
    /// - Parameter req: The dope node add request.
    /// - Returns: The dope node response.
    /// - Throws: Any error the kernel reports.
    func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeAdd, payload: req, responseType: DopeNodeResponse.self)
    }

    /// Updates a node in a dope scope.
    /// - Parameter req: The dope node update request.
    /// - Returns: The dope node response.
    /// - Throws: Any error the kernel reports.
    func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeUpdate, payload: req, responseType: DopeNodeResponse.self)
    }

    /// Deletes a node from a dope scope.
    /// - Parameter req: The dope node delete request.
    /// - Returns: The dope node delete response.
    /// - Throws: Any error the kernel reports.
    func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        try request(type: .dopeNodeDelete, payload: req, responseType: DopeNodeDeleteResponse.self)
    }

    /// Plans a merge in a dope scope.
    /// - Parameter req: The dope merge plan request.
    /// - Returns: The dope merge plan response.
    /// - Throws: Any error the kernel reports.
    func dopeMergePlan(_ req: DopeMergePlanRequest) throws -> DopeMergePlanResponse {
        try request(type: .dopeMergePlan, payload: req, responseType: DopeMergePlanResponse.self)
    }

    /// Resolves a dope scope.
    /// - Parameter req: The dope resolve request.
    /// - Returns: The dope resolve response.
    /// - Throws: Any error the kernel reports.
    func dopeResolve(_ req: DopeResolveRequest) throws -> DopeResolveResponse {
        try request(type: .dopeResolve, payload: req, responseType: DopeResolveResponse.self)
    }

    /// Reads a repository into a dope scope.
    /// - Parameter req: The dope read repo request.
    /// - Returns: The dope read repo response.
    /// - Throws: Any error the kernel reports.
    func dopeReadRepo(_ req: DopeReadRepoRequest) throws -> DopeReadRepoResponse {
        try request(type: .dopeReadRepo, payload: req, responseType: DopeReadRepoResponse.self)
    }

    /// Writes a dope scope to a repository.
    /// - Parameter req: The dope write repo request.
    /// - Returns: The dope write repo response.
    /// - Throws: Any error the kernel reports.
    func dopeWriteRepo(_ req: DopeWriteRepoRequest) throws -> DopeWriteRepoResponse {
        try request(type: .dopeWriteRepo, payload: req, responseType: DopeWriteRepoResponse.self)
    }

    /// Ingests content into a dope scope.
    /// - Parameter req: The dope ingest request.
    /// - Returns: The dope ingest response.
    /// - Throws: Any error the kernel reports.
    func dopeIngest(_ req: DopeIngestRequest) throws -> DopeIngestResponse {
        try request(type: .dopeIngest, payload: req, responseType: DopeIngestResponse.self)
    }
}

// MARK: - Diagram (v15)

extension GmVerbCaller {
    /// Initializes a diagram.
    /// - Parameter req: The diagram init request.
    /// - Returns: The diagram response.
    /// - Throws: Any error the kernel reports.
    func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try request(type: .diagramInit, payload: req, responseType: DiagramResponse.self)
    }

    /// Lists diagrams.
    /// - Parameter req: The diagram list request.
    /// - Returns: The diagram list response.
    /// - Throws: Any error the kernel reports.
    func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        try request(type: .diagramList, payload: req, responseType: DiagramListResponse.self)
    }

    /// Retrieves a diagram.
    /// - Parameter req: The diagram get request.
    /// - Returns: The diagram get response.
    /// - Throws: Any error the kernel reports.
    func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        try request(type: .diagramGet, payload: req, responseType: DiagramGetResponse.self)
    }

    /// Adds a node to a diagram.
    /// - Parameter req: The diagram node add request.
    /// - Returns: The diagram node response.
    /// - Throws: Any error the kernel reports.
    func diagramNodeAdd(_ req: DiagramNodeAddRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeAdd, payload: req, responseType: DiagramNodeResponse.self)
    }

    /// Updates a node in a diagram.
    /// - Parameter req: The diagram node update request.
    /// - Returns: The diagram node response.
    /// - Throws: Any error the kernel reports.
    func diagramNodeUpdate(_ req: DiagramNodeUpdateRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeUpdate, payload: req, responseType: DiagramNodeResponse.self)
    }

    /// Deletes a node from a diagram.
    /// - Parameter req: The diagram node delete request.
    /// - Returns: The diagram node delete response.
    /// - Throws: Any error the kernel reports.
    func diagramNodeDelete(_ req: DiagramNodeDeleteRequest) throws -> DiagramNodeDeleteResponse {
        try request(type: .diagramNodeDelete, payload: req, responseType: DiagramNodeDeleteResponse.self)
    }

    /// Applies batch changes to a diagram.
    /// - Parameter req: The diagram batch apply request.
    /// - Returns: The diagram batch apply response.
    /// - Throws: Any error the kernel reports.
    func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        try request(type: .diagramBatchApply, payload: req, responseType: DiagramBatchApplyResponse.self)
    }

    /// Searches a diagram.
    /// - Parameter req: The diagram search request.
    /// - Returns: The diagram search response.
    /// - Throws: Any error the kernel reports.
    func diagramSearch(_ req: DiagramSearchRequest) throws -> DiagramSearchResponse {
        try request(type: .diagramSearch, payload: req, responseType: DiagramSearchResponse.self)
    }

    /// Deletes a diagram.
    /// - Parameter req: The diagram delete request.
    /// - Returns: The diagram delete response.
    /// - Throws: Any error the kernel reports.
    func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        try request(type: .diagramDelete, payload: req, responseType: DiagramDeleteResponse.self)
    }

    /// Writes a diagram to a repository.
    /// - Parameter req: The diagram write repo request.
    /// - Returns: The diagram write repo response.
    /// - Throws: Any error the kernel reports.
    func diagramWriteRepo(_ req: DiagramWriteRepoRequest) throws -> DiagramWriteRepoResponse {
        try request(type: .diagramWriteRepo, payload: req, responseType: DiagramWriteRepoResponse.self)
    }

    /// Ingests diagrams from files into the database.
    ///
    /// - Parameter req: The diagram ingest request.
    /// - Returns: The diagram ingest response.
    /// - Throws: Any error the kernel reports.
    func diagramIngest(_ req: DiagramIngestRequest) throws -> DiagramIngestResponse {
        try request(type: .diagramIngest, payload: req, responseType: DiagramIngestResponse.self)
    }
}
