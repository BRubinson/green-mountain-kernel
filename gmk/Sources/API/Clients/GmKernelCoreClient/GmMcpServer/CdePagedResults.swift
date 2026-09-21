import Foundation

// THE PAGE SHAPES THE CDE SERVER RENDERS. Paging lives HERE and not in the
// daemon: GMVibes reads whole typed records in-process through the same verb
// layer and is not budget-bound, so the verb layer serves both unchanged and
// this file is the one place a record is cut to fit the harness's result cap.
// Every builder walks its read's fill order over the IN-MEMORY response; the
// record is re-read from the daemon on every page, which is bounded and local.

// MARK: - Cde-layer stubs (the SDK has no blob-free form of these rows)

struct CdeExplorationSummaryStub: Encodable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let agentType: String
    let agentId: String?
    let status: String
    let overviewChars: Int
    let createdAt: String
    let updatedAt: String

    init(_ row: ExplorationSummaryRow) {
        uuid = row.uuid
        version = row.version
        promptUuid = row.promptUuid
        agentType = row.agentType
        agentId = row.agentId
        status = row.status
        overviewChars = row.overview.count
        createdAt = row.createdAt
        updatedAt = row.updatedAt
    }
}

struct CdeReviewSummaryStub: Encodable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let status: String
    let verdict: String?
    let overviewChars: Int
    let agentId: String?
    let createdAt: String
    let updatedAt: String

    init(_ row: ReviewSummaryRow) {
        uuid = row.uuid
        version = row.version
        promptUuid = row.promptUuid
        status = row.status
        verdict = row.verdict
        overviewChars = row.overview.count
        agentId = row.agentId
        createdAt = row.createdAt
        updatedAt = row.updatedAt
    }
}

struct CdeArchitectureSummaryStub: Encodable {
    let uuid: String
    let version: Int64
    let promptUuid: String
    let status: String
    let bodyChars: Int
    let decisionRationaleChars: Int
    let createdAt: String
    let updatedAt: String

    init(_ row: ArchitectureSummaryRow) {
        uuid = row.uuid
        version = row.version
        promptUuid = row.promptUuid
        status = row.status
        bodyChars = row.body.count
        decisionRationaleChars = row.decisionRationale?.count ?? 0
        createdAt = row.createdAt
        updatedAt = row.updatedAt
    }
}

struct CdeBriefingStub: Encodable {
    let uuid: String
    let version: Int64
    let sessionUuid: String
    let promptUuid: String?
    let briefingForStep: String
    let status: String
    let agentId: String?
    let dopeScopeUuid: String?
    let dopeScopeRevision: Int64?
    let dopeRefCount: Int
    let kbiteRefCount: Int
    let fileChangeRefCount: Int
    let createdAt: String
    let updatedAt: String

    init(_ row: AgentBriefingRow) {
        uuid = row.uuid
        version = row.version
        sessionUuid = row.sessionUuid
        promptUuid = row.promptUuid
        briefingForStep = row.briefingForStep
        status = row.status
        agentId = row.agentId
        dopeScopeUuid = row.dopeScopeUuid
        dopeScopeRevision = row.dopeScopeRevision
        dopeRefCount = row.dopeRefs.count
        kbiteRefCount = row.kbiteRefs.count
        fileChangeRefCount = row.fileChangeRefs.count
        createdAt = row.createdAt
        updatedAt = row.updatedAt
    }
}

// MARK: - Page results

struct CdeExplorationPage: Encodable {
    let summaryStubs: [CdeExplorationSummaryStub]
    let keyFiles: [ExplorationKeyFileRow]
    let findings: [ExplorationFindingRow]
    let findingStubs: [ExplorationFindingStub]
    let windows: [CdeTextWindow]
    let page: CdePage

