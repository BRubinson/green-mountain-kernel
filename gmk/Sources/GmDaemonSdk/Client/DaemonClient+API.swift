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

    func ping() throws -> PingResponse {
        try request(type: .ping, payload: PingRequest(), responseType: PingResponse.self)
    }

    func status() throws -> StatusResponse {
        try request(type: .status, payload: StatusRequest(), responseType: StatusResponse.self)
    }

    func shutdown() throws -> ShutdownResponse {
        try request(type: .shutdown, payload: ShutdownRequest(), responseType: ShutdownResponse.self)
    }

    func backup() throws -> BackupResponse {
        try request(type: .backup, payload: BackupRequest(), responseType: BackupResponse.self)
    }

    // MARK: - Context

    func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        try request(type: .contextEnsure, payload: req, responseType: ContextEnsureResponse.self)
    }

    func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        try request(type: .contextGet, payload: req, responseType: ContextGetResponse.self)
    }

    // MARK: - Listing

    func listProjects() throws -> ProjectListResponse {
        try request(type: .projectList, payload: ProjectListRequest(), responseType: ProjectListResponse.self)
    }

    func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectResponse {
        try request(type: .projectUpdate, payload: req, responseType: ProjectResponse.self)
    }

    func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try request(type: .instanceList, payload: req, responseType: InstanceListResponse.self)
    }

    func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try request(type: .sessionList, payload: req, responseType: SessionListResponse.self)
    }

    // MARK: - Catalog search

    func searchCatalog(_ req: CatalogSearchRequest) throws -> CatalogSearchResponse {
        try request(type: .catalogSearch, payload: req, responseType: CatalogSearchResponse.self)
    }

    // MARK: - Full-text search (v8)

    func search(_ req: SearchRequest) throws -> SearchResponse {
        try request(type: .search, payload: req, responseType: SearchResponse.self)
    }

    // MARK: - Session

    func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        try request(type: .sessionGet, payload: req, responseType: SessionGetResponse.self)
    }

    func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        try request(type: .sessionUpdate, payload: req, responseType: SessionRow.self)
    }

    // MARK: - Prompt

    func createPrompt(_ req: PromptCreateRequest) throws -> PromptRow {
        try request(type: .promptCreate, payload: req, responseType: PromptRow.self)
    }

    func listPrompts(_ req: PromptListRequest) throws -> PromptListResponse {
        try request(type: .promptList, payload: req, responseType: PromptListResponse.self)
    }

    func getPrompt(_ req: PromptGetRequest) throws -> PromptGetResponse {
        try request(type: .promptGet, payload: req, responseType: PromptGetResponse.self)
    }

    func updatePromptContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        try request(type: .promptUpdateContent, payload: req, responseType: PromptRow.self)
    }

    func setPromptStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        try request(type: .promptSetStatus, payload: req, responseType: PromptRow.self)
    }

    // MARK: - Artifact

    func addArtifact(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        try request(type: .artifactAdd, payload: req, responseType: ArtifactRow.self)
    }

    func listArtifacts(_ req: ArtifactListRequest) throws -> ArtifactListResponse {
        try request(type: .artifactList, payload: req, responseType: ArtifactListResponse.self)
    }

    // MARK: - Prompt-qualified diagrams

    func promptDiagramQualify(
        _ req: PromptDiagramQualifyRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(
            type: .promptDiagramQualify,
            payload: req,
            responseType: PromptQualifiedDiagramRow.self
        )
    }

    func promptDiagramGet(
        _ req: PromptDiagramGetRequest
    ) throws -> PromptQualifiedDiagramRow {
        try request(
            type: .promptDiagramGet,
            payload: req,
            responseType: PromptQualifiedDiagramRow.self
        )
    }

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

    func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        try request(type: .fileChangeAdd, payload: req, responseType: FileChangeAddResponse.self)
    }

    func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try request(type: .fileChangeList, payload: req, responseType: FileChangeListResponse.self)
    }

    // MARK: - Kbite

    func listKbites(_ req: KbiteListRequest) throws -> KbiteListResponse {
        try request(type: .kbiteList, payload: req, responseType: KbiteListResponse.self)
    }

    func addKbite(_ req: KbiteAddRequest) throws -> KbiteAddResponse {
        try request(type: .kbiteAdd, payload: req, responseType: KbiteAddResponse.self)
    }

    func removeKbite(_ req: KbiteRemoveRequest) throws -> KbiteRemoveResponse {
        try request(type: .kbiteRemove, payload: req, responseType: KbiteRemoveResponse.self)
    }

    func openKbiteMaw(_ req: KbiteMawOpenRequest) throws -> KbiteMawOpenResponse {
        try request(type: .kbiteMawOpen, payload: req, responseType: KbiteMawOpenResponse.self)
    }

    func digestKbite(_ req: KbiteDigestRequest) throws -> KbiteDigestResponse {
        try request(type: .kbiteDigest, payload: req, responseType: KbiteDigestResponse.self)
    }

    func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        try request(type: .kbiteGet, payload: req, responseType: KbiteGetResponse.self)
    }

    func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        try request(type: .kbiteFileGet, payload: req, responseType: KbiteFileGetResponse.self)
    }

    func searchKbites(_ req: KbiteSearchRequest) throws -> KbiteSearchResponse {
        try request(type: .kbiteSearch, payload: req, responseType: KbiteSearchResponse.self)
    }

    func tagKbiteKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        try request(type: .kbiteKeywordTag, payload: req, responseType: KbiteKeywordTagResponse.self)
    }

    func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        try request(type: .kbiteExport, payload: req, responseType: KbiteExportResponse.self)
    }

    func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        try request(type: .kbiteImport, payload: req, responseType: KbiteImportResponse.self)
    }

    func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try request(type: .kbiteDelete, payload: req, responseType: KbiteDeleteResponse.self)
    }

    // MARK: - Audit

    func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        try request(type: .eventList, payload: req, responseType: EventListResponse.self)
    }
}

