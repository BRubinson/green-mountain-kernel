import XCTest
import GRDB
import GmDaemonSdk
@testable import GmDaemon
// One case below is a cross-module parity oracle; see the manifest.
import GmUxComponentLibrary

/// The DAEMON-SIDE half of the old DiagramKitAdditionsTests: the tree reducer
/// (containment, CAS, clientRef ledger, minting, single revision bump) and the
/// DIFFERENTIAL PARITY test that runs the same batch through the reducer and
/// through the daemon's `diagramBatchApply` and demands the same answer.
///
/// The parity test is why this half needs the Store, and it is the one case in
/// the pair that genuinely spans both sides of the reducer/daemon boundary —
/// which is exactly what it exists to guard.
///
/// See the render-side sibling in gmUxComponentLibrary for the hit test,
/// geometry, discard and organizer cases. The value fixtures are duplicated
/// there; see that file's header for why.


private func identity(_ uuid: String) -> DopeNodeIdentity {
    DopeNodeIdentity(uuid: uuid, version: 0, createdAt: "t", updatedAt: "t")
}

private func element(
    _ uuid: String, code: String, payload: DiagramElementPayload,
    centerX: Double = 0, centerY: Double = 0, elementZ: Double = 0,
    scale: Double = 1, children: [DiagramElementNode] = []
) -> DiagramElementNode {
    DiagramElementNode(
        identity: identity(uuid),
        base: DiagramElementBase(code: code, name: code, description: "",
                                 sortOrder: 0, centerX: centerX, centerY: centerY,
                                 elementZ: elementZ, scale: scale),
        payload: payload, children: children)
}

private func diagramTree(_ elements: [DiagramElementNode],
                         revision: Int64 = 0) -> DiagramTree {
    DiagramTree(identity: identity("d-1"), tier: "SESSION", projectUuid: "proj-1",
                instanceUuid: "inst-1", sessionUuid: "sess-1", promptUuid: nil,
                code: "main", name: "Main", description: "", gmccDiagramPath: nil,
                revision: revision, elements: elements)
}

private func dopeFixture() -> DopeScopeTree {
    func property(_ code: String, relatedRef: String? = nil) -> DopePropertyNode {
        DopePropertyNode(identity: identity("p-\(code)"),
                         body: DopePropertyBody(
                            code: code, name: code, description: "", sortOrder: 0,
                            dataType: relatedRef == nil ? "uuid" : "relationship",
                            nullable: false, isUnique: false, autoIncrement: nil,
                            textCharLimit: nil, enumRef: nil,
                            relationshipTargetRef: relatedRef, baseOriginRef: nil))
    }
    let user = DopeEntityNode(
        identity: identity("e-user"),
        body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                             description: "", sortOrder: 0,
                             repoRepresentativeFile: nil, baseComposableRef: nil),
        properties: [property("id"), property("profile", relatedRef: "core.profile.id")])
    let profile = DopeEntityNode(
        identity: identity("e-profile"),
        body: DopeEntityBody(code: "profile", name: "Profile", entityType: "MODEL",
                             description: "", sortOrder: 0,
                             repoRepresentativeFile: nil, baseComposableRef: nil),
        properties: [property("id")])
    let core = DopePersistenceNode(
        identity: identity("dom-core"),
        body: DopePersistenceBody(code: "core", name: "Core", description: "", sortOrder: 0),
        entities: [user, profile], enums: [])
    return DopeScopeTree(identity: identity("scope-1"),
                         body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                         sessionUuid: "sess-1", promptUuid: nil,
                         scopeType: "SESSION_BASE", revision: 1, domains: [core])
}

// `dopeContext()` and `cardTree()` are NOT duplicated here. They return
// DiagramDopeContext / a resolved card tree — render-side types that live in
// gmUxComponentLibrary, which this package does not depend on and should not.
// Copying a fixture across the split is tolerable; copying one that drags a
// module dependency with it is not.

final class DiagramTreeReducerTests: XCTestCase {

    private var minting: SequentialDiagramMinting!

    override func setUp() {
        minting = SequentialDiagramMinting()
    }