    /// `findingUuid` pins one full row and empties every other region.
    static func build(
        _ response: ExploreGetResponse,
        pager: inout CdePager,
        findingUuid: String?
    ) throws -> Self {
        let stubs = response.summaries.map(CdeExplorationSummaryStub.init)
        pager.charge(stubs)
        var windows: [CdeTextWindow] = []
        if let findingUuid {
            guard let row = response.findings.first(where: { $0.uuid == findingUuid }) else {
                throw ToolError(message: "no exploration finding '\(findingUuid)' on this prompt")
            }
            let findings = try pager.rows("findings", [row])
            return Self(
                summaryStubs: stubs,
                keyFiles: [],
                findings: findings,
                findingStubs: [],
                windows: [],
                page: try pager.page()
            )
        }
        for summary in response.summaries {
            if let window = try pager.text("overview:\(summary.uuid)", summary.overview) {
                windows.append(window)
            }
        }
        let keyFiles = try pager.rows("key_files", response.keyFiles)
        let findings = try pager.rows("findings", response.findings)
        let findingStubs = try pager.rows("finding_stubs", response.findingStubs)
        return Self(
            summaryStubs: stubs,
            keyFiles: keyFiles,
            findings: findings,
            findingStubs: findingStubs,
            windows: windows,
            page: try pager.page()
        )
    }
}

struct CdeReviewPage: Encodable {
    let summaryStub: CdeReviewSummaryStub
    let findings: [ReviewFindingRow]
    let findingStubs: [ReviewFindingStub]
    let windows: [CdeTextWindow]
    let page: CdePage

    static func build(
        _ response: ReviewGetResponse,
        pager: inout CdePager,
        findingUuid: String?
    ) throws -> Self {
        let stub = CdeReviewSummaryStub(response.summary)
        pager.charge(stub)
        if let findingUuid {
            guard let row = response.findings.first(where: { $0.uuid == findingUuid }) else {
                throw ToolError(message: "no review finding '\(findingUuid)' on this prompt")
            }
            let findings = try pager.rows("findings", [row])
            return Self(summaryStub: stub, findings: findings, findingStubs: [], windows: [], page: try pager.page())
        }
        var windows: [CdeTextWindow] = []
        if let window = try pager.text("overview", response.summary.overview) { windows.append(window) }
        let findings = try pager.rows("findings", response.findings)
        let findingStubs = try pager.rows("finding_stubs", response.findingStubs)
        return Self(
            summaryStub: stub,
            findings: findings,
            findingStubs: findingStubs,
            windows: windows,
            page: try pager.page()
        )
    }
}

struct CdeClarificationPage: Encodable {
    let summary: ClarificationSummaryRow
    let questions: [ClarificationQuestionRow]
    let notes: [ClarificationNoteRow]
    let noteStubs: [ClarificationNoteStub]
    /// The package is ALWAYS a stub here — it has its own door.
    let carePackageStub: CarePackageStub?
    let page: CdePage

    static func build(
        _ response: ClarifyGetResponse,
        pager: inout CdePager,
        noteUuid: String?
    ) throws -> Self {
        let packageStub = response.carePackageStub ?? response.carePackage.map(CarePackageStub.init(package:))
        pager.charge(response.summary)
        pager.charge(response.questions)
        pager.charge(packageStub)
        if let noteUuid {
            guard let row = response.notes.first(where: { $0.uuid == noteUuid }) else {
                throw ToolError(message: "no clarification note '\(noteUuid)' on this prompt")
            }
            let notes = try pager.rows("notes", [row])
            return Self(
                summary: response.summary,
                questions: response.questions,
                notes: notes,
                noteStubs: [],
                carePackageStub: packageStub,
                page: try pager.page()
            )
        }
        let notes = try pager.rows("notes", response.notes)
        let noteStubs = try pager.rows("note_stubs", response.noteStubs ?? [])
        return Self(
            summary: response.summary,
            questions: response.questions,
            notes: notes,
            noteStubs: noteStubs,
            carePackageStub: packageStub,
            page: try pager.page()
        )
    }
}

struct CdeCarePackagePage: Encodable {
    let packageStub: CarePackageStub
    let dopeRefs: [CarePackageDopeRefRow]
    let kbiteRefs: [CarePackageKbiteRefRow]
    let explorationRefStubs: [CarePackageExplorationRefStub]
    let windows: [CdeTextWindow]
    let page: CdePage

