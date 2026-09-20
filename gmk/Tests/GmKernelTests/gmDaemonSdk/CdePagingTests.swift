import Foundation
import GmDaemonSdk
import XCTest

// MARK: - The pager's own arithmetic (no kernel)

final class CdePagerTests: XCTestCase {

    private struct Row: Encodable {
        let id: Int
        let body: String
    }

    private func rows(_ count: Int, chars: Int) -> [Row] {
        (0..<count).map { Row(id: $0, body: String(repeating: "x", count: chars)) }
    }

    func testAtLeastOneRowLandsEvenWhenItAloneExceedsTheBudget() throws {
        var pager = try CdePager(pageBytes: 4_096, cursor: nil)
        let taken = try pager.rows("big", rows(2, chars: 10_000))
        XCTAssertEqual(taken.count, 1)
        let page = try pager.page()
        XCTAssertEqual(page.nextCursor, "big:1")
        XCTAssertEqual(page.regions, [CdePageRegion(name: "big", returned: 1, total: 2)])
    }

    func testRowsStopBeforeTheOneThatWouldCrossAndReportTheTotal() throws {
        var pager = try CdePager(pageBytes: 4_096, cursor: nil)
        let taken = try pager.rows("r", rows(50, chars: 500))
        XCTAssertGreaterThan(taken.count, 1)
        XCTAssertLessThan(taken.count, 50)
        let page = try pager.page()
        XCTAssertEqual(page.nextCursor, "r:\(taken.count)")
        XCTAssertEqual(page.regions.first?.total, 50)
        XCTAssertEqual(page.regions.first?.returned, taken.count)
    }

    func testLaterRegionsReportZeroOnceExhaustedAndKeepTheirTotals() throws {
        var pager = try CdePager(pageBytes: 4_096, cursor: nil)
        _ = try pager.rows("first", rows(50, chars: 500))
        let second = try pager.rows("second", rows(3, chars: 10))
        XCTAssertTrue(second.isEmpty)
        let page = try pager.page()
        XCTAssertEqual(page.regions.last, CdePageRegion(name: "second", returned: 0, total: 3))
        XCTAssertTrue(page.nextCursor?.hasPrefix("first:") ?? false)
    }

    func testCursorIntoALaterRegionSkipsEarlierOnesWithTrueTotals() throws {
        var pager = try CdePager(pageBytes: 4_096, cursor: "second:1")
        let first = try pager.rows("first", rows(5, chars: 10))
        let second = try pager.rows("second", rows(3, chars: 10))
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second.map(\.id), [1, 2])
        let page = try pager.page()
        XCTAssertEqual(page.regions[0], CdePageRegion(name: "first", returned: 0, total: 5))
        XCTAssertEqual(page.regions[1], CdePageRegion(name: "second", returned: 2, total: 3))
        XCTAssertNil(page.nextCursor)
    }

    func testTextWindowsReassembleTheBlobAndNeverSplitAGrapheme() throws {
        let flag = "🇺🇸"
        let family = "👨‍👩‍👧‍👦"
        let blob = String(repeating: flag + family + "ab", count: 2_000)
        var cursor: String?
        var pieces: [String] = []
        var offsets: [Int] = []
        repeat {
            var pager = try CdePager(pageBytes: 4_096, cursor: cursor)
            if let window = try pager.text("blob", blob) {
                pieces.append(window.text)
                offsets.append(window.offset)
                XCTAssertEqual(window.totalChars, blob.count)
                XCTAssertEqual(window.returnedChars, window.text.count)
                if window.offset + window.returnedChars < window.totalChars {
                    XCTAssertGreaterThanOrEqual(window.returnedChars, CdePager.minimumTextSlice)
                }
            }
            cursor = try pager.page().nextCursor
        } while cursor != nil
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertEqual(pieces.joined(), blob)
        XCTAssertEqual(offsets.first, 0)
        for piece in pieces {
            XCTAssertFalse(piece.unicodeScalars.first.map(\.properties.isJoinControl) ?? false)
        }
    }

    func testEmptyTextIsStillARegion() throws {
        var pager = try CdePager(pageBytes: 4_096, cursor: nil)
        XCTAssertNil(try pager.text("goal", ""))
        XCTAssertEqual(try pager.page().regions, [CdePageRegion(name: "goal", returned: 0, total: 0)])
    }

    func testBadCursorsAreRefused() throws {
        XCTAssertThrowsError(try CdePager(pageBytes: 4_096, cursor: "nonsense"))
        XCTAssertThrowsError(try CdePager(pageBytes: 4_096, cursor: "r:-1"))
        var unknown = try CdePager(pageBytes: 4_096, cursor: "elsewhere:0")
        _ = try unknown.rows("r", rows(2, chars: 10))
        XCTAssertThrowsError(try unknown.page())
        var past = try CdePager(pageBytes: 4_096, cursor: "r:9")
        XCTAssertThrowsError(try past.rows("r", rows(2, chars: 10)))
    }

    func testCursorRoundTripsThroughItsWireForm() {
        let cursor = CdePageCursor("overview:ab:cd:12")
        XCTAssertEqual(cursor?.region, "overview:ab:cd")
        XCTAssertEqual(cursor?.position, 12)
        XCTAssertEqual(cursor?.wireString, "overview:ab:cd:12")
    }
}

