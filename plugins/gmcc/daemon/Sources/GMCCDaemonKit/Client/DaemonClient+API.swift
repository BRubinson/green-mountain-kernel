import Foundation

// Typed one-method-per-message facade — the entire integration surface for
// gmcc_hook, gmcc_mcp and GMVibes. Wraps the generic request plumbing; callers never touch
// MessageType or responseType.

extension DaemonClient {
    // MARK: - Infra

    public func ping() throws -> PingResponse {
        try request(type: .ping, payload: PingRequest(), responseType: PingResponse.self)
    }

    public func status() throws -> StatusResponse {
        try request(type: .status, payload: StatusRequest(), responseType: StatusResponse.self)
    }

    public func shutdown() throws -> ShutdownResponse {
        try request(type: .shutdown, payload: ShutdownRequest(), responseType: ShutdownResponse.self)
    }

    public func backup() throws -> BackupResponse {
        try request(type: .backup, payload: BackupRequest(), responseType: BackupResponse.self)
    }

    // MARK: - Context

    public func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        try request(type: .contextEnsure, payload: req, responseType: ContextEnsureResponse.self)
    }

    public func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        try request(type: .contextGet, payload: req, responseType: ContextGetResponse.self)
    }

    // MARK: - Listing

    public func listProjects() throws -> ProjectListResponse {
        try request(type: .projectList, payload: ProjectListRequest(), responseType: ProjectListResponse.self)
    }

    public func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectResponse {
        try request(type: .projectUpdate, payload: req, responseType: ProjectResponse.self)
    }

    public func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try request(type: .instanceList, payload: req, responseType: InstanceListResponse.self)
    }

    public func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try request(type: .sessionList, payload: req, responseType: SessionListResponse.self)
    }

    // MARK: - Catalog search

    public func searchCatalog(_ req: CatalogSearchRequest) throws -> CatalogSearchResponse {
        try request(type: .catalogSearch, payload: req, responseType: CatalogSearchResponse.self)
    }

    // MARK: - Full-text search (v8)

    public func search(_ req: SearchRequest) throws -> SearchResponse {
        try request(type: .search, payload: req, responseType: SearchResponse.self)
    }

    // MARK: - Session

    public func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        try request(type: .sessionGet, payload: req, responseType: SessionGetResponse.self)
    }

    public func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        try request(type: .sessionUpdate, payload: req, responseType: SessionRow.self)
    }

    // MARK: - Prompt

    public func createPrompt(_ req: PromptCreateRequest) throws -> PromptRow {
        try request(type: .promptCreate, payload: req, responseType: PromptRow.self)
    }

    public func listPrompts(_ req: PromptListRequest) throws -> PromptListResponse {
        try request(type: .promptList, payload: req, responseType: PromptListResponse.self)
    }

    public func getPrompt(_ req: PromptGetRequest) throws -> PromptGetResponse {
        try request(type: .promptGet, payload: req, responseType: PromptGetResponse.self)
    }

    public func updatePromptContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        try request(type: .promptUpdateContent, payload: req, responseType: PromptRow.self)
    }

    public func setPromptStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        try request(type: .promptSetStatus, payload: req, responseType: PromptRow.self)
    }

    // MARK: - Artifact

    public func addArtifact(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        try request(type: .artifactAdd, payload: req, responseType: ArtifactRow.self)
    }

    public func listArtifacts(_ req: ArtifactListRequest) throws -> ArtifactListResponse {
        try request(type: .artifactList, payload: req, responseType: ArtifactListResponse.self)
    }

    // MARK: - Prompt-qualified diagrams

    public func promptDiagramQualify(
        _ req: PromptDiagramQualifyRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(type: .promptDiagramQualify, payload: req,
                    responseType: PromptQualifiedDiagramRow.self)
    }

    public func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(type: .promptDiagramGet, payload: req,
                    responseType: PromptQualifiedDiagramRow.self)
    }

    public func promptDiagramList(
        _ req: PromptDiagramListRequest
    ) throws -> PromptDiagramListResponse {
        try request(type: .promptDiagramList, payload: req,
                    responseType: PromptDiagramListResponse.self)
    }

    // MARK: - File change

    public func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        try request(type: .fileChangeAdd, payload: req, responseType: FileChangeAddResponse.self)
    }

    public func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try request(type: .fileChangeList, payload: req, responseType: FileChangeListResponse.self)
    }

    // MARK: - Kbite

    public func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        try request(type: .kbiteList, payload: req, responseType: KbiteListResponse.self)
    }

    public func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try request(type: .kbiteAdd, payload: req, responseType: KbiteAddResponse.self)
    }

    public func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try request(type: .kbiteRemove, payload: req, responseType: KbiteRemoveResponse.self)
    }

    public func openKbiteMaw(_ req: KbiteMawOpenRequest) throws -> KbiteMawOpenResponse {
        try request(type: .kbiteMawOpen, payload: req, responseType: KbiteMawOpenResponse.self)
    }

    public func digestKbite(_ req: KbiteDigestRequest) throws -> KbiteDigestResponse {
        try request(type: .kbiteDigest, payload: req, responseType: KbiteDigestResponse.self)
    }

    public func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        try request(type: .kbiteGet, payload: req, responseType: KbiteGetResponse.self)
    }

    public func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        try request(type: .kbiteFileGet, payload: req, responseType: KbiteFileGetResponse.self)
    }

    public func searchKbites(_ req: KbiteSearchRequest) throws -> KbiteSearchResponse {
        try request(type: .kbiteSearch, payload: req, responseType: KbiteSearchResponse.self)
    }

    public func tagKbiteKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        try request(type: .kbiteKeywordTag, payload: req, responseType: KbiteKeywordTagResponse.self)
    }

    public func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        try request(type: .kbiteExport, payload: req, responseType: KbiteExportResponse.self)
    }

    public func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        try request(type: .kbiteImport, payload: req, responseType: KbiteImportResponse.self)
    }

    public func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try request(type: .kbiteDelete, payload: req, responseType: KbiteDeleteResponse.self)
    }

    // MARK: - Audit

    public func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        try request(type: .eventList, payload: req, responseType: EventListResponse.self)
    }
}