    static func build(
        _ package: CarePackageRow,
        pager: inout CdePager,
        refUuid: String?
    ) throws -> Self {
        let stub = CarePackageStub(package: package)
        pager.charge(stub)
        var windows: [CdeTextWindow] = []
        if let window = try pager.text("clarified_intent", package.clarifiedIntent) { windows.append(window) }
        if let refUuid {
            guard let ref = package.explorationRefs.first(where: { $0.uuid == refUuid }) else {
                throw ToolError(message: "no exploration ref '\(refUuid)' on this care package")
            }
            if let window = try pager.text("curated_body:\(refUuid)", ref.curatedBody) { windows.append(window) }
        }
        let dopeRefs = try pager.rows("dope_refs", package.dopeRefs)
        let kbiteRefs = try pager.rows("kbite_refs", package.kbiteRefs)
        let allStubs = package.explorationRefs.map { ref -> CarePackageExplorationRefStub in
            let body = CdeExcerpt.take(ref.curatedBody)
            return CarePackageExplorationRefStub(
                uuid: ref.uuid,
                curatedTitle: ref.curatedTitle,
                filePath: ref.filePath,
                sourceFindingUuid: ref.sourceFindingUuid,
                seq: ref.seq,
                curatedBodyExcerpt: body.excerpt,
                curatedBodyChars: body.chars,
                curatedBodyTruncated: body.truncated
            )
        }
        let refStubs = try pager.rows("exploration_ref_stubs", allStubs)
        return Self(
            packageStub: stub,
            dopeRefs: dopeRefs,
            kbiteRefs: kbiteRefs,
            explorationRefStubs: refStubs,
            windows: windows,
            page: try pager.page()
        )
    }
}

struct CdeArchitecturePage: Encodable {
    let summaryStub: CdeArchitectureSummaryStub
    let optionStubs: [ArchitectureOptionStub]
    let orderingRespected: Bool?
    let persistenceChanges: [ArchPersistenceChangeRow]
    let generalChangeStubs: [ArchGeneralChangeStub]
    let unplannedChanges: [UnplannedChangeRow]
    let windows: [CdeTextWindow]
    let page: CdePage

    /// Built from the UNNARROWED daemon response: every option body and every
    /// change_code is in hand, and this layer decides what becomes a window.
    static func build(
        _ response: ArchGetResponse,
        pager: inout CdePager,
        optionUuid: String?,
        changeUuid: String?,
        limit: Int?
    ) throws -> Self {
        let summaryStub = CdeArchitectureSummaryStub(response.summary)
        let optionStubs = response.options.map { option in
            ArchitectureOptionStub(
                uuid: option.uuid,
                agentName: option.agentName,
                agentId: option.agentId,
                status: option.status,
                selected: option.status == "selected",
                bodyChars: option.body.count
            )
        }
        pager.charge(summaryStub)
        pager.charge(optionStubs)
        var windows: [CdeTextWindow] = []
        if let window = try pager.text("body", response.summary.body) { windows.append(window) }
        if let rationale = response.summary.decisionRationale, !rationale.isEmpty,
            let window = try pager.text("decision_rationale", rationale)
        {
            windows.append(window)
        }
        if let optionUuid {
            guard let option = response.options.first(where: { $0.uuid == optionUuid }) else {
                throw ToolError(message: "no architecture option '\(optionUuid)' on this prompt")
            }
            if let window = try pager.text("option_body:\(optionUuid)", option.body) { windows.append(window) }
        }
        if let changeUuid {
            guard let change = response.generalChanges.first(where: { $0.uuid == changeUuid }) else {
                throw ToolError(message: "no general change '\(changeUuid)' on this prompt")
            }
            if let window = try pager.text("change_code:\(changeUuid)", change.changeCode) { windows.append(window) }
        }
        let persistence = try pager.rows("persistence_changes", response.persistenceChanges)
        let roster = limit.map { Array(response.generalChanges.prefix(max($0, 1))) } ?? response.generalChanges
        let allStubs = roster.map { change -> ArchGeneralChangeStub in
            let code = CdeExcerpt.take(change.changeCode)
            return ArchGeneralChangeStub(
                uuid: change.uuid,
                seq: change.seq,
                filePath: change.filePath,
                className: change.className,
                reasonBrief: change.reasonBrief,
                changeDepth: change.changeDepth,
                changeCodeExcerpt: code.excerpt,
                changeCodeChars: code.chars,
                changeCodeTruncated: code.truncated,
                implementation: change.implementation
            )
        }
        let generalStubs = try pager.rows("general_change_stubs", allStubs)
        let unplanned = try pager.rows("unplanned_changes", response.unplannedChanges)
        return Self(
            summaryStub: summaryStub,
            optionStubs: optionStubs,
            orderingRespected: response.orderingRespected,
            persistenceChanges: persistence,
            generalChangeStubs: generalStubs,
            unplannedChanges: unplanned,
            windows: windows,
            page: try pager.page()
        )
    }
}