// MARK: - The cde doors over the wire (MCP_CALL)

/// Every paged read is exercised the way the harness reaches it: `MCP_CALL`
/// into a booted kernel, the rendered text parsed back as JSON. The fixtures
/// are deliberately oversized so every read needs more than one page.
final class CdePagingWireTests: KernelBackedTestCase {

    private struct Fixture {
        let sessionUuid: String
        let promptUuid: String
        let project: ProjectContext
        let instance: InstanceContext
        let session: SessionContext
        let findingUuids: [String]
        let overview: String
        let intent: String
        let archBody: String
        let detail: String
        let noteUuids: [String]
        let changeUuids: [String]
    }

    nonisolated(unsafe) private static var fixture: Fixture?

    private func filler(_ tag: String, _ chars: Int) -> String {
        String(repeating: "\(tag) lorem ipsum dolor sit amet ", count: chars / 30 + 1).prefix(chars).description
    }

    /// Built ONCE per process: every case reads the same oversized prompt.
    private func makeFixture() throws -> Fixture {
        if let fixture = Self.fixture { return fixture }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let code = "t_page_\(id)"
        let repo = env.root.appendingPathComponent("repos/\(code)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let project = ProjectContext(
            gitRepoName: code,
            code: code,
            name: code,
            gmfsRelativeStoragePath: "projects/\(code)"
        )
        let instance = InstanceContext(
            code: "\(code)_1",
            name: code,
            absoluteFileSystemPath: repo.path,
            gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1"
        )
        let session = SessionContext(
            code: "main",
            name: "main",
            backstory: "",
            goal: "",
            gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main"
        )
        let ensured = try env.send(
            .contextEnsure,
            ContextEnsureRequest(project: project, instance: instance, session: session),
            ContextEnsureResponse.self
        )
        let detail = filler("detail", 80_000)
        let prompt = try env.send(
            .promptCreate,
            PromptCreateRequest(
                sessionUuid: ensured.sessionUuid,
                name: "paging fixture",
                backstory: filler("back", 3_000),
                goal: "",
                detail: detail
            ),
            PromptRow.self
        )
        _ = try env.send(
            .promptStart,
            PromptStartRequest(promptUuid: prompt.uuid, variant: .bot),
            BotWorkflowResponse.self
        )
        let briefing = try env.send(
            .briefingOpen,
            BriefingOpenRequest(promptUuid: prompt.uuid, briefingForStep: "initial"),
            BriefingRowResponse.self
        )
        _ = try env.send(
            .briefingComplete,
            BriefingCompleteRequest(
                briefingUuid: briefing.briefing.uuid,
                expectedVersion: briefing.briefing.version,
                dopeRefs: (0..<40).map { "ghost.domain.entity\($0)" },
                kbiteRefs: [],
                fileChangeRefs: []
            ),
            BriefingRowResponse.self
        )

        let (findingUuids, overview) = try seedExploration(prompt.uuid)
        let (noteUuids, intent) = try seedClarification(prompt.uuid)
        let (changeUuids, archBody) = try seedArchitecture(prompt.uuid)
        try seedReview(prompt.uuid)
        try seedFileChanges(prompt.uuid, project: project, instance: instance, session: session)

        let built = Fixture(
            sessionUuid: ensured.sessionUuid,
            promptUuid: prompt.uuid,
            project: project,
            instance: instance,
            session: session,
            findingUuids: findingUuids,
            overview: overview,
            intent: intent,
            archBody: archBody,
            detail: detail,
            noteUuids: noteUuids,
            changeUuids: changeUuids
        )
        Self.fixture = built
        return built
    }

