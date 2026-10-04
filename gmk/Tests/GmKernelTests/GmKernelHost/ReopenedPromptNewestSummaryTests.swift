import Foundation
import GRDB
import XCTest

/// The m0028 re-open edge (done → draft), driven entirely over the wire.
///
/// The summary resolvers order `created_at DESC, id DESC` so a prompt holding
/// several summary rows serves its newest set. Every summary OPEN verb is
/// create-or-return keyed on the prompt, so no wire flow mints a second set today
/// and the read-only-SQL rule forbids inserting one by hand. These cases assert
/// what IS reachable: the ordered resolvers run on every GET/NEXT, and the
/// re-opened prompt resolves one summary set across CLARIFY_GET / ARCH_GET / NEXT.
final class ReopenedPromptNewestSummaryTests: KernelBackedTestCase {

    /// Creates a session for a test, uniquely named.
    ///
    /// Mints a project and session to hang a prompt off so test cases cannot
    /// collide no matter what order they run in.
    ///
    /// - Parameter label: A label to make the session unique.
    /// - Returns: The session identifier.
    /// - Throws: Errors from creating the project/session or network calls.
    private func makeSession(_ label: String) throws -> String {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let code = "t_\(label)_\(id)"
        let repo = env.root.appendingPathComponent("repos/\(code)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let response = try env.send(
            .contextEnsure,
            ContextEnsureRequest(
                project: ProjectContext(
                    gitRepoName: code,
                    code: code,
                    name: code,
                    gmfsRelativeStoragePath: "projects/\(code)"
                ),
                instance: InstanceContext(
                    code: "\(code)_1",
                    name: code,
                    absoluteFileSystemPath: repo.path,
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1"
                ),
                session: SessionContext(
                    code: "main",
                    name: "main",
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main",
                    backstory: "",
                    goal: ""
                )
            ),
            ContextEnsureResponse.self
        )
        return response.sessionUuid
    }

    /// The prompt's current version.
    ///
    /// Re-read before every status move; BRIEFING_OPEN bumps it out from
    /// under a cached row.
    ///
    /// - Parameter promptUuid: The prompt identifier.
    /// - Returns: The current version of the prompt.
    /// - Throws: Errors from network calls.
    private func promptVersion(_ promptUuid: String) throws -> Int64 {
        try env.send(
            .promptGet,
            PromptGetRequest(promptUuid: promptUuid),
            PromptGetResponse.self
        )
        .prompt.version
    }

    /// Sets the prompt's status after reading its current version.
    ///
    /// - Parameters:
    ///   - promptUuid: The prompt identifier.
    ///   - status: The new status.
    /// - Throws: Errors from reading the version or setting status.
    private func setStatus(_ promptUuid: String, _ status: PromptStatus) throws {
        _ = try env.send(
            .promptSetStatus,
            PromptSetStatusRequest(
                promptUuid: promptUuid,
                expectedVersion: try promptVersion(promptUuid),
                status: status
            ),
            PromptRow.self
        )
    }

    /// Returns the count of summary rows for a prompt in a table.
    ///
    /// - Parameters:
    ///   - table: The table name to query.
    ///   - promptUuid: The prompt identifier.
    /// - Returns: The count of matching rows.
    /// - Throws: Errors from database access.
    private func summaryCount(table: String, promptUuid: String) throws -> Int {
        let db = try env.readOnlyDatabase()
        return try db.read {
            try Int.fetchOne(
                $0,
                sql: "SELECT COUNT(*) FROM \(table) WHERE prompt_uuid = ?",
                arguments: [promptUuid]
            ) ?? 0
        }
    }

    // MARK: - Cases