// MARK: - Clarification (v7)

extension DaemonClient {
    public func clarifyOpen(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyOpen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    public func clarifyQuestionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyQuestionAdd, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    public func clarifyNoteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        try request(type: .clarifyNoteAdd, payload: req, responseType: ClarifyNoteRowResponse.self)
    }

    public func clarifySeal(_ req: ClarifySealRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifySeal, payload: req, responseType: ClarifySummaryResponse.self)
    }

    public func clarifyAnswer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyAnswer, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    public func carePackageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        try request(type: .carePackageOpen, payload: req, responseType: CarePackageResponse.self)
    }

    public func carePackageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        try request(type: .carePackageRefAdd, payload: req, responseType: CarePackageResponse.self)
    }

    public func carePackageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        try request(type: .carePackageComplete, payload: req, responseType: CarePackageResponse.self)
    }

    public func carePackageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        try request(type: .carePackageGet, payload: req, responseType: CarePackageResponse.self)
    }

    public func clarifyReopen(_ req: ClarifyReopenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyReopen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    public func clarifyFinalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        try request(type: .clarifyFinalize, payload: req, responseType: ClarifyFinalizeResponse.self)
    }

    public func clarifyGet(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        try request(type: .clarifyGet, payload: req, responseType: ClarifyGetResponse.self)
    }
}

// MARK: - Exploration (v9)

extension DaemonClient {
    public func exploreOpen(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreOpen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    public func exploreKeyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        try request(type: .exploreKeyFileAdd, payload: req, responseType: ExploreKeyFileAddResponse.self)
    }

    public func exploreFindingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        try request(type: .exploreFindingAdd, payload: req, responseType: ExploreFindingRowResponse.self)
    }

    public func exploreRank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        try request(type: .exploreRank, payload: req, responseType: ExploreRankResponse.self)
    }

    public func exploreComplete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreComplete, payload: req, responseType: ExploreSummaryResponse.self)
    }

    public func exploreReopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreReopen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    public func exploreGet(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        try request(type: .exploreGet, payload: req, responseType: ExploreGetResponse.self)
    }
}

// MARK: - Review (v9)

