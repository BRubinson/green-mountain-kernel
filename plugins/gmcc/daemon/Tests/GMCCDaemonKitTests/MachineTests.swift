import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Drives the clarification and architecture state machines plus the
/// lifecycle-v2 prompt gates on a real migrated Store — every legal edge,
/// every illegal edge, the legacy bypass, and the no-synthetic-rows rule.
final class MachineTests: XCTestCase {
    private var store: Store!
    private var dbPath: String!
    private var promptUuid: String!
    private var sessionUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("machine-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        // Minimal context chain + one post-m0002 prompt.
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'repo_1', 'repo_1', '/tmp/machine-repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');
                """)
        }
        sessionUuid = "sess-1"
        promptUuid = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "machine_test", detail: "d")).uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func promptVersion() throws -> Int64 {
        try store.getPrompt(PromptGetRequest(promptUuid: promptUuid)).prompt.version
    }

    private func setStatus(_ status: PromptStatus) throws -> PromptRow {
        try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(), status: status))
    }

    func testFullLifecycleWithGatesAndMachines() throws {
        // draft → clarifying creates the summary (create-on-enter).
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        var summary = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        XCTAssertEqual(summary.status, "building")

        // Gate refuses architecting while the clarification is incomplete.
        XCTAssertThrowsError(try setStatus(.architecting))

        // Add a question (with options) and an internal note; seal, answer,
        // finalize — the m0025 split machine.
        let q1 = try store.clarifyQuestionAdd(ClarifyQuestionAddRequest(
            summaryUuid: summary.uuid, question: "What is the goal?",
            options: ["Ship it", "Hold"])).question
        XCTAssertEqual(q1.options.count, 2)
        _ = try store.clarifyNoteAdd(ClarifyNoteAddRequest(
            summaryUuid: summary.uuid, body: "Integration point resolved: the wire codec.",
            weight: 20))
        // Answer while building is refused.
        XCTAssertThrowsError(try store.clarifyAnswer(ClarifyAnswerRequest(
            questionUuid: q1.uuid, expectedVersion: q1.version, answerText: "early")))
        summary = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version)).summary
        XCTAssertEqual(summary.status, "answering")
        // Question-add stays legal while ANSWERING (the generative follow-up
        // passes); it is refused only once complete. Answer the follow-up so
        // the finalize gate below tests exactly one open question.
        let followUp = try store.clarifyQuestionAdd(ClarifyQuestionAddRequest(
            summaryUuid: summary.uuid, question: "follow-up?")).question
        _ = try store.clarifyAnswer(ClarifyAnswerRequest(
            questionUuid: followUp.uuid, expectedVersion: followUp.version,
            answerText: "answered"))
        // Finalize with an open question is refused.
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version)))
        // Answer by selection + typed elaboration (junction rows).
        let answered = try store.clarifyAnswer(ClarifyAnswerRequest(
            questionUuid: q1.uuid, expectedVersion: q1.version,
            answerText: "ship it", selectedOptionUuids: [q1.options[0].uuid])).question
        XCTAssertEqual(answered.selectedOptionUuids, [q1.options[0].uuid])
        // A foreign option uuid is refused.
        XCTAssertThrowsError(try store.clarifyAnswer(ClarifyAnswerRequest(
            questionUuid: q1.uuid, expectedVersion: answered.version,
            selectedOptionUuids: ["not-an-option"])))
        // Stale expected-version conflicts.
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version - 1)))
        let finalized = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: summary.version))
        XCTAssertEqual(finalized.summary.status, "complete")
        // THE RETIRED DOOR: finalize writes NOTHING to the prompt row —
        // backstory/goal/detail are human input only.
        XCTAssertEqual(
            try store.getPrompt(PromptGetRequest(promptUuid: promptUuid)).prompt.goal, "")

        // Reopen (complete → answering) then re-finalize.
        let reopened = try store.clarifyReopen(ClarifyReopenRequest(
            summaryUuid: summary.uuid, expectedVersion: finalized.summary.version)).summary
        XCTAssertEqual(reopened.status, "answering")
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: summary.uuid, expectedVersion: reopened.version))

        // clarifying → architecting now passes and creates the arch summary.
        XCTAssertEqual(try setStatus(.architecting).status, "architecting")
        var arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        XCTAssertFalse(arch.uuid.isEmpty)

        // Gate refuses implementing while the architecture is unapproved.
        XCTAssertThrowsError(try setStatus(.implementing))

        // Author the architecture: body, one persistence change + field, one general change.
        arch = try store.archSummarize(ArchSummarizeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version, body: "Concept.")).summary
        let persist = try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "Widget",
            filePath: "/tmp/machine-repo/Sources/Widget.swift", reasonBrief: "new model")).change
        XCTAssertEqual(persist.filePath, "Sources/Widget.swift") // normalized
        _ = try store.archFieldAdd(ArchFieldAddRequest(
            persistenceChangeUuid: persist.uuid, fieldName: "owner_uuid", dataType: "TEXT",
            changeReason: "link", changePurpose: "join", nullable: false,
            isForeignKey: true, fkTarget: "owner.uuid", isIndexed: true))
        // FK without target refused.
        XCTAssertThrowsError(try store.archFieldAdd(ArchFieldAddRequest(
            persistenceChangeUuid: persist.uuid, fieldName: "bad", dataType: "TEXT",
            changeReason: "r", changePurpose: "p", nullable: true, isForeignKey: true)))
        _ = try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/UI.swift",
            reasonBrief: "render", changeDepth: .pseudo, changeCode: "draw()"))
        // Absolute-outside-instance path refused.
        XCTAssertThrowsError(try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "/etc/passwd",
            reasonBrief: "nope", changeDepth: .pseudo, changeCode: "x")))

        // propose → (revise → propose) → approve; approved is terminal.
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        // Adds are sealed after propose.
        XCTAssertThrowsError(try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/Late.swift",
            reasonBrief: "late", changeDepth: .pseudo, changeCode: "x")))
        arch = try store.archRevise(ArchReviseRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        XCTAssertEqual(arch.status, "drafting")
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        arch = try store.archApprove(ArchApproveRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        XCTAssertEqual(arch.status, "approved")
        XCTAssertThrowsError(try store.archRevise(ArchReviseRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)))

        // architecting → implementing now passes; then the skip edge.
        XCTAssertEqual(try setStatus(.implementing).status, "implementing")
        XCTAssertEqual(try setStatus(.done).status, "done")
        XCTAssertThrowsError(try setStatus(.reviewing)) // done is terminal
    }

    func testIllegalPromptEdges() throws {
        XCTAssertThrowsError(try setStatus(.architecting)) // non-adjacent
        XCTAssertThrowsError(try setStatus(.done))         // jump to terminal
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        XCTAssertThrowsError(try setStatus(.draft))        // backward
    }

    /// m0005 removed the legacy tier: create-on-enter is now universal, so
    /// draft → clarifying always materialises a clarification summary and the
    /// clarifying → architecting gate always has a summary to check. The old
    /// backdate-the-prompt bypass has no remaining code path.
    func testCreateOnEnterIsUniversalWithNoLegacyBypass() throws {
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE prompt SET created_at = '2020-01-01T00:00:00Z' WHERE uuid = ?",
                arguments: [promptUuid!])
        }
        XCTAssertEqual(try setStatus(.clarifying).status, "clarifying")
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clarification_summary"), 1)
        }
        // An old created_at buys no gate bypass: the summary is still building.
        XCTAssertThrowsError(try setStatus(.architecting))
    }

    func testArchGetComparisonBuckets() throws {
        _ = try setStatus(.clarifying)
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        let sealed = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version)).summary
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: clarify.uuid, expectedVersion: sealed.version))
        _ = try setStatus(.architecting)
        let arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        _ = try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "M", filePath: "Sources/Model.swift",
            reasonBrief: "model first"))
        _ = try store.archGeneralAdd(ArchGeneralAddRequest(
            summaryUuid: arch.uuid, filePath: "Sources/View.swift",
            reasonBrief: "view", changeDepth: .draft, changeCode: "v"))

        // Record file changes: the persistence path, then an unplanned path.
        let project = ProjectContext(
            gitRepoName: "repo", code: "repo", name: "repo",
            ckfsRelativeStoragePath: "projects/repo", uuid: "proj-1")
        let instance = InstanceContext(
            code: "repo_1", name: "repo_1", absoluteFileSystemPath: "/tmp/machine-repo",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1", uuid: "inst-1")
        let session = SessionContext(
            code: "main", name: "main",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1/sessions/main", uuid: "sess-1")
        _ = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            promptUuid: promptUuid, relativePath: "Sources/Model.swift",
            changeKind: .edit, ranges: [ChangeRange(lineStart: 1, lineEnd: 5)]))
        _ = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            promptUuid: promptUuid, relativePath: "Sources/Surprise.swift",
            changeKind: .create, ranges: []))

        let got = try store.archGet(ArchGetRequest(promptUuid: promptUuid))
        // Planned + touched.
        XCTAssertEqual(got.persistenceChanges[0].implementation.fileChangeCount, 1)
        // Planned + untouched.
        XCTAssertEqual(got.generalChanges[0].implementation.fileChangeCount, 0)
        // Touched + unplanned.
        XCTAssertEqual(got.unplannedChanges.map(\.path), ["Sources/Surprise.swift"])
        // Persistence-first: general side untouched ⇒ audit vacuous.
        XCTAssertNil(got.orderingRespected)
    }

    func testExplorationMachine() throws {
        // Open works at draft (Phase 2 timing) and is idempotent per
        // (prompt, agent_type); prompt status never creates one.
        let opened = try store.exploreOpen(ExploreOpenRequest(promptUuid: promptUuid))
        XCTAssertTrue(opened.created)
        XCTAssertEqual(opened.summary.status, "exploring")
        XCTAssertEqual(opened.summary.agentType, "general")
        XCTAssertFalse(try store.exploreOpen(ExploreOpenRequest(promptUuid: promptUuid)).created)
        // A second agent type coexists on the same prompt.
        let synthesis = try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "synthesis"))
        XCTAssertTrue(synthesis.created)
        // Unknown agent types are refused (registry-governed vocabulary).
        XCTAssertThrowsError(try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "bogus")))
        let summaryUuid = opened.summary.uuid

        // Key files dedupe as upsert-ignore.
        let kf1 = try store.exploreKeyFileAdd(ExploreKeyFileAddRequest(
            summaryUuid: summaryUuid, filePath: "Sources/A.swift"))
        XCTAssertTrue(kf1.created)
        let kf2 = try store.exploreKeyFileAdd(ExploreKeyFileAddRequest(
            summaryUuid: summaryUuid, filePath: "Sources/A.swift"))
        XCTAssertFalse(kf2.created)
        XCTAssertEqual(kf1.keyFile.uuid, kf2.keyFile.uuid)

        // Two findings: one pre-rated, one unranked.
        let f1 = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .implementationPattern, title: "pattern",
            body: "body", agentName: "conservative", rating: 40)).finding
        let f2 = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .scopeCreepRisk, title: "risk",
            body: "body", agentName: "aggressive")).finding
        XCTAssertNil(f2.findingRating)

        // The synthesis complete is the prompt-level seal: it refuses while
        // anything across the prompt is unranked. An AGENT summary completes
        // freely — its overview is the agent's own report.
        XCTAssertThrowsError(try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: synthesis.summary.uuid,
            expectedVersion: synthesis.summary.version, overview: "seal")))

        // Batch atomicity: one bad pair (foreign uuid) rejects the whole batch.
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            promptUuid: promptUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 10),
                      FindingRating(findingUuid: "not-a-finding", rating: 10)])))
        XCTAssertNil(try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid))
            .findings.first(where: { $0.uuid == f2.uuid })?.findingRating)
        // Duplicate uuids reject too.
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            promptUuid: promptUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 10),
                      FindingRating(findingUuid: f2.uuid, rating: 20)])))

        // A good PROMPT-scoped batch lands; unrankedCount hits zero.
        let ranked = try store.exploreRank(ExploreRankRequest(
            promptUuid: promptUuid,
            ratings: [FindingRating(findingUuid: f2.uuid, rating: 150)]))
        XCTAssertEqual(ranked.unrankedCount, 0)

        // GET partitions at 100: f1 (40) full, f2 (150) stub; --full unhides.
        let got = try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(got.findings.map(\.uuid), [f1.uuid])
        XCTAssertEqual(got.findingStubs.map(\.uuid), [f2.uuid])
        XCTAssertEqual(
            try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid, full: true))
                .findings.count, 2)
        // Rating-range window shifts the partition.
        XCTAssertEqual(
            try store.exploreGet(ExploreGetRequest(
                promptUuid: promptUuid, ratingMin: 100, ratingMax: 200)).findings.map(\.uuid),
            [f2.uuid])

        // The agent summary completes with just its overview; the synthesis
        // complete (all ranked now) is the seal; rank refused after the seal;
        // reopening the synthesis re-arms and preserves everything.
        var summary = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: opened.summary.version,
            overview: "the agent narrative")).summary
        XCTAssertEqual(summary.status, "complete")
        var seal = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: synthesis.summary.uuid,
            expectedVersion: synthesis.summary.version,
            overview: "the synthesis")).summary
        XCTAssertEqual(seal.status, "complete")
        XCTAssertThrowsError(try store.exploreRank(ExploreRankRequest(
            promptUuid: promptUuid,
            ratings: [FindingRating(findingUuid: f1.uuid, rating: 5)])))
        seal = try store.exploreReopen(ExploreReopenRequest(
            summaryUuid: synthesis.summary.uuid, expectedVersion: seal.version)).summary
        XCTAssertEqual(seal.status, "exploring")
        XCTAssertEqual(seal.overview, "the synthesis")
        // GET returns every summary, synthesis first.
        let all = try store.exploreGet(ExploreGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(all.summaries.map(\.agentType), ["synthesis", "general"])
        // A post-reopen unranked finding re-blocks the SEAL (not the agent).
        summary = try store.exploreReopen(ExploreReopenRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version)).summary
        _ = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: summaryUuid, kind: .other, title: "new", body: "b",
            agentName: "primary"))
        XCTAssertThrowsError(try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: synthesis.summary.uuid, expectedVersion: seal.version,
            overview: "v2")))
    }

    func testReviewMachine() throws {
        let opened = try store.reviewOpen(ReviewOpenRequest(promptUuid: promptUuid))
        let summaryUuid = opened.summary.uuid
        XCTAssertEqual(opened.summary.status, "reviewing")

        // line_end without line_start refused; located finding lands.
        XCTAssertThrowsError(try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .correctnessBug, title: "t", body: "b",
            lineEnd: 5, agentName: "a")))
        let f1 = try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .correctnessBug, title: "bug",
            body: "b", filePath: "Sources/A.swift", lineStart: 3, lineEnd: 9,
            agentName: "conservative", rating: 10)).finding
        let f2 = try store.reviewFindingAdd(ReviewFindingAddRequest(
            summaryUuid: summaryUuid, kind: .simplification, title: "nit",
            body: "b", agentName: "pragmatic", rating: 400)).finding

        // Complete requires the verdict and carries overview + verdict.
        var summary = try store.reviewGet(ReviewGetRequest(promptUuid: promptUuid)).summary
        summary = try store.reviewComplete(ReviewCompleteRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version,
            overview: "review narrative", verdict: .approvedWithNits)).summary
        XCTAssertEqual(summary.verdict, "approved_with_nits")

        // Resolve works AFTER complete (the fix loop), stubs keep status,
        // lateral corrections allowed, never back to open.
        let resolved = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: f1.version, status: .fixed)).finding
        XCTAssertEqual(resolved.status, "fixed")
        let corrected = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: resolved.version, status: .accepted)).finding
        XCTAssertEqual(corrected.status, "accepted")
        XCTAssertThrowsError(try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f1.uuid, expectedVersion: corrected.version, status: .open)))
        let got = try store.reviewGet(ReviewGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(got.findingStubs.first(where: { $0.uuid == f2.uuid })?.status, "open")

        // Resolve survives a reopen mid-fix-loop (the ungated design).
        summary = try store.reviewReopen(ReviewReopenRequest(
            summaryUuid: summaryUuid, expectedVersion: summary.version)).summary
        XCTAssertEqual(summary.status, "reviewing")
        _ = try store.reviewResolve(ReviewResolveRequest(
            findingUuid: f2.uuid, expectedVersion: f2.version, status: .wontFix))

        // SUMMARY_ABSENT on a fresh prompt: no review summary, and prompt
        // transitions never created one behind our back (skip-to-done
        // legality).
        let fresh = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "fresh", detail: "d")).uuid
        do {
            _ = try store.reviewGet(ReviewGetRequest(promptUuid: fresh))
            XCTFail("expected summaryAbsent")
        } catch let StoreError.summaryAbsent(entity, _) {
            XCTAssertEqual(entity, "review")
        }
    }
}
