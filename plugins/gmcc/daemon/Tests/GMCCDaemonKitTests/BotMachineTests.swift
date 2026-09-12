import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Functional coverage for the m0025 bot workflow machine — the release's
/// headline feature. Drives promptStart/promptResume/botNext/setBaseline,
/// the phase derivation across gates, claim stealing, end-of-life, the care
/// package finalize gate, and the architecture option/decide guards on a
/// real migrated Store.
final class BotMachineTests: XCTestCase {
    private var store: Store!
    private var dbPath: String!
    private var promptUuid: String!
    private var sessionUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("botmachine-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'repo_1', 'repo_1', '/tmp/bm-repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');
                """)
        }
        sessionUuid = "sess-1"
        promptUuid = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "machine", detail: "d")).uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func next(_ prompt: String? = nil) throws -> BotNextResponse {
        try store.botNext(BotNextRequest(promptUuid: prompt ?? promptUuid))
    }

    private func promptVersion(_ uuid: String) throws -> Int64 {
        try store.getPrompt(PromptGetRequest(promptUuid: uuid)).prompt.version
    }

    // MARK: - Start / resume / claims

    func testStartCreatesAndSecondStartReleasesTheClientClaim() throws {
        let started = try store.promptStart(PromptStartRequest(
            promptUuid: promptUuid, variant: .bot, clientKey: "claude:1:1"))
        XCTAssertTrue(started.created)
        XCTAssertEqual(started.workflow.variant, "bot")
        XCTAssertEqual(started.workflow.status, "active")

        // Start refuses a duplicate on the same prompt…
        XCTAssertThrowsError(try store.promptStart(PromptStartRequest(
            promptUuid: promptUuid, variant: .bot, clientKey: "claude:1:1")))

        // …and the SAME instance starting a SECOND prompt releases its old
        // hold instead of dying on the partial UNIQUE(client_key).
        let second = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "second", detail: "d")).uuid
        let startedB = try store.promptStart(PromptStartRequest(
            promptUuid: second, variant: .rpi, clientKey: "claude:1:1"))
        XCTAssertEqual(startedB.workflow.clientKey, "claude:1:1")
        XCTAssertNil(try store.botGet(BotGetRequest(promptUuid: promptUuid)).workflow.clientKey)
    }

    func testStartRefusesNonDraftAndResumeAdopts() throws {
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .clarifying))
        XCTAssertThrowsError(try store.promptStart(PromptStartRequest(
            promptUuid: promptUuid, variant: .bot)))
        // Resume without a variant on a machine-less prompt asks for one.
        XCTAssertThrowsError(try store.promptResume(PromptResumeRequest(promptUuid: promptUuid)))
        let adopted = try store.promptResume(PromptResumeRequest(
            promptUuid: promptUuid, variant: .bot, clientKey: "claude:2:2"))
        XCTAssertTrue(adopted.created)
        // A second resume returns the same row and steals the claim.
        let stolen = try store.promptResume(PromptResumeRequest(
            promptUuid: promptUuid, variant: nil, clientKey: "claude:3:3"))
        XCTAssertFalse(stolen.created)
        XCTAssertEqual(stolen.workflow.uuid, adopted.workflow.uuid)
        XCTAssertEqual(stolen.workflow.clientKey, "claude:3:3")
    }

    // MARK: - Phase derivation (bot variant walked end to end)

    func testBotVariantPhaseWalk() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptUuid, variant: .bot))

        // No briefing yet → briefing phase, explore blocked on it.
        var response = try next()
        XCTAssertEqual(response.phase, "briefing")
        XCTAssertFalse(response.gateBlockers.isEmpty)

        // Briefing ready → explore.
        let briefing = try store.briefingOpen(BriefingOpenRequest(
            promptUuid: promptUuid, briefingForStep: "initial"))
        _ = try store.briefingComplete(BriefingCompleteRequest(
            briefingUuid: briefing.briefing.uuid,
            expectedVersion: briefing.briefing.version,
            dopeRefs: ["agentics.bot_workflow"]))
        response = try next()
        XCTAssertEqual(response.phase, "explore")
        XCTAssertEqual(response.uuids.briefingUuid, briefing.briefing.uuid)

        // General + synthesis summaries complete → clarify_open.
        let general = try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "general")).summary
        let finding = try store.exploreFindingAdd(ExploreFindingAddRequest(
            summaryUuid: general.uuid, kind: .other, title: "t", body: "b",
            agentName: "general", rating: 40)).finding
        XCTAssertNotNil(finding.findingRating)
        _ = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: general.uuid, expectedVersion: general.version, overview: "general view"))
        let synthesis = try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "synthesis")).summary
        _ = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: synthesis.uuid, expectedVersion: synthesis.version, overview: "the seal"))
        response = try next()
        XCTAssertEqual(response.phase, "clarify_open")

        // Sealed clarification suite → clarify_user.
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .clarifying))
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        let q = try store.clarifyQuestionAdd(ClarifyQuestionAddRequest(
            summaryUuid: clarify.uuid, question: "sure?", options: ["yes", "no"])).question
        _ = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version))
        response = try next()
        XCTAssertEqual(response.phase, "clarify_user")

        // Follow-up question-add stays legal while answering (the promised
        // generative passes).
        _ = try store.clarifyQuestionAdd(ClarifyQuestionAddRequest(
            summaryUuid: clarify.uuid, question: "follow-up?"))

        // Answer everything, finalize (bot variant needs no care package),
        // move to architecting → architecture phase.
        for question in try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).questions {
            _ = try store.clarifyAnswer(ClarifyAnswerRequest(
                questionUuid: question.uuid, expectedVersion: question.version,
                answerText: question.uuid == q.uuid ? nil : "typed",
                selectedOptionUuids: question.uuid == q.uuid ? [q.options[0].uuid] : nil))
        }
        let sealed = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version))
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .architecting))
        response = try next()
        XCTAssertEqual(response.phase, "architecture")

        // Architecture body → plan_gate; approve + implementing → implement.
        var arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        arch = try store.archSummarize(ArchSummarizeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version, body: "concept")).summary
        response = try next()
        XCTAssertEqual(response.phase, "plan_gate")
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        arch = try store.archApprove(ArchApproveRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .implementing))
        response = try next()
        XCTAssertEqual(response.phase, "implement")

        // Review opened → review; complete → review_fix; done closes.
        _ = try store.reviewOpen(ReviewOpenRequest(promptUuid: promptUuid))
        response = try next()
        XCTAssertEqual(response.phase, "review")
        let review = try store.reviewGet(ReviewGetRequest(promptUuid: promptUuid)).summary
        _ = try store.reviewComplete(ReviewCompleteRequest(
            summaryUuid: review.uuid, expectedVersion: review.version,
            overview: "clean", verdict: .approved))
        response = try next()
        XCTAssertEqual(response.phase, "review_fix")

        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .done))
        // done closed the workflow; reads fall back to the closed row…
        let closed = try store.botGet(BotGetRequest(promptUuid: promptUuid)).workflow
        XCTAssertEqual(closed.status, "done")
        // …next derives the done phase on it…
        XCTAssertEqual(try next().phase, "done")
        // …and resume refuses to re-open finished work.
        XCTAssertThrowsError(try store.promptResume(PromptResumeRequest(
            promptUuid: promptUuid, variant: .bot)))
    }

    // MARK: - Legacy adoption (back-walk derivation)

    func testAdoptedLegacyPromptDerivesFromStrongestEvidence() throws {
        // A migrated pre-machine prompt: synthesis-only exploration row,
        // approved architecture, status implementing — the forward walk
        // stranded these at explore.
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .clarifying))
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version))
        let sealed = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version))
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .architecting))
        var arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        arch = try store.archSummarize(ArchSummarizeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version, body: "legacy plan")).summary
        arch = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)).summary
        _ = try store.archApprove(ArchApproveRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version))
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .implementing))
        // Only a synthesis summary exists (the migration's shape).
        let synthesis = try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "synthesis")).summary
        _ = try store.exploreComplete(ExploreCompleteRequest(
            summaryUuid: synthesis.uuid, expectedVersion: synthesis.version, overview: "legacy"))

        _ = try store.promptResume(PromptResumeRequest(promptUuid: promptUuid, variant: .team))
        XCTAssertEqual(try next().phase, "implement",
                       "adopted legacy prompt must derive from its strongest evidence, not strand at explore")
    }

    // MARK: - Care package gate

    func testRpiFinalizeRequiresReadyCarePackage() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptUuid, variant: .rpi))
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .clarifying))
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version))
        var sealed = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary

        // No package at all → finalize refused for a care-package variant.
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version)))

        // Building package → still refused; ready → passes.
        let package = try store.carePackageOpen(CarePackageOpenRequest(
            summaryUuid: sealed.uuid)).package
        _ = try store.carePackageRefAdd(CarePackageRefAddRequest(
            packageUuid: package.uuid, kind: .dope, dopeCode: "agentics.care_package"))
        XCTAssertThrowsError(try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version)))
        // ref-add inserts child rows only — the package row's version is
        // untouched, so complete still expects the open-time version.
        _ = try store.carePackageComplete(CarePackageCompleteRequest(
            packageUuid: package.uuid, expectedVersion: package.version,
            clarifiedIntent: "the clarified intent"))
        sealed = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        let finalized = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version))
        XCTAssertEqual(finalized.summary.status, "complete")
        // The intent lives ONLY on the package — the prompt row is untouched.
        XCTAssertEqual(
            try store.getPrompt(PromptGetRequest(promptUuid: promptUuid)).prompt.goal, "")
    }

    // MARK: - Architecture options

    func testOptionDecideGuardsExpansionAndPropose() throws {
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .clarifying))
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifySeal(ClarifySealRequest(
            summaryUuid: clarify.uuid, expectedVersion: clarify.version))
        let sealed = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifyFinalize(ClarifyFinalizeRequest(
            summaryUuid: sealed.uuid, expectedVersion: sealed.version))
        _ = try store.setPromptStatus(PromptSetStatusRequest(
            promptUuid: promptUuid, expectedVersion: try promptVersion(promptUuid), status: .architecting))
        var arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary

        // Two options; a duplicate persona is refused.
        let a = try store.archOptionAdd(ArchOptionAddRequest(
            summaryUuid: arch.uuid, agentName: "aggressive", body: "big")).option
        _ = try store.archOptionAdd(ArchOptionAddRequest(
            summaryUuid: arch.uuid, agentName: "conservative", body: "small"))
        XCTAssertThrowsError(try store.archOptionAdd(ArchOptionAddRequest(
            summaryUuid: arch.uuid, agentName: "aggressive", body: "again")))

        // Undecided options block BOTH the expansion and the seal.
        XCTAssertThrowsError(try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "X", filePath: "Sources/X.swift",
            reasonBrief: "r")))
        arch = try store.archSummarize(ArchSummarizeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version, body: "plan")).summary
        XCTAssertThrowsError(try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version)))

        // Decide: winner selected, sibling rejected, rationale recorded.
        let decided = try store.archDecide(ArchDecideRequest(
            optionUuid: a.uuid, expectedVersion: a.version, rationale: "aggressive wins"))
        XCTAssertEqual(decided.summary.decisionRationale, "aggressive wins")
        XCTAssertEqual(
            Set(decided.options.map(\.status)), ["selected", "rejected"])

        // Expansion + propose now pass.
        _ = try store.archPersistAdd(ArchPersistAddRequest(
            summaryUuid: arch.uuid, className: "X", filePath: "Sources/X.swift",
            reasonBrief: "r", changeKind: "add", dopeRef: "agentics.bot_workflow"))
        arch = try store.archGet(ArchGetRequest(promptUuid: promptUuid)).summary
        _ = try store.archPropose(ArchProposeRequest(
            summaryUuid: arch.uuid, expectedVersion: arch.version))
    }

    // MARK: - workflow_phase stamping

    func testLivePhaseStampingOnAttributedFileChange() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptUuid, variant: .bot))

        // A file change attributed to the prompt is stamped with the LIVE
        // derived phase (briefing — nothing else exists yet), not
        // last_served_phase (never set here).
        let project = ProjectContext(
            gitRepoName: "repo", code: "repo", name: "repo",
            ckfsRelativeStoragePath: "projects/repo", uuid: "proj-1")
        let instance = InstanceContext(
            code: "repo_1", name: "repo_1", absoluteFileSystemPath: "/tmp/bm-repo",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1", uuid: "inst-1")
        let session = SessionContext(
            code: "main", name: "main",
            ckfsRelativeStoragePath: "projects/repo/instances/repo_1/sessions/main", uuid: "sess-1")
        let change = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            promptUuid: promptUuid, relativePath: "Sources/A.swift",
            changeKind: .edit, ranges: [], origin: "manual"))
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try String.fetchOne(
                    db, sql: "SELECT workflow_phase FROM file_change WHERE uuid = ?",
                    arguments: [change.fileChangeUuid]),
                "briefing")
            XCTAssertEqual(
                try String.fetchOne(
                    db, sql: "SELECT origin FROM file_change WHERE uuid = ?",
                    arguments: [change.fileChangeUuid]),
                "manual")
        }
    }

    // MARK: - MCP seal leak (repository-level guard is prose; tool refuses)

    func testSynthesisSummaryStillPrimarysViaDirectVerb() throws {
        // The MCP tool refuses agent_type=synthesis client-side; the direct
        // verb stays legal for the PRIMARY (bot/rpi flows drive it via gm).
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptUuid, variant: .bot))
        let synthesis = try store.exploreOpen(ExploreOpenRequest(
            promptUuid: promptUuid, agentType: "synthesis"))
        XCTAssertTrue(synthesis.created)
    }
}