extension DaemonClient {
    public func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewOpen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    public func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewFindingAdd, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    public func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try request(type: .reviewRank, payload: req, responseType: ReviewRankResponse.self)
    }

    public func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewResolve, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    public func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewComplete, payload: req, responseType: ReviewSummaryResponse.self)
    }

    public func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewReopen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    public func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try request(type: .reviewGet, payload: req, responseType: ReviewGetResponse.self)
    }
}

// MARK: - Briefing (v21)

extension DaemonClient {
    public func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try request(type: .briefingOpen, payload: req, responseType: BriefingRowResponse.self)
    }

    public func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try request(type: .briefingComplete, payload: req, responseType: BriefingRowResponse.self)
    }

    public func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try request(type: .briefingGet, payload: req, responseType: BriefingGetResponse.self)
    }

    public func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try request(type: .briefingList, payload: req, responseType: BriefingListResponse.self)
    }

    public func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try request(type: .briefingStub, payload: req, responseType: BriefingStubResponse.self)
    }
}

// MARK: - Architecture (v7)

extension DaemonClient {
    public func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try request(type: .archOpen, payload: req, responseType: ArchSummaryResponse.self)
    }

    public func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try request(type: .archSummarize, payload: req, responseType: ArchSummaryResponse.self)
    }

    public func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try request(type: .archPersistAdd, payload: req, responseType: ArchPersistAddResponse.self)
    }

    public func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try request(type: .archFieldAdd, payload: req, responseType: ArchFieldAddResponse.self)
    }

    public func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try request(type: .archGeneralAdd, payload: req, responseType: ArchGeneralAddResponse.self)
    }

    public func archPropose(_ req: ArchProposeRequest) throws -> ArchSummaryResponse {
        try request(type: .archPropose, payload: req, responseType: ArchSummaryResponse.self)
    }

    public func archApprove(_ req: ArchApproveRequest) throws -> ArchSummaryResponse {
        try request(type: .archApprove, payload: req, responseType: ArchSummaryResponse.self)
    }

    public func archRevise(_ req: ArchReviseRequest) throws -> ArchSummaryResponse {
        try request(type: .archRevise, payload: req, responseType: ArchSummaryResponse.self)
    }

    public func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try request(type: .archOptionAdd, payload: req, responseType: ArchOptionRowResponse.self)
    }

    public func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try request(type: .archDecide, payload: req, responseType: ArchDecideResponse.self)
    }

    public func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try request(type: .promptStart, payload: req, responseType: BotWorkflowResponse.self)
    }

    public func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try request(type: .promptResume, payload: req, responseType: BotWorkflowResponse.self)
    }

    public func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try request(type: .botNext, payload: req, responseType: BotNextResponse.self)
    }

    public func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try request(type: .botGet, payload: req, responseType: BotWorkflowResponse.self)
    }

    public func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try request(type: .agentRegister, payload: req, responseType: AgentRegisterResponse.self)
    }

    public func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try request(type: .archGet, payload: req, responseType: ArchGetResponse.self)
    }
}

// MARK: - Git state + config (v7)

extension DaemonClient {
    public func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        try request(type: .sessionResolve, payload: req, responseType: SessionResolveResponse.self)
    }

    public func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        try request(
            type: .instanceCurrentSession, payload: req,
            responseType: InstanceCurrentSessionResponse.self)
    }

    public func pathsGet() throws -> PathsGetResponse {
        try request(type: .pathsGet, payload: PathsGetRequest(), responseType: PathsGetResponse.self)
    }

    public func configSet(_ req: ConfigSetRequest) throws -> ConfigSetResponse {
        try request(type: .configSet, payload: req, responseType: ConfigSetResponse.self)
    }
}

// MARK: - Dope (v11)

