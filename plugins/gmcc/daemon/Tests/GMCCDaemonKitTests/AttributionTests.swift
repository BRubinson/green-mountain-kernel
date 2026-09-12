import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0026's whole contract, proved entirely without a shell: the
/// claude_session_binding pin, the three-outcome attribution ladder, the
/// loud/silent split on an unbound write, (tool call, file) idempotency, and
/// the two-writer agent registry that makes "registration first" a guarantee
/// rather than a precondition.
///
/// Everything here is the DAEMON half. The hook that produces these payloads
/// has no say in any of it — that is the point: a payload cannot talk its way
/// past the binding, cannot pick its own prompt, and cannot record twice.
final class AttributionTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var sessionUuid: String!
    private var promptA: String!
    private var promptB: String!

    private let conversation = "claude-conv-1"

    private let project = ProjectContext(
        gitRepoName: "repo", code: "repo", name: "repo",
        ckfsRelativeStoragePath: "projects/repo")
    private let instance = InstanceContext(
        code: "repo_1", name: "repo_1", absoluteFileSystemPath: "/tmp/attr-repo",
        ckfsRelativeStoragePath: "projects/repo/instances/repo_1")
    private let session = SessionContext(
        code: "main", name: "main", ckfsRelativeStoragePath: "x")

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0026-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        // The binding is made the way SessionStart makes it: as a passenger on
        // the ensure call that creates the session it points at.
        sessionUuid = try store.ensureContext(ContextEnsureRequest(
            project: project, instance: instance, session: session,
            claudeSessionId: conversation)).sessionUuid
        promptA = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "alpha", detail: "d")).uuid
        promptB = try store.createPrompt(PromptCreateRequest(
            sessionUuid: sessionUuid, name: "beta", detail: "d")).uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Helpers

    /// A payload-borne write: it names the conversation, so it must resolve
    /// through the binding.
    @discardableResult
    private func hookWrite(
        path: String = "Sources/File.swift",
        claudeSessionId: String? = nil,
        agentId: String? = nil,
        agentType: String? = nil,
        toolUseId: String? = nil,
        ranges: [ChangeRange] = [],
        project: ProjectContext? = nil,
        instance: InstanceContext? = nil
    ) throws -> FileChangeAddResponse {
        try store.addFileChange(FileChangeAdd(
            project: project ?? self.project,
            instance: instance ?? self.instance,
            session: session,
            relativePath: path,
            changeKind: .edit,
            ranges: ranges,
            autoAttribute: true,
            agentId: agentId,
            claudeSessionId: claudeSessionId ?? conversation,
            claudeTurnId: "turn-9",
            toolUseId: toolUseId,
            toolName: "Edit",
            agentType: agentType,
            permissionMode: "acceptEdits",
            durationMs: 42,
            transcriptPath: "/tmp/transcript.jsonl"))
    }

    private func promptOf(_ fileChangeUuid: String) throws -> String? {
        try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT prompt_uuid FROM file_change WHERE uuid = ?",
                arguments: [fileChangeUuid])
        }
    }

    private func eventCount(_ kind: DaemonEventKind) throws -> Int {
        try store.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM daemon_event WHERE kind = ?",
                arguments: [kind.rawValue]) ?? 0
        }
    }

    private func setStatus(_ promptUuid: String, _ status: PromptStatus) throws {
        // Straight SQL: the ladder reads the column, and walking the real
        // status gates would drag every summary machine into an attribution
        // test.
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE prompt SET status = ? WHERE uuid = ?",
                arguments: [status.rawValue, promptUuid])
        }
    }

    private func registration(agentId: String) throws -> AgentRegistrationRow? {
        try store.dbQueue.read { db in
            try AgentRegistrationRecord.fetchOne(
                db, where: "agent_id = ?", arguments: [agentId])?.wireRow()
        }
    }

    // MARK: - The binding

    /// Pin-once is the UNIQUE index, not a branch: the conversation stays
    /// bound to the FIRST session it ensured, so a mid-session checkout cannot
    /// silently re-point it.
    func testTheBindingPinsOnceAndSurvivesASecondEnsure() throws {
        let otherBranch = SessionContext(
            code: "feature", name: "feature", ckfsRelativeStoragePath: "y")
        let second = try store.ensureContext(ContextEnsureRequest(
            project: project, instance: instance, session: otherBranch,
            claudeSessionId: conversation))
        XCTAssertNotEqual(second.sessionUuid, sessionUuid, "the new branch got its own session")

        let bound = try store.dbQueue.read { db in
            try ClaudeSessionBindingRepository(db: db, core: self.store.core)
                .resolveSession(claudeSessionId: self.conversation)
        }
        XCTAssertEqual(bound, sessionUuid)
        let rows = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM claude_session_binding") ?? 0
        }
        XCTAssertEqual(rows, 1)
    }

    // MARK: - The ladder

    /// Rung 1: the session's single active workflow names the prompt — and
    /// the daemon stamps the phase it derives, never one the caller claims.
    func testLadderTakesTheSessionsSingleActiveWorkflow() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptA, variant: .bot))
        let change = try hookWrite()
        XCTAssertEqual(try promptOf(change.fileChangeUuid), promptA)

        let phase = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT workflow_phase FROM file_change WHERE uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        XCTAssertNotNil(phase)
    }

    /// Rung 2: no workflow at all, but exactly one prompt is implementing.
    func testLadderFallsBackToTheSingleImplementingPrompt() throws {
        try setStatus(promptB, .implementing)
        let change = try hookWrite()
        XCTAssertEqual(try promptOf(change.fileChangeUuid), promptB)
    }

    /// Rung 3: NULL, recorded and session-scoped. Both rungs demand
    /// uniqueness, so two of anything is an answer of "not knowable", never a
    /// coin flip between two prompts — and the row is still WRITTEN, because
    /// an unattributable change is not a lost one.
    func testLadderRefusesToGuessBetweenTwoPrompts() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptA, variant: .bot))
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptB, variant: .bot))
        let ambiguousWorkflows = try hookWrite()
        XCTAssertNil(try promptOf(ambiguousWorkflows.fileChangeUuid))

        try setStatus(promptA, .implementing)
        try setStatus(promptB, .implementing)
        let ambiguousStatuses = try hookWrite(path: "Sources/Other.swift")
        XCTAssertNil(try promptOf(ambiguousStatuses.fileChangeUuid))

        let recorded = try store.listFileChanges(
            FileChangeListRequest(sessionUuid: sessionUuid)).changes
        XCTAssertEqual(recorded.count, 2, "unattributed is still recorded")
    }

    /// A caller with no conversation to name (the CLI, the pen) never touches
    /// the binding and resolves the same ladder against the session its cwd
    /// landed in.
    func testANonPayloadWriteResolvesTheLadderFromItsOwnSession() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptA, variant: .bot))
        let change = try store.addFileChange(FileChangeAdd(
            project: project, instance: instance, session: session,
            relativePath: "Sources/Manual.swift", changeKind: .edit, ranges: [],
            autoAttribute: true, origin: FileChangeOrigin.manual))
        XCTAssertEqual(try promptOf(change.fileChangeUuid), promptA)
    }

    // MARK: - The unbound gate

    /// A repo the daemon KNOWS, producing a payload it cannot resolve, is dead
    /// capture — refused AND marked. Silence is what hid this in the first
    /// place, so the event is the deliverable here, not the throw.
    func testUnboundWriteInAKnownRepoIsRefusedLoudly() throws {
        XCTAssertThrowsError(try hookWrite(claudeSessionId: "conv-never-pinned")) { error in
            guard case StoreError.hookUnbound(let id, let booted)? = error as? StoreError else {
                return XCTFail("expected hookUnbound, got \(error)")
            }
            XCTAssertEqual(id, "conv-never-pinned")
            XCTAssertTrue(booted)
        }
        XCTAssertEqual(try eventCount(.hookUnbound), 1)
        let written = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_change") ?? 0
        }
        XCTAssertEqual(written, 0, "the refusal wrote nothing at all")
    }

    /// A PostToolUse hook fires in every repo on the machine. One the daemon
    /// has never seen is refused with no event and no rows — the ordinary
    /// case, and the no-op contract that replaces the env gate.
    func testUnboundWriteInAnUnknownRepoIsRefusedSilently() throws {
        let stranger = ProjectContext(
            gitRepoName: "elsewhere", code: "elsewhere", name: "elsewhere",
            ckfsRelativeStoragePath: "projects/elsewhere")
        let strangerInstance = InstanceContext(
            code: "elsewhere_1", name: "elsewhere_1", absoluteFileSystemPath: "/tmp/elsewhere",
            ckfsRelativeStoragePath: "projects/elsewhere/instances/elsewhere_1")
        XCTAssertThrowsError(
            try hookWrite(
                claudeSessionId: "conv-somewhere-else",
                project: stranger, instance: strangerInstance)
        ) { error in
            guard case StoreError.hookUnbound(_, let booted)? = error as? StoreError else {
                return XCTFail("expected hookUnbound, got \(error)")
            }
            XCTAssertFalse(booted)
        }
        XCTAssertEqual(try eventCount(.hookUnbound), 0)
        let projects = try store.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM project WHERE code = 'elsewhere'") ?? 0
        }
        XCTAssertEqual(projects, 0, "a refused write never runs the ensure chain")
    }

    // MARK: - Idempotency

    /// A replayed tool call is an already-recorded SUCCESS: the same uuids
    /// come back, and the db is left alone. No second row, no second event and
    /// no session touch — a replay must not look like a second edit to a
    /// subscriber.
    func testReplayedToolCallReturnsTheSameRowWithoutASecondEvent() throws {
        let first = try hookWrite(toolUseId: "toolu_1")
        XCTAssertNil(first.deduplicated)

        let fileVersionBefore = try store.dbQueue.read { db in
            try Int64.fetchOne(
                db, sql: "SELECT version FROM session_file WHERE uuid = ?",
                arguments: [first.sessionFileUuid])
        }
        let sessionTouchBefore = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT updated_at FROM session WHERE uuid = ?",
                arguments: [self.sessionUuid])
        }

        let replay = try hookWrite(toolUseId: "toolu_1")
        XCTAssertEqual(replay.deduplicated, true)
        XCTAssertEqual(replay.fileChangeUuid, first.fileChangeUuid)
        XCTAssertEqual(replay.sessionFileUuid, first.sessionFileUuid)
        XCTAssertEqual(try eventCount(.fileChange), 1)

        try store.dbQueue.read { db in
            XCTAssertEqual(
                try Int64.fetchOne(
                    db, sql: "SELECT version FROM session_file WHERE uuid = ?",
                    arguments: [first.sessionFileUuid]),
                fileVersionBefore,
                "the replay bumped session_file.version")
            XCTAssertEqual(
                try String.fetchOne(
                    db, sql: "SELECT updated_at FROM session WHERE uuid = ?",
                    arguments: [self.sessionUuid]),
                sessionTouchBefore,
                "the replay touched the session")
        }
    }

    /// The idempotency unit is (tool call, FILE), not the tool call: one
    /// command legitimately writes several files under one tool_use_id, and a
    /// bare key would make that capture impossible.
    func testTheSameToolCallRecordsEachFileOnce() throws {
        let a = try hookWrite(path: "Sources/A.swift", toolUseId: "toolu_2")
        let b = try hookWrite(path: "Sources/B.swift", toolUseId: "toolu_2")
        XCTAssertNotEqual(a.fileChangeUuid, b.fileChangeUuid)
        XCTAssertNil(b.deduplicated)
        XCTAssertEqual(try eventCount(.fileChange), 2)
    }

    // MARK: - The agent registry

    /// A write for an agent nobody registered is NOT dropped: the identity
    /// half is invented from the payload so the FK holds, and the invention is
    /// announced. That is the difference between registration-first as a
    /// guarantee and registration-first as a precondition.
    func testAMissingRegistrationIsInventedFromThePayload() throws {
        _ = try store.promptStart(PromptStartRequest(promptUuid: promptA, variant: .bot))
        let change = try hookWrite(agentId: "a-explorer-9f", agentType: "gmcc:code-explorer")

        let linked = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT agent_registration_uuid FROM file_change WHERE uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        let row = try XCTUnwrap(try registration(agentId: "a-explorer-9f"))
        XCTAssertEqual(linked, row.uuid)
        XCTAssertEqual(row.agentType, "gmcc:code-explorer")
        XCTAssertEqual(row.claudeSessionId, conversation)
        XCTAssertEqual(row.claudeTurnId, "turn-9")
        XCTAssertEqual(row.sessionUuid, sessionUuid)
        XCTAssertEqual(row.promptUuid, promptA)
        // The authority half is the SPAWNER's to write, and stays empty until
        // it does.
        XCTAssertNil(row.role)
        XCTAssertNil(row.methodology)
        XCTAssertNil(row.workflowPhase)
        XCTAssertEqual(try eventCount(.agentUnregistered), 1)

        // A second write for the same agent reuses the row and announces
        // nothing — the event marks an invention, not an agent.
        _ = try hookWrite(path: "Sources/Second.swift", agentId: "a-explorer-9f")
        XCTAssertEqual(try eventCount(.agentUnregistered), 1)
    }

    /// ORDERING IS NOT A CONSTRAINT. A spawner that only learns its agent ids
    /// when a dynamic workflow reports back registers LATE, and the authority
    /// merges onto the same row — explaining changes that were written before
    /// it ever called.
    func testLateSpawnerRegistrationMergesOntoTheAlreadyWrittenRow() throws {
        let change = try hookWrite(agentId: "a-explorer-9f", agentType: "gmcc:code-explorer")
        let invented = try XCTUnwrap(try registration(agentId: "a-explorer-9f"))

        let response = try store.agentRegister(AgentRegisterRequest(
            agentId: "a-explorer-9f", role: "explorer",
            methodology: "data-flow", workflowPhase: "exploring"))
        XCTAssertFalse(response.created, "the row already existed")
        XCTAssertEqual(response.registration.uuid, invented.uuid)
        XCTAssertEqual(response.registration.role, "explorer")
        XCTAssertEqual(response.registration.methodology, "data-flow")
        XCTAssertEqual(response.registration.workflowPhase, "exploring")
        // The identity half is untouched by the merge.
        XCTAssertEqual(response.registration.agentType, "gmcc:code-explorer")
        XCTAssertEqual(response.registration.claudeTurnId, "turn-9")

        // And the change written before the spawner called now reads through
        // to the authority, because the join is at READ time.
        let role = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT ar.role FROM file_change fc
                JOIN agent_registration ar ON ar.uuid = fc.agent_registration_uuid
                WHERE fc.uuid = ?
                """, arguments: [change.fileChangeUuid])
        }
        XCTAssertEqual(role, "explorer")
    }

    /// The spawner may also get there first — then the row is its creation and
    /// the agent's writes hang off it, with nothing invented.
    func testSpawnerFirstRegistrationIsReusedByTheAgentsWrites() throws {
        let created = try store.agentRegister(AgentRegisterRequest(
            agentId: "a-architect-11", role: "architect"))
        XCTAssertTrue(created.created)

        let change = try hookWrite(agentId: "a-architect-11")
        let linked = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT agent_registration_uuid FROM file_change WHERE uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        XCTAssertEqual(linked, created.registration.uuid)
        XCTAssertEqual(try eventCount(.agentUnregistered), 0)
    }

    /// THE SUBAGENT-START IDENTITY WRITE. It names a conversation and nothing
    /// else, and the daemon derives the gmcc session and prompt from the
    /// binding — the same single resolution path a file_change takes, so a
    /// registration cannot land in a session the binding disagrees with.
    func testIdentityRegistrationResolvesItsSessionThroughTheBinding() throws {
        try setStatus(promptA, .implementing)
        let response = try store.agentRegister(AgentRegisterRequest(
            agentId: "a349d9808be1c1472",
            agentType: "workflow-subagent",
            claudeSessionId: conversation,
            claudeTurnId: "turn-9"))

        XCTAssertTrue(response.created)
        XCTAssertEqual(response.registration.agentType, "workflow-subagent")
        XCTAssertEqual(response.registration.claudeSessionId, conversation)
        XCTAssertEqual(response.registration.claudeTurnId, "turn-9")
        XCTAssertEqual(response.registration.sessionUuid, sessionUuid)
        XCTAssertEqual(response.registration.promptUuid, promptA)
        // Identity only — the role the spawner owns is still open.
        XCTAssertNil(response.registration.role)

        // And because the hook beat the agent to it, the agent's first write
        // reuses the row rather than having one invented for it.
        let change = try hookWrite(agentId: "a349d9808be1c1472")
        let linked = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT agent_registration_uuid FROM file_change WHERE uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        XCTAssertEqual(linked, response.registration.uuid)
        XCTAssertEqual(try eventCount(.agentUnregistered), 0)
    }

    /// Neither half can blank the other, in EITHER order: identity first then
    /// authority is the ordinary case, and an unbound conversation still
    /// leaves a usable identity rather than failing the registration.
    func testIdentityAndAuthorityMergeWithoutClearingEachOther() throws {
        _ = try store.agentRegister(AgentRegisterRequest(
            agentId: "aconservative-d32a81b4b9dfa222",
            agentType: "conservative",
            claudeSessionId: "a-conversation-nobody-bound",
            claudeTurnId: "turn-2"))
        let merged = try store.agentRegister(AgentRegisterRequest(
            agentId: "aconservative-d32a81b4b9dfa222",
            role: "explorer", methodology: "conservative"))

        XCTAssertFalse(merged.created)
        XCTAssertEqual(merged.registration.role, "explorer")
        XCTAssertEqual(merged.registration.methodology, "conservative")
        // The payload's label survives the authority write, and the unbound
        // conversation left the uuids NULL instead of refusing the row.
        XCTAssertEqual(merged.registration.agentType, "conservative")
        XCTAssertNil(merged.registration.sessionUuid)
    }

    /// A bare re-register neither writes nor errors: the spawner is allowed to
    /// assert that a registration exists without naming any authority.
    func testRegisteringWithNoAuthorityLeavesTheRowAlone() throws {
        let created = try store.agentRegister(AgentRegisterRequest(
            agentId: "a-reviewer-3", role: "reviewer"))
        let again = try store.agentRegister(AgentRegisterRequest(agentId: "a-reviewer-3"))
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.registration.uuid, created.registration.uuid)
        XCTAssertEqual(again.registration.role, "reviewer")
        XCTAssertEqual(again.registration.version, created.registration.version)
    }

    /// THE PRIMARY carries no agent_id at all — that absence IS the
    /// primary/subagent discriminator — so its changes point at no
    /// registration and none is invented for it. This is why the FK column is
    /// nullable.
    func testAPrimaryWriteCarriesNoRegistration() throws {
        let change = try hookWrite()
        let linked = try store.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT agent_registration_uuid FROM file_change WHERE uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        XCTAssertNil(linked)
        let registrations = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agent_registration") ?? 0
        }
        XCTAssertEqual(registrations, 0)
        XCTAssertEqual(try eventCount(.agentUnregistered), 0)
    }

    // MARK: - The payload capture set

    /// One typed column per payload field, all the way out through
    /// FILE_CHANGE_LIST — a blob would have made every one of these axes
    /// unqueryable.
    func testPayloadColumnsRoundTripThroughList() throws {
        let change = try hookWrite(agentId: "a-explorer-9f", agentType: "gmcc:code-explorer",
                                   toolUseId: "toolu_3")
        let row = try XCTUnwrap(
            try store.listFileChanges(FileChangeListRequest(sessionUuid: sessionUuid))
                .changes.first(where: { $0.uuid == change.fileChangeUuid }))
        XCTAssertEqual(row.claudeSessionId, conversation)
        XCTAssertEqual(row.claudeTurnId, "turn-9")
        XCTAssertEqual(row.toolUseId, "toolu_3")
        XCTAssertEqual(row.toolName, "Edit")
        XCTAssertEqual(row.agentId, "a-explorer-9f")
        XCTAssertEqual(row.agentType, "gmcc:code-explorer")
        XCTAssertEqual(row.permissionMode, "acceptEdits")
        XCTAssertEqual(row.durationMs, 42)
        XCTAssertEqual(row.transcriptPath, "/tmp/transcript.jsonl")
        XCTAssertEqual(row.origin, FileChangeOrigin.hook)
        XCTAssertNotNil(row.agentRegistrationUuid)
    }

    // MARK: - structuredPatch ranges

    /// Exact line numbers off the payload, NEW-side: a hunk is recorded where
    /// it landed. A pure deletion reports newLines 0, and the floor puts it on
    /// the line it collapsed into rather than producing a zero-height range.
    func testHunksExpandToNewSideRanges() throws {
        let ranges = StructuredPatchExpander.expand([
            StructuredPatchHunk(
                oldStart: 10, oldLines: 3, newStart: 12, newLines: 4,
                lines: [" a", "-b", "+c", "+d"]),
            StructuredPatchHunk(
                oldStart: 40, oldLines: 2, newStart: 44, newLines: 0, lines: ["-x", "-y"]),
        ])
        XCTAssertEqual(ranges.map(\.lineStart), [12, 44])
        XCTAssertEqual(ranges.map(\.lineEnd), [15, 44])
        XCTAssertEqual(ranges[0].changedContent, " a\n-b\n+c\n+d")
    }

    /// file_change is append-only history and nothing trims it later, so the
    /// budget is enforced where the rows are written — a regenerated file
    /// cannot land a megabyte per change.
    func testRangeCapsAreEnforcedOnTheWrite() throws {
        let hunks = (0..<150).map { index in
            StructuredPatchHunk(
                oldStart: index * 10, oldLines: 1, newStart: index * 10, newLines: 1,
                lines: [String(repeating: "x", count: 9000)])
        }
        let change = try hookWrite(ranges: StructuredPatchExpander.expand(hunks))
        XCTAssertEqual(change.rangeUuids.count, FileChangeLimits.maxRangesPerChange)

        let longest = try store.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT MAX(LENGTH(changed_content)) FROM file_change_range WHERE file_change_uuid = ?",
                arguments: [change.fileChangeUuid])
        }
        XCTAssertEqual(longest, FileChangeLimits.maxChangedContentCharacters)
    }
}
