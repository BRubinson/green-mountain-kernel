import XCTest
import GmDaemonSdk
@testable import GmUxComponentLibrary

/// The RENDER-SIDE half of the old DiagramKitAdditionsTests: the pure hit test
/// (reverse paint order, layer-never-returned, edge tolerance), the drag
/// divisor helper, the edit-session discard-during-flush rule, and the
/// organizer (determinism + the derived corridor floor).
///
/// SPLIT FROM its daemon-side sibling because the original file spanned two
/// modules: these cases reach DiagramResolver / DiagramOrganizer /
/// DiagramHitTest, which live here, while the reducer-vs-daemon parity oracle
/// needs the Store, which lives in gmDaemon. One file could not
/// `@testable import` both without making one package depend on the other for
/// a test's sake.
///
/// The value fixtures below are duplicated in the sibling. That is deliberate
/// and it is the lesser evil: the alternative is a shared test-support library
/// product, which would put a test helper into the shipped package graph.


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
