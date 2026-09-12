import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Tests for the slot-work kit additions: the pure hit test (reverse paint
/// order, layer-never-returned, edge tolerance), the drag divisor helper,
/// the tree reducer (containment, CAS, clientRef ledger, minting, single
/// revision bump) with a DIFFERENTIAL PARITY test against the daemon's
/// `diagramBatchApply`, and the organizer (determinism + the derived
/// corridor floor).

// MARK: - Shared value fixtures

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

private func dopeContext() -> DiagramDopeContext {
    DiagramDopeContext(entries: [
        "gmcc": DiagramDopeContext.Entry(tree: dopeFixture(), resolvedVia: "session_base"),
    ])
}

/// Scope with two FK-joined entity cards 420pt apart.
private func cardTree() -> DiagramTree {
    let scope = element(
        "el-scope", code: "scope",
        payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
        children: [
            element("el-user", code: "user",
                    payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                    elementZ: 1),
            element("el-profile", code: "profile",
                    payload: .dopeEntity(DopeEntityPayload(entityCode: "core.profile")),
                    centerX: 420, elementZ: 1),
        ])
    return diagramTree([scope])
}

// MARK: - Hit test

final class DiagramHitTestTests: XCTestCase {

    private func resolved() -> ResolvedDiagram {
        DiagramResolver.resolve(cardTree(), dope: dopeContext(),
                                environment: DiagramRenderEnvironment(displayScale: 1,
                                                                      padding: 20))
    }

    func testEntityCardBeatsItsContainingScope() {
        let r = resolved()
        let userFrame = r.element(uuid: "el-user")!.frame
        guard case .element(let hit)? = r.hitTest(at: CGPoint(x: userFrame.midX,
                                                              y: userFrame.midY)) else {
            return XCTFail("expected an element hit")
        }
        XCTAssertEqual(hit.uuid, "el-user", "the card, not the scope, must win")
    }

    func testScopeInteriorOutsideCardsHitsTheScope() {
        let r = resolved()
        let userFrame = r.element(uuid: "el-user")!.frame
        let profileFrame = r.element(uuid: "el-profile")!.frame
        // Between the two cards, above the edge's corridor midline.
        let gap = CGPoint(x: (userFrame.maxX + profileFrame.minX) / 2,
                          y: min(userFrame.minY, profileFrame.minY) + 1)
        if case .element(let hit)? = r.hitTest(at: gap) {
            XCTAssertEqual(hit.uuid, "el-scope")
        } else {
            XCTFail("expected the scope outline's interior to hit")
        }
    }

    func testLaterSiblingWinsOverlap() {
        // Two cards stacked at the same center; higher elementZ paints later.
        let scope = element(
            "el-scope", code: "scope",
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            children: [
                element("el-a", code: "a",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                        elementZ: 1),
                element("el-b", code: "b",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.profile")),
                        elementZ: 2),
            ])
        let r = DiagramResolver.resolve(diagramTree([scope]), dope: dopeContext())
        let frame = r.element(uuid: "el-b")!.frame
        guard case .element(let hit)? = r.hitTest(at: CGPoint(x: frame.midX, y: frame.midY))
        else { return XCTFail("expected a hit") }
        XCTAssertEqual(hit.uuid, "el-b", "the later-painted sibling must win")
    }

    func testDrawingLayerIsDescendedButNeverReturned() {
        let stroke = element("el-stroke", code: "s", payload: .drawingStroke(
            DrawingStrokePayload(strokeWidth: 4,
                                 vertices: [DiagramVertex(x: -50, y: 0),
                                            DiagramVertex(x: 50, y: 0)])))
        let layer = element("el-layer", code: "l",
                            payload: .drawingLayer(DrawingLayerPayload()),
                            children: [stroke])
        let r = DiagramResolver.resolve(diagramTree([layer]), dope: DiagramDopeContext())
        // Inside the layer's (child-derived) frame, on the stroke itself:
        // strokes are not hit in v1 and the layer must not swallow it.
        XCTAssertNil(r.hitTest(at: CGPoint(x: 0, y: 0)))
    }

    func testEdgeFallbackToleranceBand() {
        let r = resolved()
        XCTAssertEqual(r.edges.count, 1)
        let mid = r.edges[0].points[r.edges[0].points.count / 2]
        // Just off the polyline, inside tolerance — but only when no card is
        // there (the elements-first deviation).
        guard case .edge(let edge)? = r.hitTest(at: CGPoint(x: mid.x, y: mid.y + 3)) else {
            return XCTFail("expected an edge hit near \(mid)")
        }
        XCTAssertEqual(edge.propertyRef, "core.user.profile")
        // Far from the band, still inside the scope frame: the scope outline
        // (pass 3) catches it — not the edge.
        guard case .element(let fallthroughHit)? =
            r.hitTest(at: CGPoint(x: mid.x, y: mid.y + 40)) else {
            return XCTFail("expected the scope outline to catch the miss")
        }
        XCTAssertEqual(fallthroughHit.uuid, "el-scope")
    }

    func testMissOutsideEverything() {
        XCTAssertNil(resolved().hitTest(at: CGPoint(x: -10_000, y: -10_000)))
    }
}

// MARK: - Drag divisor

final class DiagramGeometryTests: XCTestCase {

    func testMoveMutationDividesByParentScaleNotOwnScale() {
        // A card with its OWN scale 0.5 inside a 2x scope: parent accumulated
        // scale is 2, element accumulated scale is 1.
        let scope = element(
            "el-scope", code: "scope",
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            scale: 2,
            children: [
                element("el-user", code: "user",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                        centerX: 10, centerY: 20, scale: 0.5),
            ])
        let r = DiagramResolver.resolve(diagramTree([scope]), dope: dopeContext())
        let resolvedCard = r.topLevel[0].children[0]
        XCTAssertEqual(resolvedCard.accumulatedScale, 1, accuracy: 0.0001)

        let node = DiagramTreeReducer.findNode("el-user", in: cardTreeWithScaledScope())!
        let mutation = DiagramDrag.moveMutation(node: node, resolved: resolvedCard,
                                                by: CGSize(width: 40, height: -20))
        guard case .elementUpdate(let update) = mutation else {
            return XCTFail("expected elementUpdate")
        }
        // Divisor = parent scale (2), NOT accumulated (1): 10 + 40/2 = 30.
        XCTAssertEqual(update.centerX!, 30, accuracy: 0.0001)
        XCTAssertEqual(update.centerY!, 10, accuracy: 0.0001)
    }

    private func cardTreeWithScaledScope() -> [DiagramElementNode] {
        [element("el-scope", code: "scope",
                 payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                 scale: 2,
                 children: [element("el-user", code: "user",
                                    payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                                    centerX: 10, centerY: 20, scale: 0.5)])]
    }

    func testRowCenterYAgreesWithResolvedEdgeAnchor() {
        let r = DiagramResolver.resolve(cardTree(), dope: dopeContext())
        let user = r.element(uuid: "el-user")!
        // The FK is core.user.profile at rowIndex 1; the edge leaves at that
        // row's y (side anchor y == row center y for routed edges' source).
        let expected = user.rowCenterY(1, environment: r.environment)
        XCTAssertEqual(r.edges[0].points[0].y, expected, accuracy: 0.5)
    }
}

// MARK: - Reducer

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

// MARK: - Edit session discard-during-flush

final class DiagramEditSessionDiscardTests: XCTestCase {

    /// A committer that parks until released, so a discard can land while
    /// the flush is awaiting the commit.
    private actor GatedCommitter: DiagramCommitting {
        private var gate: CheckedContinuation<Void, Never>?
        private var waiting: CheckedContinuation<Void, Never>?

        func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64 {
            waiting?.resume()
            waiting = nil
            await withCheckedContinuation { gate = $0 }
            return (expectedRevision ?? 0) + 1
        }

        func waitUntilCommitting() async {
            await withCheckedContinuation { waiting = $0 }
        }

        func release() {
            gate?.resume()
            gate = nil
        }
    }

    @MainActor
    func testDiscardDuringInFlightFlushNeitherTrapsNorEatsNewStages() async throws {
        let committer = GatedCommitter()
        // Test-only isolation opt-out: DiagramEditSession is a plain
        // non-Sendable class the app confines to MainActor; every touch in
        // this test happens on MainActor too, the flush Task included.
        nonisolated(unsafe) let session = DiagramEditSession(
            committer: committer, baseRevision: 0)
        session.stage(.elementUpdate(DiagramElementUpdate(
            elementUuid: "e-1", expectedVersion: 0, centerX: 1)))
        session.stage(.elementUpdate(DiagramElementUpdate(
            elementUuid: "e-2", expectedVersion: 0, centerX: 2)))

        let flushTask = Task { @MainActor in try await session.flush() }
        await committer.waitUntilCommitting()

        // Mid-flight: a cancelled-drag reset discards, then a NEW gesture
        // stages one mutation. Pre-fix, flush completion called
        // removeFirst(2) on a 1-element array and trapped.
        session.discard()
        session.stage(.elementUpdate(DiagramElementUpdate(
            elementUuid: "e-3", expectedVersion: 0, centerX: 3)))

        await committer.release()
        _ = try await flushTask.value

        XCTAssertEqual(session.staged.count, 1, "the post-discard stage must survive")
        if case .elementUpdate(let update)? = session.staged.first {
            XCTAssertEqual(update.elementUuid, "e-3")
        } else {
            XCTFail("expected the post-discard elementUpdate to remain staged")
        }
    }
}

// MARK: - Organizer

final class DiagramOrganizerTests: XCTestCase {

    /// Pile several FK-linked cards on one spot; organize must separate them
    /// past the derived corridor floor, deterministically.
    private func piledResolved() -> (ResolvedDiagram, DiagramTree) {
        let scope = element(
            "el-scope", code: "scope",
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            children: [
                element("el-a", code: "a",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                        centerX: 0, centerY: 0, elementZ: 1),
                element("el-b", code: "b",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.profile")),
                        centerX: 4, centerY: 2, elementZ: 2),
                element("el-c", code: "c",
                        payload: .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
                        centerX: -3, centerY: 5, elementZ: 3),
            ])
        let tree = diagramTree([scope])
        return (DiagramResolver.resolve(tree, dope: dopeContext()), tree)
    }

    func testMinSeparationIsDerivedFromRouterPadding() {
        XCTAssertEqual(DiagramOrganizer.minSeparation,
                       CGFloat(DiagramResolver.edgeRoutingPadding) * 2 + 2)
    }

    func testOrganizeSeparatesPiledCardsPastTheCorridorFloor() {
        let (resolved, _) = piledResolved()
        let centers = DiagramOrganizer.newCenters(for: resolved)
        XCTAssertFalse(centers.isEmpty)

        // Rebuild final frames from moved centers + original sizes.
        var frames: [CGRect] = []
        func collect(_ e: ResolvedElement) {
            switch e.kind {
            case .entityCard, .absentEntity:
                let center = centers[e.uuid] ?? CGPoint(x: e.frame.midX, y: e.frame.midY)
                frames.append(CGRect(x: center.x - e.frame.width / 2,
                                     y: center.y - e.frame.height / 2,
                                     width: e.frame.width, height: e.frame.height))
            default: break
            }
            e.children.forEach(collect)
        }
        resolved.topLevel.forEach(collect)
        XCTAssertEqual(frames.count, 3)

        let floor = DiagramOrganizer.minSeparation - 0.01
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                let gapX = max(frames[i].minX, frames[j].minX)
                    - min(frames[i].maxX, frames[j].maxX)
                let gapY = max(frames[i].minY, frames[j].minY)
                    - min(frames[i].maxY, frames[j].maxY)
                XCTAssertTrue(gapX >= floor || gapY >= floor,
                              "cards \(i)/\(j) closer than the corridor floor")
            }
        }
    }

    func testOrganizeIsDeterministic() {
        let (resolved, tree) = piledResolved()
        let first = DiagramOrganizer.organize(resolved, tree: tree)
        let second = DiagramOrganizer.organize(resolved, tree: tree)
        XCTAssertEqual(first, second)
    }
}