// MARK: - Clarification (v7)

extension GmVerbCaller {
    func clarifyOpen(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyOpen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    func clarifyQuestionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyQuestionAdd, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    func clarifyNoteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        try request(type: .clarifyNoteAdd, payload: req, responseType: ClarifyNoteRowResponse.self)
    }

    func clarifySeal(_ req: ClarifySealRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifySeal, payload: req, responseType: ClarifySummaryResponse.self)
    }

    func clarifyAnswer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        try request(type: .clarifyAnswer, payload: req, responseType: ClarifyQuestionRowResponse.self)
    }

    func carePackageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        try request(type: .carePackageOpen, payload: req, responseType: CarePackageResponse.self)
    }

    func carePackageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        try request(type: .carePackageRefAdd, payload: req, responseType: CarePackageResponse.self)
    }

    func carePackageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        try request(type: .carePackageComplete, payload: req, responseType: CarePackageResponse.self)
    }

    func carePackageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        try request(type: .carePackageGet, payload: req, responseType: CarePackageResponse.self)
    }

    func clarifyReopen(_ req: ClarifyReopenRequest) throws -> ClarifySummaryResponse {
        try request(type: .clarifyReopen, payload: req, responseType: ClarifySummaryResponse.self)
    }

    func clarifyFinalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        try request(type: .clarifyFinalize, payload: req, responseType: ClarifyFinalizeResponse.self)
    }

    func clarifyGet(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        try request(type: .clarifyGet, payload: req, responseType: ClarifyGetResponse.self)
    }
}

// MARK: - Exploration (v9)

extension GmVerbCaller {
    func exploreOpen(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreOpen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    func exploreKeyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        try request(type: .exploreKeyFileAdd, payload: req, responseType: ExploreKeyFileAddResponse.self)
    }

    func exploreFindingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        try request(type: .exploreFindingAdd, payload: req, responseType: ExploreFindingRowResponse.self)
    }

    func exploreRank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        try request(type: .exploreRank, payload: req, responseType: ExploreRankResponse.self)
    }

    func exploreComplete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreComplete, payload: req, responseType: ExploreSummaryResponse.self)
    }

    func exploreReopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        try request(type: .exploreReopen, payload: req, responseType: ExploreSummaryResponse.self)
    }

    func exploreGet(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        try request(type: .exploreGet, payload: req, responseType: ExploreGetResponse.self)
    }
}

// MARK: - Review (v9)

