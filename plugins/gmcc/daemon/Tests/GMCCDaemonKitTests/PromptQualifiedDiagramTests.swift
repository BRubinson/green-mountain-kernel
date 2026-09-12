import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0022's whole contract. The table has no status machine to test, so the
/// assertions target what its restraint actually rests on: that a second
/// reading REPLACES the first rather than piling up, that both ends of the
/// pair are checked before the FK can fail anonymously, and that the
/// fingerprint survives the round trip well enough to still answer the
/// staleness question it was stored to answer.
final class PromptQualifiedDiagramTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0022-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-b")), 'sess-1', 2, 'p2', 'two', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeDiagram(code: String) throws -> DiagramRow {
        try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: code, name: code)).diagram
    }

    private func fingerprint(
        diagramUuid: String, revision: Int64, dope: [String: Int64] = ["gmcc": 645]
    ) throws -> String {
        let data = try DiagramRenderFingerprint(
            diagramUuid: diagramUuid, diagramRevision: revision,
            dopeRevisions: dope, scheme: "light", scale: 2).encoded()
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    private func qualify(
        prompt: String = "prompt-a", diagram: String, revision: Int64 = 1,
        path: String? = nil, dope: [String: Int64] = ["gmcc": 645],
        text: String = "the persistence layer, as this prompt reads it"
    ) throws -> PromptQualifiedDiagramRow {
        try store.promptDiagramQualify(PromptDiagramQualifyRequest(
            promptUuid: prompt, diagramUuid: diagram,
            renderedPath: path ?? "projects/repo/diagrams/screenshots/\(diagram).png",
            renderedRevision: revision,
            renderFingerprint: try fingerprint(
                diagramUuid: diagram, revision: revision, dope: dope),
            qualification: text))
    }

    // MARK: - Upsert

    /// The property the UNIQUE(prompt_uuid, diagram_uuid) exists for: a
    /// prompt's reading of a diagram is its CURRENT reading. Re-qualifying
    /// must not leave a reader two rows to choose between.
    func testRequalifyingReplacesInPlaceRatherThanAccumulating() throws {
        let diagram = try makeDiagram(code: "domain")
        let first = try qualify(diagram: diagram.uuid, revision: 1, text: "first reading")
        XCTAssertEqual(first.version, 0)

        let second = try qualify(
            diagram: diagram.uuid, revision: 4, dope: ["gmcc": 700], text: "second reading")

        // Same row, bumped — not a second row, and not a new uuid that would
        // strand anything already pointing at the first.
        XCTAssertEqual(second.uuid, first.uuid)
        XCTAssertEqual(second.version, 1)
        XCTAssertEqual(second.qualification, "second reading")
        XCTAssertEqual(second.renderedRevision, 4)
        XCTAssertEqual(
            try store.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_qualified_diagram")
            }, 1)
    }

    /// Two prompts reading the SAME diagram are two rows: the pair is the
    /// key, not the diagram.
    func testTwoPromptsCanQualifyTheSameDiagram() throws {
        let diagram = try makeDiagram(code: "domain")
        let a = try qualify(prompt: "prompt-a", diagram: diagram.uuid, text: "a reads it this way")
        let b = try qualify(prompt: "prompt-b", diagram: diagram.uuid, text: "b reads it that way")
        XCTAssertNotEqual(a.uuid, b.uuid)
        XCTAssertEqual(try store.promptDiagramList(
            PromptDiagramListRequest(promptUuid: "prompt-a")).qualifications.count, 1)
    }

    // MARK: - Existence

    /// Both ends are guarded, and the error NAMES the end that was wrong —
    /// a bare FK failure would leave the caller guessing.
    func testUnknownPromptAndUnknownDiagramAreBothNotFound() throws {
        let diagram = try makeDiagram(code: "domain")

        XCTAssertThrowsError(try qualify(prompt: "nope", diagram: diagram.uuid)) { error in
            guard case StoreError.notFound(let entity, let key) = error else {
                return XCTFail("expected notFound, got \(error)")
            }
            XCTAssertEqual(entity, "prompt")
            XCTAssertEqual(key, "nope")
        }

        XCTAssertThrowsError(try qualify(diagram: "no-such-diagram")) { error in
            guard case StoreError.notFound(let entity, let key) = error else {
                return XCTFail("expected notFound, got \(error)")
            }
            XCTAssertEqual(entity, "diagram")
            XCTAssertEqual(key, "no-such-diagram")
        }

        // The read verbs guard the same way, so a typo never reads as "empty".
        XCTAssertThrowsError(try store.promptDiagramList(
            PromptDiagramListRequest(promptUuid: "nope")))
        XCTAssertThrowsError(try store.promptDiagramGet(
            PromptDiagramGetRequest(promptUuid: "prompt-a", diagramUuid: "no-such-diagram")))
    }

    /// A real prompt with nothing recorded is SUMMARY_ABSENT, not NOT_FOUND:
    /// the caller's next move is to render, read and qualify — not to doubt
    /// the uuid. Same discrimination the report families make.
    func testRealPromptWithNoQualificationIsSummaryAbsent() throws {
        XCTAssertThrowsError(try store.promptDiagramGet(
            PromptDiagramGetRequest(promptUuid: "prompt-a"))) { error in
            guard case StoreError.summaryAbsent(let entity, let promptUuid) = error else {
                return XCTFail("expected summaryAbsent, got \(error)")
            }
            XCTAssertEqual(entity, "prompt_qualified_diagram")
            XCTAssertEqual(promptUuid, "prompt-a")
        }
        // …while list answers the same state with an empty list.
        XCTAssertTrue(try store.promptDiagramList(
            PromptDiagramListRequest(promptUuid: "prompt-a")).qualifications.isEmpty)
    }

    // MARK: - Get and list scoping

    func testListReturnsOnlyThatPromptsQualifications() throws {
        let domain = try makeDiagram(code: "domain")
        let flow = try makeDiagram(code: "flow")
        try qualify(prompt: "prompt-a", diagram: domain.uuid)
        try qualify(prompt: "prompt-a", diagram: flow.uuid)
        try qualify(prompt: "prompt-b", diagram: domain.uuid)

        let a = try store.promptDiagramList(PromptDiagramListRequest(promptUuid: "prompt-a"))
        XCTAssertEqual(Set(a.qualifications.map(\.diagramUuid)), [domain.uuid, flow.uuid])
        let b = try store.promptDiagramList(PromptDiagramListRequest(promptUuid: "prompt-b"))
        XCTAssertEqual(b.qualifications.map(\.diagramUuid), [domain.uuid])
    }

    /// An unqualified get with several rows refuses and names the count.
    /// Picking one arbitrarily would be the worst outcome available: the
    /// caller would read a real qualification of the wrong picture.
    func testUnqualifiedGetIsTheSingleRowOrARefusal() throws {
        let domain = try makeDiagram(code: "domain")
        try qualify(diagram: domain.uuid, text: "only reading")
        XCTAssertEqual(
            try store.promptDiagramGet(
                PromptDiagramGetRequest(promptUuid: "prompt-a")).qualification,
            "only reading")

        let flow = try makeDiagram(code: "flow")
        try qualify(diagram: flow.uuid)
        XCTAssertThrowsError(try store.promptDiagramGet(
            PromptDiagramGetRequest(promptUuid: "prompt-a"))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("expected badRequest, got \(error)")
            }
            XCTAssertTrue(detail.contains("2"), detail)
        }
        // Naming the diagram resolves it.
        XCTAssertEqual(
            try store.promptDiagramGet(PromptDiagramGetRequest(
                promptUuid: "prompt-a", diagramUuid: domain.uuid)).qualification,
            "only reading")
    }

    // MARK: - The fingerprint

    /// The column is opaque JSON text, and that is only useful if it comes
    /// back byte-identical enough to DECODE and still compare equal — which
    /// is the entire staleness mechanism. A round trip that merely returned
    /// "some string" would pass a weaker test and fail the real job.
    func testFingerprintRoundTripsAndStillAnswersStaleness() throws {
        let diagram = try makeDiagram(code: "domain")
        let stored = try qualify(diagram: diagram.uuid, revision: 3, dope: ["gmcc": 645])

        let decoded = try XCTUnwrap(DiagramRenderFingerprint.decoded(
            Data(stored.renderFingerprint.utf8)))
        XCTAssertEqual(decoded.diagramUuid, diagram.uuid)
        XCTAssertEqual(decoded.diagramRevision, 3)
        XCTAssertEqual(decoded.dopeRevisions, ["gmcc": 645])
        XCTAssertTrue(decoded.matches(DiagramRenderFingerprint(
            diagramUuid: diagram.uuid, diagramRevision: 3,
            dopeRevisions: ["gmcc": 645], scheme: "light", scale: 2)))

        // The failure this whole column exists to catch: a bound dope tree
        // moved, the diagram did not, and the qualification is now about a
        // picture that no longer exists.
        XCTAssertFalse(decoded.matches(DiagramRenderFingerprint(
            diagramUuid: diagram.uuid, diagramRevision: 3,
            dopeRevisions: ["gmcc": 700], scheme: "light", scale: 2)))
    }

    /// A fingerprint that is not a JSON object could never be compared
    /// against a sidecar, so it is refused at write time rather than
    /// discovered to be useless at read time.
    func testNonJsonFingerprintAndEmptyQualificationAreRefused() throws {
        let diagram = try makeDiagram(code: "domain")
        XCTAssertThrowsError(try store.promptDiagramQualify(PromptDiagramQualifyRequest(
            promptUuid: "prompt-a", diagramUuid: diagram.uuid,
            renderedPath: "p.png", renderedRevision: 1,
            renderFingerprint: "not json", qualification: "x")))
        XCTAssertThrowsError(try qualify(diagram: diagram.uuid, text: "   \n  "))
    }

    // MARK: - Schema

    /// Cascade, so deleting a prompt cannot strand its readings.
    func testDeletingThePromptCascades() throws {
        let diagram = try makeDiagram(code: "domain")
        try qualify(diagram: diagram.uuid)
        try store.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM prompt WHERE uuid = 'prompt-a'")
        }
        XCTAssertEqual(
            try store.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM prompt_qualified_diagram")
            }, 0)
    }

    /// The ledger head: the applied rows and the compiled constant agree, and
    /// the value is pinned so a migration cannot land silently.
    func testSchemaVersionMatchesCompiledConstant() throws {
        XCTAssertEqual(try store.schemaVersion(), Migrations.currentSchemaVersion)
        XCTAssertEqual(Migrations.currentSchemaVersion, 26)
        try store.dbQueue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations"), 26)
            XCTAssertEqual(
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM schema_migrations WHERE version = 25"), 1)
            // Both FK indexes, named for the family.
            for index in ["idx_prompt_qualified_diagram_prompt_fk",
                          "idx_prompt_qualified_diagram_diagram_fk"] {
                XCTAssertEqual(
                    try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?",
                        arguments: [index]), 1, "missing index \(index)")
            }
            // The restraint, asserted: no status column, no findings table,
            // no FTS mirror. If a later change adds one, this is where the
            // design decision gets re-opened deliberately.
            let sql = try String.fetchOne(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                arguments: ["prompt_qualified_diagram"]) ?? ""
            XCTAssertTrue(sql.contains("UNIQUE(prompt_uuid, diagram_uuid)"), sql)
            XCTAssertFalse(sql.contains("status"), sql)
            for table in ["prompt_qualified_diagram_fts", "prompt_qualified_diagram_finding"] {
                XCTAssertEqual(
                    try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM sqlite_master WHERE name = ?",
                        arguments: [table]), 0, "\(table) should not exist")
            }
        }
    }

    /// The event is durable and its OWN kind: nothing about the canvas moved,
    /// so a diagram listener must not be told to refetch a tree.
    func testQualifyAppendsItsOwnDurableEvent() throws {
        let diagram = try makeDiagram(code: "domain")
        let row = try qualify(diagram: diagram.uuid)
        try store.dbQueue.read { db in
            let event = try Row.fetchOne(
                db,
                sql: """
                    SELECT kind, subject_uuid, payload FROM daemon_event
                    WHERE kind = ? ORDER BY id DESC LIMIT 1
                    """,
                arguments: [DaemonEventKind.promptDiagramQualified.rawValue])
            let unwrapped = try XCTUnwrap(event)
            XCTAssertEqual(unwrapped["subject_uuid"], row.uuid)
            let payload: String = unwrapped["payload"]
            XCTAssertTrue(payload.contains(diagram.uuid), payload)
        }
    }
}