struct CdeFileChangePage: Encodable {
    let changes: [FileChangeRow]
    let page: CdePage

    static func build(_ response: FileChangeListResponse, pager: inout CdePager) throws -> Self {
        Self(changes: try pager.rows("changes", response.changes), page: try pager.page())
    }
}

/// One shape for every search: the daemon's ranked hits, paged.
struct CdeHitsPage<Hit: Encodable>: Encodable {
    let hits: [Hit]
    let page: CdePage

    static func build(_ hits: [Hit], pager: inout CdePager) throws -> Self {
        Self(hits: try pager.rows("hits", hits), page: try pager.page())
    }
}

struct CdeCatalogPage: Encodable {
    let instances: [InstanceRow]
    let sessions: [SessionStub]
    let page: CdePage

    /// Sessions page; instances are the parents of the sessions on the page.
    static func build(_ response: CatalogSearchResponse, pager: inout CdePager) throws -> Self {
        let sessions = try pager.rows("sessions", response.sessions)
        let parents = Set(sessions.map(\.instanceUuid))
        let instances = response.instances.filter { parents.contains($0.uuid) }
        return Self(instances: instances, sessions: sessions, page: try pager.page())
    }
}

struct CdePromptPage: Encodable {
    let promptStub: PromptStub
    let artifacts: [ArtifactRow]
    let kbiteCodes: [String]
    let changeSummary: ChangeSummary
    let windows: [CdeTextWindow]
    let page: CdePage

    static func build(_ response: PromptGetResponse, pager: inout CdePager) throws -> Self {
        let row = response.prompt
        let stub = PromptStub(
            uuid: row.uuid,
            sessionUuid: row.sessionUuid,
            seq: row.seq,
            code: row.code,
            name: row.name,
            status: row.status,
            version: row.version,
            gmfsRelativeStoragePath: row.gmfsRelativeStoragePath,
            reports: nil,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
        pager.charge(stub)
        pager.charge(response.kbiteCodes)
        pager.charge(response.changeSummary)
        var windows: [CdeTextWindow] = []
        // An EMPTY field is still a region (0 of 0) so "empty" and "not yet
        // paged" stay distinguishable.
        for (region, text) in [("detail", row.detail), ("backstory", row.backstory), ("goal", row.goal)] {
            if let window = try pager.text(region, text) { windows.append(window) }
        }
        let artifacts = try pager.rows("artifacts", response.artifacts)
        return Self(
            promptStub: stub,
            artifacts: artifacts,
            kbiteCodes: response.kbiteCodes,
            changeSummary: response.changeSummary,
            windows: windows,
            page: try pager.page()
        )
    }
}

struct CdeBriefingPage: Encodable {
    let briefingStub: CdeBriefingStub
    let staleness: BriefingStaleness
    let dopeRefs: [AgentBriefingDopeRefRow]
    let kbiteRefs: [AgentBriefingKbiteRefRow]
    let fileChangeRefs: [AgentBriefingFileChangeRefRow]
    let page: CdePage

    static func build(_ response: BriefingGetResponse, pager: inout CdePager) throws -> Self {
        let stub = CdeBriefingStub(response.briefing)
        pager.charge(stub)
        pager.charge(response.staleness)
        let dope = try pager.rows("dope_refs", response.briefing.dopeRefs)
        let kbite = try pager.rows("kbite_refs", response.briefing.kbiteRefs)
        let files = try pager.rows("file_change_refs", response.briefing.fileChangeRefs)
        return Self(
            briefingStub: stub,
            staleness: response.staleness,
            dopeRefs: dope,
            kbiteRefs: kbite,
            fileChangeRefs: files,
            page: try pager.page()
        )
    }
}