    /// The full reopen loop: create → work → done → draft → work again, with
    /// every read verb asserting it resolves the same (newest) summary set.
    func testReopenedPromptResolvesItsNewestSummarySet() throws {
        let sessionUuid = try makeSession("reopen")
        let prompt = try env.send(
            .promptCreate,
            PromptCreateRequest(sessionUuid: sessionUuid, name: "reopen fixture"),
            PromptRow.self
        )
        XCTAssertEqual(prompt.status, "draft")

        // Enter the machine, then open the first run's summaries.
        _ = try env.send(
            .promptStart,
            PromptStartRequest(promptUuid: prompt.uuid, variant: .bot),
            BotWorkflowResponse.self
        )
        let briefing1 = try env.send(
            .briefingOpen,
            BriefingOpenRequest(briefingForStep: "initial", promptUuid: prompt.uuid),
            BriefingRowResponse.self
        )
        XCTAssertTrue(briefing1.created)
        let clarify1 = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: prompt.uuid),
            ClarifySummaryResponse.self
        )
        XCTAssertTrue(clarify1.created)
        let arch1 = try env.send(
            .archOpen,
            ArchOpenRequest(promptUuid: prompt.uuid),
            ArchSummaryResponse.self
        )
        XCTAssertTrue(arch1.created)

        // BRIEFING_OPEN stamped draft → initiated; finish and re-open.
        try setStatus(prompt.uuid, .done)
        try setStatus(prompt.uuid, .draft)

        // The second pass over the same prompt. OPEN is create-or-return
        // keyed on the prompt, so this documents today's contract: the
        // re-opened prompt CONTINUES its summary set rather than minting a
        // second one — there is no wire path to a second row yet (see the
        // class note), which is exactly why `created` must read false here.
        let briefing2 = try env.send(
            .briefingOpen,
            BriefingOpenRequest(briefingForStep: "initial", promptUuid: prompt.uuid),
            BriefingRowResponse.self
        )
        XCTAssertFalse(briefing2.created, "BRIEFING_OPEN resets, never duplicates")
        XCTAssertEqual(briefing2.briefing.uuid, briefing1.briefing.uuid)
        let clarify2 = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: prompt.uuid),
            ClarifySummaryResponse.self
        )
        XCTAssertFalse(clarify2.created)
        let arch2 = try env.send(
            .archOpen,
            ArchOpenRequest(promptUuid: prompt.uuid),
            ArchSummaryResponse.self
        )
        XCTAssertFalse(arch2.created)

        // Single-row precondition: with one row per table, "newest" and
        // "only" coincide — the assertions below are meaningful because the
        // counts here pin what the wire was able to create.
        XCTAssertEqual(try summaryCount(table: "clarification_summary", promptUuid: prompt.uuid), 1)
        XCTAssertEqual(try summaryCount(table: "architecture_summary", promptUuid: prompt.uuid), 1)
        XCTAssertEqual(try summaryCount(table: "agent_briefing", promptUuid: prompt.uuid), 1)

        // The prompt-keyed resolvers (now ORDER BY created_at DESC, id DESC)
        // must serve the newest summary — a malformed ORDER BY fails these
        // reads loudly rather than silently serving the wrong row.
        let clarifyGet = try env.send(
            .clarifyGet,
            ClarifyGetRequest(promptUuid: prompt.uuid),
            ClarifyGetResponse.self
        )
        XCTAssertEqual(clarifyGet.summary.uuid, clarify2.summary.uuid)
        let archGet = try env.send(
            .archGet,
            ArchGetRequest(promptUuid: prompt.uuid),
            ArchGetResponse.self
        )
        XCTAssertEqual(archGet.summary.uuid, arch2.summary.uuid)

        // BOT_NEXT derives its uuid bundle through phaseUuids' ordered SQL —
        // the bundle must name the same set the GET verbs served.
        let next = try env.send(
            .botNext,
            BotNextRequest(promptUuid: prompt.uuid),
            BotNextResponse.self
        )
        XCTAssertEqual(next.uuids.briefingUuid, briefing2.briefing.uuid)
        XCTAssertEqual(next.uuids.clarificationSummaryUuid, clarify2.summary.uuid)
        XCTAssertEqual(next.uuids.architectureSummaryUuid, arch2.summary.uuid)
    }

    /// A prompt that was never re-opened resolves identically through the
    /// ordered resolvers — the DESC ordering is a no-op on a single row.
    func testSingleRunPromptIsUnaffectedByOrderedResolution() throws {
        let sessionUuid = try makeSession("single")
        let prompt = try env.send(
            .promptCreate,
            PromptCreateRequest(sessionUuid: sessionUuid, name: "single-run fixture"),
            PromptRow.self
        )

        let clarify = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: prompt.uuid),
            ClarifySummaryResponse.self
        )
        let arch = try env.send(
            .archOpen,
            ArchOpenRequest(promptUuid: prompt.uuid),
            ArchSummaryResponse.self
        )

        XCTAssertEqual(
            try env.send(
                .clarifyGet,
                ClarifyGetRequest(promptUuid: prompt.uuid),
                ClarifyGetResponse.self
            )
            .summary.uuid,
            clarify.summary.uuid
        )
        XCTAssertEqual(
            try env.send(
                .archGet,
                ArchGetRequest(promptUuid: prompt.uuid),
                ArchGetResponse.self
            )
            .summary.uuid,
            arch.summary.uuid
        )
    }
}