extension DaemonClient {
    public func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try request(type: .dopeInit, payload: req, responseType: DopeScopeResponse.self)
    }

    public func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try request(type: .dopeList, payload: req, responseType: DopeListResponse.self)
    }

    public func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        try request(type: .dopeGet, payload: req, responseType: DopeGetResponse.self)
    }

    public func dopePromote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        try request(type: .dopePromote, payload: req, responseType: DopePromoteResponse.self)
    }

    public func dopeCogAdd(_ r: DopeCogAddRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogAdd, payload: r, responseType: DopeCogResponse.self)
    }

    public func dopeCogUpdate(_ r: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogUpdate, payload: r, responseType: DopeCogResponse.self)
    }

    public func dopeCogDelete(_ r: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try request(type: .dopeCogDelete, payload: r, responseType: DopeCogDeleteResponse.self)
    }

    public func dopeCogGet(_ r: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try request(type: .dopeCogGet, payload: r, responseType: DopeCogGetResponse.self)
    }

    public func dopeCogElementAdd(_ r: DopeCogElementAddRequest) throws -> DopeCogElementResponse {
        try request(type: .dopeCogElementAdd, payload: r, responseType: DopeCogElementResponse.self)
    }

    public func dopeCogElementUpdate(
        _ r: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try request(type: .dopeCogElementUpdate, payload: r,
                    responseType: DopeCogElementResponse.self)
    }

    public func dopeCogElementDelete(
        _ r: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try request(type: .dopeCogElementDelete, payload: r,
                    responseType: DopeCogDeleteResponse.self)
    }

    public func dopeSearch(_ req: DopeSearchRequest) throws -> DopeSearchResponse {
        try request(type: .dopeSearch, payload: req, responseType: DopeSearchResponse.self)
    }

    public func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeAdd, payload: req, responseType: DopeNodeResponse.self)
    }

    public func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeUpdate, payload: req, responseType: DopeNodeResponse.self)
    }

    public func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        try request(type: .dopeNodeDelete, payload: req, responseType: DopeNodeDeleteResponse.self)
    }

    public func dopeMergePlan(_ req: DopeMergePlanRequest) throws -> DopeMergePlanResponse {
        try request(type: .dopeMergePlan, payload: req, responseType: DopeMergePlanResponse.self)
    }

    public func dopeResolve(_ req: DopeResolveRequest) throws -> DopeResolveResponse {
        try request(type: .dopeResolve, payload: req, responseType: DopeResolveResponse.self)
    }

    public func dopeReadRepo(_ req: DopeReadRepoRequest) throws -> DopeReadRepoResponse {
        try request(type: .dopeReadRepo, payload: req, responseType: DopeReadRepoResponse.self)
    }

    public func dopeWriteRepo(_ req: DopeWriteRepoRequest) throws -> DopeWriteRepoResponse {
        try request(type: .dopeWriteRepo, payload: req, responseType: DopeWriteRepoResponse.self)
    }

    public func dopeIngest(_ req: DopeIngestRequest) throws -> DopeIngestResponse {
        try request(type: .dopeIngest, payload: req, responseType: DopeIngestResponse.self)
    }
}

// MARK: - Diagram (v15)

extension DaemonClient {
    public func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try request(type: .diagramInit, payload: req, responseType: DiagramResponse.self)
    }

    public func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        try request(type: .diagramList, payload: req, responseType: DiagramListResponse.self)
    }

    public func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        try request(type: .diagramGet, payload: req, responseType: DiagramGetResponse.self)
    }

    public func diagramNodeAdd(_ req: DiagramNodeAddRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeAdd, payload: req, responseType: DiagramNodeResponse.self)
    }

    public func diagramNodeUpdate(_ req: DiagramNodeUpdateRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeUpdate, payload: req, responseType: DiagramNodeResponse.self)
    }

    public func diagramNodeDelete(_ req: DiagramNodeDeleteRequest) throws -> DiagramNodeDeleteResponse {
        try request(type: .diagramNodeDelete, payload: req, responseType: DiagramNodeDeleteResponse.self)
    }

    public func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        try request(type: .diagramBatchApply, payload: req, responseType: DiagramBatchApplyResponse.self)
    }

    public func diagramSearch(_ req: DiagramSearchRequest) throws -> DiagramSearchResponse {
        try request(type: .diagramSearch, payload: req, responseType: DiagramSearchResponse.self)
    }

    public func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        try request(type: .diagramDelete, payload: req, responseType: DiagramDeleteResponse.self)
    }

    public func diagramWriteRepo(_ req: DiagramWriteRepoRequest) throws -> DiagramWriteRepoResponse {
        try request(type: .diagramWriteRepo, payload: req, responseType: DiagramWriteRepoResponse.self)
    }

    public func diagramIngest(_ req: DiagramIngestRequest) throws -> DiagramIngestResponse {
        try request(type: .diagramIngest, payload: req, responseType: DiagramIngestResponse.self)
    }
}
