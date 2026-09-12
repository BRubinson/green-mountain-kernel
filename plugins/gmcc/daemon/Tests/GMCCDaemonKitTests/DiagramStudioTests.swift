import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Diagram Studio (v23) — the db-level contracts: the visibility axis and
/// its SESSION-only guard, the first diagram FTS mirror (trigger-synced,
/// churn-guarded), DIAGRAM_SEARCH's two modes, DIAGRAM_DELETE's cascade,
/// and the write-repo/ingest round trip with code-path target re-resolution.
final class DiagramStudioTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var repoRoot: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-studio-\(UUID().uuidString).db").path
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-studio-repo-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(
            atPath: repoRoot, withIntermediateDirectories: true)
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
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '\(repoRoot!)',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(atPath: repoRoot)
    }

    private func makeDiagram(code: String, name: String? = nil,
                             description: String = "") throws -> DiagramRow {
        try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: code, name: name ?? code,
            description: description)).diagram
    }

    // MARK: - Visibility axis

    func testVisibilityDefaultsPrivateAndPublicIsSessionTierOnly() throws {
        let diagram = try makeDiagram(code: "vis")
        XCTAssertEqual(diagram.visibility, "PRIVATE")

        // SESSION tier: PUBLIC is legal.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: diagram.version, visibility: .public))]))
        let updated = try XCTUnwrap(store.dbQueue.read { db in
            try self.store.fetchDiagram(db, uuid: diagram.uuid)
        })
        XCTAssertEqual(updated.visibility, "PUBLIC")

        // Promoting a PUBLIC diagram away from SESSION tier is refused.
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: updated.version,
                promotion: DiagramPromotion(tier: .project, ownerUuid: "proj-1")))])))

        // A PROJECT-tier diagram cannot go PUBLIC.
        let projectDiagram = try store.diagramInit(DiagramInitRequest(
            projectUuid: "proj-1", code: "proj_vis", name: "P")).diagram
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: projectDiagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: projectDiagram.version, visibility: .public))])))
    }

    // MARK: - FTS mirror

    func testDiagramFtsMirrorsInsertUpdateDelete() throws {
        let diagram = try makeDiagram(code: "auth_flow", name: "Auth Flow",
                                      description: "login handshake")
        func ftsHits(_ token: String) throws -> Int {
            try store.dbQueue.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM diagram_fts WHERE diagram_fts MATCH ?
                    """, arguments: [token]) ?? -1
            }
        }
        XCTAssertEqual(try ftsHits("handshake"), 1)

        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: diagram.version, name: "OAuth Dance"))]))
        XCTAssertEqual(try ftsHits("oauth"), 1)
        XCTAssertEqual(try ftsHits("dance"), 1)

        _ = try store.diagramDelete(DiagramDeleteRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(try ftsHits("handshake"), 0)
    }

    func testRevisionBumpDoesNotChurnTheFtsIndex() throws {
        // The AFTER UPDATE OF column list is load-bearing: a pencil stroke
        // bumps diagram.revision on every gesture, and a plain trigger
        // would rewrite the index each time. Prove a revision-only UPDATE
        // leaves the fts content rows untouched.
        let diagram = try makeDiagram(code: "hot_row")
        let before = try store.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT rowid, code FROM diagram_fts")
        }
        try store.dbQueue.write { db in
            _ = try self.store.bumpDiagramRevision(db, diagramUuid: diagram.uuid)
        }
        let after = try store.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT rowid, code FROM diagram_fts")
        }
        XCTAssertEqual(before.description, after.description)
    }

    // MARK: - Search

    func testSearchBrowsesWithoutAQueryAndRanksWithOne() throws {
        _ = try makeDiagram(code: "alpha", name: "Alpha", description: "first canvas")
        _ = try makeDiagram(code: "beta", name: "Beta", description: "second canvas")
        let promptless = try store.diagramInit(DiagramInitRequest(
            projectUuid: "proj-1", code: "gamma", name: "Gamma")).diagram

        // Browse mode: every project diagram, cross-tier.
        let browse = try store.diagramSearch(DiagramSearchRequest(projectUuid: "proj-1"))
        XCTAssertEqual(Set(browse.diagrams.map(\.code)), ["alpha", "beta", "gamma"])
        XCTAssertTrue(browse.diagrams.contains { $0.uuid == promptless.uuid })

        // Query mode: bm25 over the mirror.
        let hits = try store.diagramSearch(DiagramSearchRequest(
            projectUuid: "proj-1", query: "second"))
        XCTAssertEqual(hits.diagrams.map(\.code), ["beta"])

        // Session narrowing drops the project-tier row.
        let narrowed = try store.diagramSearch(DiagramSearchRequest(
            projectUuid: "proj-1", sessionUuid: "sess-1"))
        XCTAssertEqual(Set(narrowed.diagrams.map(\.code)), ["alpha", "beta"])

        // Nonsense query is a refusal, never a silent empty list.
        XCTAssertThrowsError(try store.diagramSearch(DiagramSearchRequest(
            projectUuid: "proj-1", query: "..!!..")))
    }

    // MARK: - Delete

    func testDeleteCascadesElementsAndEmitsDeletedEvent() throws {
        let diagram = try makeDiagram(code: "doomed")
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    clientRef: "layer", payload: .drawingLayer(DrawingLayerPayload()))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "layer",
                    payload: .umlNode(UmlNodePayload(nodeKind: .circle)))),
            ]))

        // Stale CAS refuses.
        XCTAssertThrowsError(try store.diagramDelete(DiagramDeleteRequest(
            diagramUuid: diagram.uuid, expectedRevision: 99)))

        let response = try store.diagramDelete(DiagramDeleteRequest(diagramUuid: diagram.uuid))
        XCTAssertEqual(response.cascadedElements, 2)
        try store.dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM diagram WHERE uuid = ?",
                arguments: [diagram.uuid]), 0)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM diagram_element WHERE diagram_uuid = ?",
                arguments: [diagram.uuid]), 0)
            XCTAssertEqual(try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM diagram_uml_node"), 0)
            let deleted = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM daemon_event
                 WHERE kind = 'DIAGRAM_CHANGE' AND subject_uuid = ?
                   AND payload LIKE '%"action":"deleted"%'
                """, arguments: [diagram.uuid])
            XCTAssertEqual(deleted, 1, "the durable goodbye event is missing")
        }
    }

    // MARK: - write-repo / ingest round trip

    func testPublicDiagramRoundTripsThroughRepoFiles() throws {
        let diagram = try makeDiagram(code: "portable", name: "Portable",
                                      description: "round trip")
        // A node pair joined by a connector — the code-path re-resolution
        // is the round trip's hardest part.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    clientRef: "layer", code: "layer",
                    payload: .drawingLayer(DrawingLayerPayload()))),
                .elementAdd(DiagramElementAdd(
                    clientRef: "a", parentClientRef: "layer", code: "node_a",
                    centerX: 0, centerY: 0,
                    payload: .umlNode(UmlNodePayload(
                        nodeKind: .roundedRect, markdown: "# A")))),
                .elementAdd(DiagramElementAdd(
                    clientRef: "b", parentClientRef: "layer", code: "node_b",
                    centerX: 300, centerY: 0,
                    payload: .umlNode(UmlNodePayload(nodeKind: .dbCylinder)))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "a", targetClientRef: "b", code: "edge",
                    payload: .connector(ConnectorPayload(
                        headKind: .openArrow, routingKind: .curved,
                        tailKind: .diamond, label: "writes")))),
            ]))
        var current = try XCTUnwrap(store.dbQueue.read { db in
            try self.store.fetchDiagram(db, uuid: diagram.uuid)
        })
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: current.version, visibility: .public))]))
        current = try XCTUnwrap(store.dbQueue.read { db in
            try self.store.fetchDiagram(db, uuid: diagram.uuid)
        })

        // 1. write-repo lands the file, uuid-free.
        let written = try store.diagramWriteRepo(DiagramWriteRepoRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(written.written, ["portable"])
        let fileURL = URL(fileURLWithPath: written.root)
            .appendingPathComponent("portable.diagram.doped.json")
        let data = try Data(contentsOf: fileURL)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(diagram.uuid),
                       "document must be uuid-free")
        let document = try DiagramDocumentCodec.decode(data)
        XCTAssertEqual(document.version, current.revision)

        // 2. Idempotent: a second pass rewrites the same content, no gate trip.
        let again = try store.diagramWriteRepo(DiagramWriteRepoRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(again.written, ["portable"])

        // 3. Delete the db row, ingest from files: the diagram comes back at
        //    SESSION tier + PUBLIC with the connector re-targeted by path.
        _ = try store.diagramDelete(DiagramDeleteRequest(diagramUuid: diagram.uuid))
        let ingest = try store.diagramIngest(DiagramIngestRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(ingest.ingested, ["portable"])

        let revived = try store.diagramGet(DiagramGetRequest(
            sessionUuid: "sess-1", code: "portable"))
        XCTAssertEqual(revived.tree.revision, document.version)
        var connector: ConnectorPayload?
        var targetUuidByCode: [String: String] = [:]
        func walk(_ node: DiagramElementNode) {
            targetUuidByCode[node.base.code] = node.identity.uuid
            if case .connector(let payload) = node.payload { connector = payload }
            for child in node.children { walk(child) }
        }
        for element in revived.tree.elements { walk(element) }
        let payload = try XCTUnwrap(connector)
        XCTAssertEqual(payload.targetElementUuid, targetUuidByCode["node_b"],
                       "connector code path must re-resolve to the re-minted target")
        XCTAssertEqual(payload.routingKind, .curved)
        XCTAssertEqual(payload.tailKind, .diamond)

        // 4. Forward-only: a second ingest with nothing newer is a no-op.
        let repeatIngest = try store.diagramIngest(DiagramIngestRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(repeatIngest.ingested, [])
        XCTAssertEqual(repeatIngest.skipped, ["portable"])
    }

    func testIngestSkipsPrivateCollisionAndWriteRepoPrunesDemoted() throws {
        // A PRIVATE row whose code matches a repo file must never be
        // clobbered by boot sync.
        let diagram = try makeDiagram(code: "contested")
        var current = try XCTUnwrap(store.dbQueue.read { db in
            try self.store.fetchDiagram(db, uuid: diagram.uuid)
        })
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: current.version, visibility: .public))]))
        _ = try store.diagramWriteRepo(DiagramWriteRepoRequest(sessionUuid: "sess-1"))

        current = try XCTUnwrap(store.dbQueue.read { db in
            try self.store.fetchDiagram(db, uuid: diagram.uuid)
        })
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagram.uuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: current.version, visibility: .private))]))

        let ingest = try store.diagramIngest(DiagramIngestRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(ingest.skipped, ["contested"], "PRIVATE collision must skip")

        // And the next write-repo prunes the demoted diagram's file.
        let write = try store.diagramWriteRepo(DiagramWriteRepoRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(write.written, [])
        XCTAssertEqual(write.pruned, ["contested"])
    }
}