    func testClientRefParentingAndSingleRevisionBump() throws {
        let batch: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(clientRef: "L",
                                          payload: .drawingLayer(DrawingLayerPayload()))),
            .elementAdd(DiagramElementAdd(
                parentClientRef: "L",
                payload: .drawingShape(DrawingShapePayload(
                    shapeKind: .rectangle,
                    vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 10, y: 10)])))),
        ]
        let out = try DiagramTreeReducer.apply(batch, to: diagramTree([]), minting: minting)
        XCTAssertEqual(out.revision, 1, "exactly one bump per batch")
        XCTAssertEqual(out.elements.count, 1)
        XCTAssertEqual(out.elements[0].children.count, 1)
        XCTAssertEqual(out.elements[0].base.code, "layer_0001")
        XCTAssertEqual(out.elements[0].children[0].base.code, "shape_0001")
    }

    func testForwardClientRefRefused() {
        let batch: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(
                parentClientRef: "L",
                payload: .drawingStroke(DrawingStrokePayload(vertices: [])))),
        ]
        XCTAssertThrowsError(try DiagramTreeReducer.apply(batch, to: diagramTree([]),
                                                          minting: minting))
    }

    func testContainmentRefusedFromSpec() {
        // A stroke directly at the top level is illegal (needs drawing_layer).
        let batch: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(
                payload: .drawingStroke(DrawingStrokePayload(vertices: [])))),
        ]
        XCTAssertThrowsError(try DiagramTreeReducer.apply(batch, to: diagramTree([]),
                                                          minting: minting)) { error in
            guard case DiagramReducerError.badRequest = error as! DiagramReducerError else {
                return XCTFail("expected badRequest, got \(error)")
            }
        }
    }

    func testExpectedRevisionCAS() {
        let batch: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(payload: .drawingLayer(DrawingLayerPayload()))),
        ]
        XCTAssertThrowsError(try DiagramTreeReducer.apply(
            batch, to: diagramTree([], revision: 5), expectedRevision: 4,
            minting: minting)) { error in
            XCTAssertEqual(error as? DiagramReducerError,
                           .revisionConflict(expected: 4, actual: 5))
        }
    }

    func testElementVersionCASAndBumpOnUpdate() throws {
        let layer = element("el-l", code: "l", payload: .drawingLayer(DrawingLayerPayload()))
        let tree = diagramTree([layer])
        // Wrong version refused.
        XCTAssertThrowsError(try DiagramTreeReducer.apply(
            [.elementUpdate(DiagramElementUpdate(elementUuid: "el-l", expectedVersion: 3,
                                                 centerX: 10))],
            to: tree, minting: minting))
        // Right version applies and bumps.
        let out = try DiagramTreeReducer.apply(
            [.elementUpdate(DiagramElementUpdate(elementUuid: "el-l", expectedVersion: 0,
                                                 centerX: 10))],
            to: tree, minting: minting)
        XCTAssertEqual(out.elements[0].base.centerX, 10)
        XCTAssertEqual(out.elements[0].identity.version, 1)
    }

    func testDeleteCascadesSubtree() throws {
        let stroke = element("el-s", code: "s", payload: .drawingStroke(
            DrawingStrokePayload(vertices: [DiagramVertex(x: 0, y: 0),
                                            DiagramVertex(x: 1, y: 1)])))
        let layer = element("el-l", code: "l", payload: .drawingLayer(DrawingLayerPayload()),
                            children: [stroke])
        let out = try DiagramTreeReducer.apply(
            [.elementDelete(DiagramElementDelete(elementUuid: "el-l", expectedVersion: 0))],
            to: diagramTree([layer]), minting: minting)
        XCTAssertTrue(out.elements.isEmpty)
    }

    func testAllOrNothingLeavesInputUntouched() {
        let tree = diagramTree([])
        let batch: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(payload: .drawingLayer(DrawingLayerPayload()))),
            .elementAdd(DiagramElementAdd(
                payload: .drawingStroke(DrawingStrokePayload(vertices: [])))),  // illegal
        ]
        XCTAssertThrowsError(try DiagramTreeReducer.apply(batch, to: tree, minting: minting))
        XCTAssertEqual(tree.elements.count, 0, "value semantics: input untouched")
    }
}


// MARK: - Reducer ⇄ daemon parity (the differential oracle)

final class DiagramTreeReducerParityTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var diagramUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-parity-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, gmfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, gmfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, gmfs_relative_storage_path)
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

    /// Strip identity/timestamps (minted differently by construction) and
    /// compare the semantic shape: hierarchy, codes, names, base geometry,
    /// payloads, versions, revision.
    private func shape(_ tree: DiagramTree) -> String {
        func node(_ n: DiagramElementNode, depth: Int) -> String {
            let pad = String(repeating: "  ", count: depth)
            let base = n.base
            let payload = String(describing: n.payload)
            let children = n.children.map { node($0, depth: depth + 1) }.joined()
            return pad + "\(base.code)|\(base.name)|\(base.sortOrder)|"
                + "\(base.centerX),\(base.centerY),\(base.elementZ),\(base.scale)|"
                + "v\(n.identity.version)|\(payload)\n" + children
        }
        return "rev\(tree.revision)|\(tree.code)|\(tree.name)\n"
            + tree.elements.map { node($0, depth: 1) }.joined()
    }

    func testSameBatchesProduceIdenticalTreesThroughBothPaths() throws {
        // Batch 1: layer + two shapes via clientRef (minted codes exercised),
        // one dope scope + entity.
        let batch1: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(clientRef: "L",
                                          payload: .drawingLayer(DrawingLayerPayload()))),
            .elementAdd(DiagramElementAdd(
                parentClientRef: "L", centerX: 5, centerY: 6,
                payload: .drawingShape(DrawingShapePayload(
                    shapeKind: .rectangle,
                    vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 10, y: 10)])))),
            .elementAdd(DiagramElementAdd(
                parentClientRef: "L",
                payload: .drawingShape(DrawingShapePayload(
                    shapeKind: .line,
                    vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 30, y: 0)])))),
            .elementAdd(DiagramElementAdd(
                clientRef: "S", code: "scope_main", name: "Scope",
                payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")))),
            .elementAdd(DiagramElementAdd(
                parentClientRef: "S", centerX: 100,
                payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")))),
        ]

        // Daemon path.
        let response1 = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, expectedRevision: 0, mutations: batch1))
        var daemonTree = try store.diagramGet(
            DiagramGetRequest(diagramUuid: diagramUuid)).tree

        // Reducer path, from the same empty starting tree.
        let start = DiagramTree(
            identity: DopeNodeIdentity(uuid: diagramUuid, version: 0,
                                       createdAt: "t", updatedAt: "t"),
            tier: "SESSION", projectUuid: "proj-1", instanceUuid: "inst-1",
            sessionUuid: "sess-1", promptUuid: nil, code: "main", name: "Main",
            description: "", gmccDiagramPath: nil, revision: 0, elements: [])
        var localTree = try DiagramTreeReducer.apply(
            batch1, to: start, expectedRevision: 0,
            minting: SequentialDiagramMinting())

        XCTAssertEqual(shape(localTree), shape(daemonTree),
                       "batch 1 semantic shape must match through both paths")

        // Batch 2: update the entity's position (CAS v0), delete the layer
        // subtree — exercising update + cascade in both paths. Uuids differ
        // between paths, so resolve each side's own uuid by code.
        func uuid(code: String, in tree: DiagramTree) -> (String, Int64) {
            func find(_ nodes: [DiagramElementNode]) -> (String, Int64)? {
                for n in nodes {
                    if n.base.code == code { return (n.identity.uuid, n.identity.version) }
                    if let f = find(n.children) { return f }
                }
                return nil
            }
            return find(tree.elements)!
        }
        func batch2(for tree: DiagramTree) -> [DiagramMutation] {
            let entity = uuid(code: "entity_0001", in: tree)
            let layer = uuid(code: "layer_0001", in: tree)
            return [
                .elementUpdate(DiagramElementUpdate(
                    elementUuid: entity.0, expectedVersion: entity.1,
                    centerX: 250, centerY: -40)),
                .elementDelete(DiagramElementDelete(
                    elementUuid: layer.0, expectedVersion: layer.1)),
            ]
        }

        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, expectedRevision: response1.revision,
            mutations: batch2(for: daemonTree)))
        daemonTree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagramUuid)).tree

        localTree = try DiagramTreeReducer.apply(
            batch2(for: localTree), to: localTree,
            expectedRevision: localTree.revision,
            minting: SequentialDiagramMinting(prefix: "local2"))

        XCTAssertEqual(shape(localTree), shape(daemonTree),
                       "batch 2 semantic shape must match through both paths")
        XCTAssertEqual(localTree.revision, daemonTree.revision)
    }

    func testDopeCanvasLayoutScaffoldsIdenticallyThroughBothPaths() throws {
        // The scaffold path GMVibes uses: DopeCanvasLayout.mutations applied
        // to an empty tree through the reducer vs the daemon.
        let mutations = DopeCanvasLayout.mutations(for: dopeFixture())
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, expectedRevision: 0, mutations: mutations))
        let daemonTree = try store.diagramGet(
            DiagramGetRequest(diagramUuid: diagramUuid)).tree

        let start = DiagramTree(
            identity: DopeNodeIdentity(uuid: diagramUuid, version: 0,
                                       createdAt: "t", updatedAt: "t"),
            tier: "SESSION", projectUuid: "proj-1", instanceUuid: "inst-1",
            sessionUuid: "sess-1", promptUuid: nil, code: "main", name: "Main",
            description: "", gmccDiagramPath: nil, revision: 0, elements: [])
        let localTree = try DiagramTreeReducer.apply(
            mutations, to: start, expectedRevision: 0,
            minting: SequentialDiagramMinting())

        XCTAssertEqual(shape(localTree), shape(daemonTree))
    }
}
