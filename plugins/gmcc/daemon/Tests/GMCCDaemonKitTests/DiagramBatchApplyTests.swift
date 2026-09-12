import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The single-write-path contract: atomicity (any failure rolls back the
/// whole batch), exactly ONE revision bump + ONE DIAGRAM_CHANGE event per
/// batch, strict array order with clientRef parenting, and the optional
/// whole-diagram expectedRevision CAS.
final class DiagramBatchApplyTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var diagramUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-batch-\(UUID().uuidString).db").path
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
                """)
        }
        diagramUuid = try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: "main", name: "Main")).diagram.uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func revision() throws -> Int64 {
        try store.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT revision FROM diagram WHERE uuid = ?",
                               arguments: [diagramUuid!]) ?? -1
        }
    }

    private func diagramChangeEventCount() throws -> Int {
        try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM daemon_event WHERE kind = 'DIAGRAM_CHANGE'
                """) ?? -1
        }
    }

    // MARK: - One transaction, one bump, one event

    func testBatchBumpsRevisionOnceAndEmitsOneEvent() throws {
        let before = try revision()
        let eventsBefore = try diagramChangeEventCount()
        let response = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    clientRef: "layer", payload: .drawingLayer(DrawingLayerPayload()))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "layer",
                    payload: .drawingStroke(DrawingStrokePayload(
                        vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 5, y: 5)])))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "layer",
                    payload: .drawingShape(DrawingShapePayload(
                        shapeKind: .ellipse,
                        vertices: [DiagramVertex(x: -5, y: -5), DiagramVertex(x: 5, y: 5)])))),
            ]))
        XCTAssertEqual(response.results.count, 3)
        XCTAssertEqual(try revision(), before + 1, "three mutations, ONE revision bump")
        XCTAssertEqual(try diagramChangeEventCount(), eventsBefore + 1, "ONE event per batch")
        XCTAssertEqual(response.results[0].clientRef, "layer")
        // Index alignment.
        XCTAssertEqual(response.results.map(\.index), [0, 1, 2])
    }

    func testClientRefParentingCreatesGestureAtomically() throws {
        let response = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    clientRef: "l", payload: .drawingLayer(DrawingLayerPayload()))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "l",
                    payload: .drawingStroke(DrawingStrokePayload(
                        vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 1, y: 1)])))),
            ]))
        let layerUuid = response.results[0].uuid
        let tree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagramUuid)).tree
        XCTAssertEqual(tree.elements.count, 1)
        XCTAssertEqual(tree.elements[0].identity.uuid, layerUuid)
        XCTAssertEqual(tree.elements[0].children.count, 1)
    }

    func testForwardClientRefIsRefused() throws {
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "later",
                    payload: .drawingStroke(DrawingStrokePayload()))),
                .elementAdd(DiagramElementAdd(
                    clientRef: "later", payload: .drawingLayer(DrawingLayerPayload()))),
            ]))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("expected badRequest, got \($0)")
            }
            XCTAssertTrue(detail.contains("later"))
        }
    }

    // MARK: - Atomicity

    func testFailedMutationRollsBackTheWholeBatch() throws {
        let before = try revision()
        let eventsBefore = try diagramChangeEventCount()
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    code: "survivor", payload: .drawingLayer(DrawingLayerPayload()))),
                // Illegal: a stroke with no parent — fails validation.
                .elementAdd(DiagramElementAdd(
                    payload: .drawingStroke(DrawingStrokePayload()))),
            ])))
        XCTAssertEqual(try revision(), before, "revision untouched after rollback")
        XCTAssertEqual(try diagramChangeEventCount(), eventsBefore, "no phantom event")
        let count = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1
        }
        XCTAssertEqual(count, 0, "the first mutation must have rolled back too")
    }

    // MARK: - Revision CAS

    func testExpectedRevisionGateRefusesStaleWriters() throws {
        let current = try revision()
        // A correct gate passes.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, expectedRevision: current,
            mutations: [.elementAdd(DiagramElementAdd(
                payload: .drawingLayer(DrawingLayerPayload())))]))
        // Replaying the same gate is now stale — VERSION_CONFLICT wire code.
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, expectedRevision: current,
            mutations: [.elementAdd(DiagramElementAdd(
                payload: .drawingLayer(DrawingLayerPayload())))]))) {
            guard case StoreError.revisionConflict = $0 else {
                return XCTFail("expected revisionConflict, got \($0)")
            }
            XCTAssertEqual(($0 as? StoreError)?.errorPayload.code, .versionConflict)
        }
    }

    // MARK: - diagramUpdate mutations (rename / path patch / promotion)

    func testDiagramUpdateRenamePathAndPromotion() throws {
        // Rename + set path.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: 0, name: "Renamed",
                gmccDiagramPath: .set("docs/main.png")))]))
        var row = try store.diagramGet(DiagramGetRequest(diagramUuid: diagramUuid)).tree
        XCTAssertEqual(row.name, "Renamed")
        XCTAssertEqual(row.gmccDiagramPath, "docs/main.png")

        // Promotion SESSION → PROJECT. Two things changed with m0021 and
        // both are asserted here rather than assumed:
        //
        //  - INSTANCE is no longer a promotion target at all (the tier is
        //    gone), so the ladder is session → project directly.
        //  - The path SURVIVES promotion to PROJECT. It used to be
        //    auto-cleared because a schema CHECK refused a path at project
        //    tier — only an instance had a checkout to anchor one. CKFS
        //    storage gives every tier a root, so that CHECK and the silent
        //    clearing both went away.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: 1,
                promotion: DiagramPromotion(tier: .project, ownerUuid: "proj-1")))]))
        row = try store.diagramGet(DiagramGetRequest(diagramUuid: diagramUuid)).tree
        XCTAssertEqual(row.tier, "PROJECT")
        XCTAssertNil(row.sessionUuid)
        XCTAssertNil(row.promptUuid)
        // A project-tier diagram spans every checkout, so it has no single
        // instance — the fact that made the INSTANCE tier removable.
        XCTAssertNil(row.instanceUuid)
        XCTAssertEqual(row.gmccDiagramPath, "docs/main.png",
                       "gmcc_diagram_path is legal at PROJECT tier since m0021")
    }

    /// The retired tier answers with an explanation, not a shrug.
    func testInstanceTierIsRefusedWithAMigrationHint() throws {
        XCTAssertThrowsError(try store.diagramList(
            DiagramListRequest(instanceUuid: "inst-1"))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("expected badRequest, got \($0)")
            }
            XCTAssertTrue(detail.contains("INSTANCE"), detail)
            XCTAssertTrue(detail.contains("m0021"), detail)
        }
    }

    func testEmptyBatchIsRefused() throws {
        XCTAssertThrowsError(try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, mutations: [])))
    }

    // MARK: - Granular verbs ride the same body

    func testGranularDeleteReportsCascadeAndBumpsOnce() throws {
        let batch = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [
                .elementAdd(DiagramElementAdd(
                    clientRef: "l", payload: .drawingLayer(DrawingLayerPayload()))),
                .elementAdd(DiagramElementAdd(
                    parentClientRef: "l",
                    payload: .drawingStroke(DrawingStrokePayload(
                        vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 1, y: 1)])))),
            ]))
        let layerUuid = try XCTUnwrap(batch.results[0].uuid)
        let before = try revision()
        let deleted = try store.diagramNodeDelete(DiagramNodeDeleteRequest(
            delete: DiagramElementDelete(elementUuid: layerUuid, expectedVersion: 0)))
        XCTAssertEqual(deleted.cascadedElements, 2)
        XCTAssertEqual(deleted.revision, before + 1)
        let counts = try store.dbQueue.read { db in
            [try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_element") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_stroke_vertex") ?? -1]
        }
        XCTAssertEqual(counts, [0, 0])
    }
}