    /// 40 findings of 3 KB and a 60 KB overview.
    private func seedExploration(_ promptUuid: String) throws -> ([String], String) {
        let explore = try env.send(
            .exploreOpen,
            ExploreOpenRequest(promptUuid: promptUuid, agentType: "general", agentId: "t"),
            ExploreSummaryResponse.self
        )
        var findingUuids: [String] = []
        for index in 0..<40 {
            let row = try env.send(
                .exploreFindingAdd,
                ExploreFindingAddRequest(
                    summaryUuid: explore.summary.uuid,
                    kind: .other,
                    title: "finding \(index)",
                    body: filler("f\(index)", 3_000),
                    agentName: "general"
                ),
                ExploreFindingRowResponse.self
            )
            findingUuids.append(row.finding.uuid)
        }
        let overview = filler("overview", 60_000)
        _ = try env.send(
            .exploreComplete,
            ExploreCompleteRequest(
                summaryUuid: explore.summary.uuid,
                expectedVersion: explore.summary.version,
                overview: overview
            ),
            ExploreSummaryResponse.self
        )
        return (findingUuids, overview)
    }

    /// 30 notes of 2 KB, plus a care package with a 25 KB intent and 20
    /// curated copies of 5 KB.
    private func seedClarification(_ promptUuid: String) throws -> ([String], String) {
        let clarify = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: promptUuid),
            ClarifySummaryResponse.self
        )
        var noteUuids: [String] = []
        for index in 0..<30 {
            let row = try env.send(
                .clarifyNoteAdd,
                ClarifyNoteAddRequest(summaryUuid: clarify.summary.uuid, body: filler("n\(index)", 2_000)),
                ClarifyNoteRowResponse.self
            )
            noteUuids.append(row.note.uuid)
        }
        let package = try env.send(
            .carePackageOpen,
            CarePackageOpenRequest(summaryUuid: clarify.summary.uuid),
            CarePackageResponse.self
        )
        for index in 0..<20 {
            _ = try env.send(
                .carePackageRefAdd,
                CarePackageRefAddRequest(
                    packageUuid: package.package.uuid,
                    kind: .exploration,
                    curatedTitle: "curated \(index)",
                    curatedBody: filler("c\(index)", 5_000)
                ),
                CarePackageResponse.self
            )
        }
        let intent = filler("intent", 25_000)
        let refreshed = try env.send(
            .carePackageGet,
            CarePackageGetRequest(promptUuid: promptUuid),
            CarePackageResponse.self
        )
        _ = try env.send(
            .carePackageComplete,
            CarePackageCompleteRequest(
                packageUuid: refreshed.package.uuid,
                expectedVersion: refreshed.package.version,
                clarifiedIntent: intent
            ),
            CarePackageResponse.self
        )
        return (noteUuids, intent)
    }

    /// A 40 KB body and 30 general changes of 4 KB.
    private func seedArchitecture(_ promptUuid: String) throws -> ([String], String) {
        let arch = try env.send(.archOpen, ArchOpenRequest(promptUuid: promptUuid), ArchSummaryResponse.self)
        let archBody = filler("plan", 40_000)
        _ = try env.send(
            .archSummarize,
            ArchSummarizeRequest(
                summaryUuid: arch.summary.uuid,
                expectedVersion: arch.summary.version,
                body: archBody
            ),
            ArchSummaryResponse.self
        )
        var changeUuids: [String] = []
        for index in 0..<30 {
            let row = try env.send(
                .archGeneralAdd,
                ArchGeneralAddRequest(
                    summaryUuid: arch.summary.uuid,
                    filePath: "src/file\(index).swift",
                    className: nil,
                    reasonBrief: "change \(index)",
                    changeDepth: .draft,
                    changeCode: filler("code\(index)", 4_000)
                ),
                ArchGeneralAddResponse.self
            )
            changeUuids.append(row.change.uuid)
        }
        return (changeUuids, archBody)
    }

    /// 40 review findings of 3 KB.
    private func seedReview(_ promptUuid: String) throws {
        let review = try env.send(
            .reviewOpen,
            ReviewOpenRequest(promptUuid: promptUuid),
            ReviewSummaryResponse.self
        )
        for index in 0..<40 {
            _ = try env.send(
                .reviewFindingAdd,
                ReviewFindingAddRequest(
                    summaryUuid: review.summary.uuid,
                    kind: .other,
                    title: "review \(index)",
                    body: filler("r\(index)", 3_000),
                    agentName: "reviewer"
                ),
                ReviewFindingRowResponse.self
            )
        }
    }

    /// 240 file change rows, each with a few ranges.
    private func seedFileChanges(
        _ promptUuid: String,
        project: ProjectContext,
        instance: InstanceContext,
        session: SessionContext
    ) throws {
        for index in 0..<240 {
            _ = try env.send(
                .fileChangeAdd,
                FileChangeAdd(
                    project: project,
                    instance: instance,
                    session: session,
                    promptUuid: promptUuid,
                    relativePath: "src/file\(index % 7).swift",
                    changeKind: .edit,
                    ranges: [
                        ChangeRange(lineStart: 1, lineEnd: 10, changedContent: nil),
                        ChangeRange(lineStart: 20 + index, lineEnd: 30 + index, changedContent: nil),
                    ]
                ),
                FileChangeAddResponse.self
            )
        }
    }

    // MARK: Driving the cde door

    private func call(_ tool: String, _ arguments: [String: GmJsonValue]) throws -> [String: Any] {
        let response = try env.send(
            .mcpCall,
            McpCallRequest(tool: tool, arguments: .object(arguments), identity: GmHarnessIdentity()),
            McpCallResponse.self
        )
        XCTAssertFalse(response.isError, "\(tool): \(response.text.prefix(300))")
        XCTAssertLessThanOrEqual(response.text.utf8.count, CdeResultBudget.maxBytes, "\(tool) overflowed the budget")
        let object = try JSONSerialization.jsonObject(with: Data(response.text.utf8)) as? [String: Any]
        let result = try XCTUnwrap(object, "\(tool) did not render an object")
        XCTAssertNil(result["gmcc_oversize"], "\(tool) fell through to the withhold envelope")
        return result
    }

    /// Walk every page of a read; returns the pages in order.
    private func allPages(_ tool: String, _ arguments: [String: GmJsonValue]) throws -> [[String: Any]] {
        var collected: [[String: Any]] = []
        var cursor: String?
        repeat {
            var args = arguments
            if let cursor { args["cursor"] = .string(cursor) }
            let page = try call(tool, args)
            collected.append(page)
            let meta = try XCTUnwrap(page["page"] as? [String: Any], "\(tool): no page block")
            cursor = meta["nextCursor"] as? String
        } while cursor != nil
        XCTAssertGreaterThan(collected.count, 1, "\(tool): the fixture was meant to need more than one page")
        return collected
    }

    private func windows(_ pages: [[String: Any]], region: String) -> String {
        pages
            .flatMap { ($0["windows"] as? [[String: Any]]) ?? [] }
            .filter { ($0["region"] as? String) == region }
            .sorted { ($0["offset"] as? Int ?? 0) < ($1["offset"] as? Int ?? 0) }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    private func rows(_ pages: [[String: Any]], key: String) -> [[String: Any]] {
        pages.flatMap { ($0["\(key)"] as? [[String: Any]]) ?? [] }
    }

    private func total(_ page: [String: Any], region: String) -> Int? {
        ((page["page"] as? [String: Any])?["regions"] as? [[String: Any]])?
            .first { ($0["name"] as? String) == region }?["total"] as? Int
    }

    // MARK: Cases

    func testExplorationPagesUnionToTheWholeRecord() throws {
        let fixture = try makeFixture()
        let pages = try allPages("rpir_get_exploration", ["prompt_uuid": .string(fixture.promptUuid)])
        let findings = rows(pages, key: "findings")
        XCTAssertEqual(Set(findings.compactMap { $0["uuid"] as? String }), Set(fixture.findingUuids))
        XCTAssertEqual(total(pages[0], region: "findings"), 40)
        let overviewRegion =
            "overview:"
            + (try XCTUnwrap(
                (pages[0]["summaryStubs"] as? [[String: Any]])?.first?["uuid"] as? String
            ))
        XCTAssertEqual(windows(pages, region: overviewRegion), fixture.overview)
        XCTAssertEqual(((pages[0]["summaryStubs"] as? [[String: Any]])?.first?["overviewChars"] as? Int), 60_000)
    }

    func testFindingUuidPinsOneBody() throws {
        let fixture = try makeFixture()
        let page = try call(
            "rpir_get_exploration",
            ["prompt_uuid": .string(fixture.promptUuid), "finding_uuid": .string(fixture.findingUuids[7])]
        )
        let findings = try XCTUnwrap(page["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?["uuid"] as? String, fixture.findingUuids[7])
        XCTAssertNil((page["page"] as? [String: Any])?["nextCursor"])
    }

    func testReviewPagesUnionToTheWholeRecord() throws {
        let fixture = try makeFixture()
        let pages = try allPages("rpir_get_review", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertEqual(rows(pages, key: "findings").count, 40)
        XCTAssertEqual(total(pages[0], region: "findings"), 40)
    }

    func testClarificationPagesNotesAndStubsThePackage() throws {
        let fixture = try makeFixture()
        let pages = try allPages("rpir_get_clarification", ["prompt_uuid": .string(fixture.promptUuid)])
        let notes = rows(pages, key: "notes")
        XCTAssertEqual(Set(notes.compactMap { $0["uuid"] as? String }), Set(fixture.noteUuids))
        XCTAssertNotNil(pages[0]["carePackageStub"])
        XCTAssertNil(pages[0]["carePackage"])
        let pinned = try call(
            "rpir_get_clarification",
            ["prompt_uuid": .string(fixture.promptUuid), "note_uuid": .string(fixture.noteUuids[3])]
        )
        XCTAssertEqual((pinned["notes"] as? [[String: Any]])?.count, 1)
    }

    func testCarePackageWindowsTheIntentAndStubsTheRefs() throws {
        let fixture = try makeFixture()
        let pages = try allPages("rpir_get_care_package", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertEqual(windows(pages, region: "clarified_intent"), fixture.intent)
        XCTAssertEqual(rows(pages, key: "explorationRefStubs").count, 20)
        let refUuid = try XCTUnwrap(rows(pages, key: "explorationRefStubs").first?["uuid"] as? String)
        let one = try allPages(
            "rpir_get_care_package",
            ["prompt_uuid": .string(fixture.promptUuid), "ref_uuid": .string(refUuid)]
        )
        XCTAssertEqual(windows(one, region: "curated_body:\(refUuid)").count, 5_000)
    }

    func testArchitectureWindowsTheBodyAndStubsTheChanges() throws {
        let fixture = try makeFixture()
        let pages = try allPages("rpir_get_architecture", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertEqual(windows(pages, region: "body"), fixture.archBody)
        let stubs = rows(pages, key: "generalChangeStubs")
        XCTAssertEqual(Set(stubs.compactMap { $0["uuid"] as? String }), Set(fixture.changeUuids))
        XCTAssertEqual(total(pages[0], region: "general_change_stubs"), 30)
        let one = try allPages(
            "rpir_get_architecture",
            ["prompt_uuid": .string(fixture.promptUuid), "change_uuid": .string(fixture.changeUuids[5])]
        )
        XCTAssertEqual(windows(one, region: "change_code:\(fixture.changeUuids[5])").count, 4_000)
    }

    func testFileChangesPageThroughEveryRow() throws {
        let fixture = try makeFixture()
        let pages = try allPages("cde_search_file_changes", ["prompt_uuid": .string(fixture.promptUuid)])
        let changes = rows(pages, key: "changes")
        XCTAssertEqual(changes.count, 240)
        XCTAssertEqual(Set(changes.compactMap { $0["uuid"] as? String }).count, 240)
        XCTAssertEqual(total(pages[0], region: "changes"), 240)
    }

    func testPromptTextArrivesAsWindows() throws {
        let fixture = try makeFixture()
        let pages = try allPages("cde_load_prompt", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertEqual(windows(pages, region: "detail"), fixture.detail)
        XCTAssertEqual(total(pages[0], region: "goal"), 0)
        XCTAssertEqual((pages[0]["promptStub"] as? [String: Any])?["uuid"] as? String, fixture.promptUuid)
    }

    func testBriefingRefsPage() throws {
        let fixture = try makeFixture()
        let page = try call("rpir_load_exploration_brief", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertEqual((page["dopeRefs"] as? [[String: Any]])?.count, 40)
        XCTAssertEqual(total(page, region: "dope_refs"), 40)
        XCTAssertEqual((page["briefingStub"] as? [String: Any])?["dopeRefCount"] as? Int, 40)
    }

    func testRecordSearchPagesItsHits() throws {
        let fixture = try makeFixture()
        let pages = try allPages(
            "rpir_search_exploration",
            [
                "query": .string("lorem"), "session_uuid": .string(fixture.sessionUuid), "limit": .int(200),
                "page_bytes": .int(8_000),
            ]
        )
        let hits = rows(pages, key: "hits")
        XCTAssertGreaterThanOrEqual(hits.count, 40)
        XCTAssertEqual(total(pages[0], region: "hits"), hits.count)
    }

    func testRpirNextIsUntouched() throws {
        let fixture = try makeFixture()
        let page = try call("rpir_next", ["prompt_uuid": .string(fixture.promptUuid)])
        XCTAssertNotNil(page["phase"])
        XCTAssertNil(page["page"])
    }
}