extension GmVerbCaller {
    func reviewOpen(_ req: ReviewOpenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewOpen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    func reviewFindingAdd(_ req: ReviewFindingAddRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewFindingAdd, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    func reviewRank(_ req: ReviewRankRequest) throws -> ReviewRankResponse {
        try request(type: .reviewRank, payload: req, responseType: ReviewRankResponse.self)
    }

    func reviewResolve(_ req: ReviewResolveRequest) throws -> ReviewFindingRowResponse {
        try request(type: .reviewResolve, payload: req, responseType: ReviewFindingRowResponse.self)
    }

    func reviewComplete(_ req: ReviewCompleteRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewComplete, payload: req, responseType: ReviewSummaryResponse.self)
    }

    func reviewReopen(_ req: ReviewReopenRequest) throws -> ReviewSummaryResponse {
        try request(type: .reviewReopen, payload: req, responseType: ReviewSummaryResponse.self)
    }

    func reviewGet(_ req: ReviewGetRequest) throws -> ReviewGetResponse {
        try request(type: .reviewGet, payload: req, responseType: ReviewGetResponse.self)
    }
}

// MARK: - Briefing (v21)

extension GmVerbCaller {
    func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try request(type: .briefingOpen, payload: req, responseType: BriefingRowResponse.self)
    }

    func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try request(type: .briefingComplete, payload: req, responseType: BriefingRowResponse.self)
    }

    func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try request(type: .briefingGet, payload: req, responseType: BriefingGetResponse.self)
    }

    func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try request(type: .briefingList, payload: req, responseType: BriefingListResponse.self)
    }

    func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try request(type: .briefingStub, payload: req, responseType: BriefingStubResponse.self)
    }
}

// MARK: - Architecture (v7)

extension GmVerbCaller {
    func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try request(type: .archOpen, payload: req, responseType: ArchSummaryResponse.self)
    }

    func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try request(type: .archSummarize, payload: req, responseType: ArchSummaryResponse.self)
    }

    func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try request(type: .archPersistAdd, payload: req, responseType: ArchPersistAddResponse.self)
    }

    func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try request(type: .archFieldAdd, payload: req, responseType: ArchFieldAddResponse.self)
    }

    func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try request(type: .archGeneralAdd, payload: req, responseType: ArchGeneralAddResponse.self)
    }

    func archPropose(_ req: ArchProposeRequest) throws -> ArchSummaryResponse {
        try request(type: .archPropose, payload: req, responseType: ArchSummaryResponse.self)
    }

    func archApprove(_ req: ArchApproveRequest) throws -> ArchSummaryResponse {
        try request(type: .archApprove, payload: req, responseType: ArchSummaryResponse.self)
    }

    func archRevise(_ req: ArchReviseRequest) throws -> ArchSummaryResponse {
        try request(type: .archRevise, payload: req, responseType: ArchSummaryResponse.self)
    }

    func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try request(type: .archOptionAdd, payload: req, responseType: ArchOptionRowResponse.self)
    }

    func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try request(type: .archDecide, payload: req, responseType: ArchDecideResponse.self)
    }

    func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try request(type: .promptStart, payload: req, responseType: BotWorkflowResponse.self)
    }

    func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try request(type: .promptResume, payload: req, responseType: BotWorkflowResponse.self)
    }

    func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try request(type: .botNext, payload: req, responseType: BotNextResponse.self)
    }

    func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try request(type: .botGet, payload: req, responseType: BotWorkflowResponse.self)
    }

    func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try request(type: .agentRegister, payload: req, responseType: AgentRegisterResponse.self)
    }

    func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try request(type: .archGet, payload: req, responseType: ArchGetResponse.self)
    }
}

// MARK: - Git state + config (v7)

extension GmVerbCaller {
    func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        try request(type: .sessionResolve, payload: req, responseType: SessionResolveResponse.self)
    }

    func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        try request(
            type: .instanceCurrentSession,
            payload: req,
            responseType: InstanceCurrentSessionResponse.self
        )
    }

    func pathsGet() throws -> PathsGetResponse {
        try request(type: .pathsGet, payload: PathsGetRequest(), responseType: PathsGetResponse.self)
    }

    func configSet(_ req: ConfigSetRequest) throws -> ConfigSetResponse {
        try request(type: .configSet, payload: req, responseType: ConfigSetResponse.self)
    }
}

// MARK: - Dope (v11)

extension GmVerbCaller {
    func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try request(type: .dopeInit, payload: req, responseType: DopeScopeResponse.self)
    }

    func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try request(type: .dopeList, payload: req, responseType: DopeListResponse.self)
    }

    func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        try request(type: .dopeGet, payload: req, responseType: DopeGetResponse.self)
    }

    func dopePromote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        try request(type: .dopePromote, payload: req, responseType: DopePromoteResponse.self)
    }

    func dopeCogAdd(_ r: DopeCogAddRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogAdd, payload: r, responseType: DopeCogResponse.self)
    }

    func dopeCogUpdate(_ r: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try request(type: .dopeCogUpdate, payload: r, responseType: DopeCogResponse.self)
    }

    func dopeCogDelete(_ r: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try request(type: .dopeCogDelete, payload: r, responseType: DopeCogDeleteResponse.self)
    }

    func dopeCogGet(_ r: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try request(type: .dopeCogGet, payload: r, responseType: DopeCogGetResponse.self)
    }

    func dopeCogElementAdd(_ r: DopeCogElementAddRequest) throws -> DopeCogElementResponse {
        try request(type: .dopeCogElementAdd, payload: r, responseType: DopeCogElementResponse.self)
    }

    func dopeCogElementUpdate(
        _ r: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try request(
            type: .dopeCogElementUpdate,
            payload: r,
            responseType: DopeCogElementResponse.self
        )
    }

    func dopeCogElementDelete(
        _ r: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try request(
            type: .dopeCogElementDelete,
            payload: r,
            responseType: DopeCogDeleteResponse.self
        )
    }

    func dopeSearch(_ req: DopeSearchRequest) throws -> DopeSearchResponse {
        try request(type: .dopeSearch, payload: req, responseType: DopeSearchResponse.self)
    }

    func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeAdd, payload: req, responseType: DopeNodeResponse.self)
    }

    func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        try request(type: .dopeNodeUpdate, payload: req, responseType: DopeNodeResponse.self)
    }

    func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        try request(type: .dopeNodeDelete, payload: req, responseType: DopeNodeDeleteResponse.self)
    }

    func dopeMergePlan(_ req: DopeMergePlanRequest) throws -> DopeMergePlanResponse {
        try request(type: .dopeMergePlan, payload: req, responseType: DopeMergePlanResponse.self)
    }

    func dopeResolve(_ req: DopeResolveRequest) throws -> DopeResolveResponse {
        try request(type: .dopeResolve, payload: req, responseType: DopeResolveResponse.self)
    }

    func dopeReadRepo(_ req: DopeReadRepoRequest) throws -> DopeReadRepoResponse {
        try request(type: .dopeReadRepo, payload: req, responseType: DopeReadRepoResponse.self)
    }

    func dopeWriteRepo(_ req: DopeWriteRepoRequest) throws -> DopeWriteRepoResponse {
        try request(type: .dopeWriteRepo, payload: req, responseType: DopeWriteRepoResponse.self)
    }

    func dopeIngest(_ req: DopeIngestRequest) throws -> DopeIngestResponse {
        try request(type: .dopeIngest, payload: req, responseType: DopeIngestResponse.self)
    }
}

// MARK: - Diagram (v15)

extension GmVerbCaller {
    func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try request(type: .diagramInit, payload: req, responseType: DiagramResponse.self)
    }

    func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        try request(type: .diagramList, payload: req, responseType: DiagramListResponse.self)
    }

    func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        try request(type: .diagramGet, payload: req, responseType: DiagramGetResponse.self)
    }

    func diagramNodeAdd(_ req: DiagramNodeAddRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeAdd, payload: req, responseType: DiagramNodeResponse.self)
    }

    func diagramNodeUpdate(_ req: DiagramNodeUpdateRequest) throws -> DiagramNodeResponse {
        try request(type: .diagramNodeUpdate, payload: req, responseType: DiagramNodeResponse.self)
    }

    func diagramNodeDelete(_ req: DiagramNodeDeleteRequest) throws -> DiagramNodeDeleteResponse {
        try request(type: .diagramNodeDelete, payload: req, responseType: DiagramNodeDeleteResponse.self)
    }

    func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        try request(type: .diagramBatchApply, payload: req, responseType: DiagramBatchApplyResponse.self)
    }

    func diagramSearch(_ req: DiagramSearchRequest) throws -> DiagramSearchResponse {
        try request(type: .diagramSearch, payload: req, responseType: DiagramSearchResponse.self)
    }

    func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        try request(type: .diagramDelete, payload: req, responseType: DiagramDeleteResponse.self)
    }

    func diagramWriteRepo(_ req: DiagramWriteRepoRequest) throws -> DiagramWriteRepoResponse {
        try request(type: .diagramWriteRepo, payload: req, responseType: DiagramWriteRepoResponse.self)
    }

    func diagramIngest(_ req: DiagramIngestRequest) throws -> DiagramIngestResponse {
        try request(type: .diagramIngest, payload: req, responseType: DiagramIngestResponse.self)
    }
}
