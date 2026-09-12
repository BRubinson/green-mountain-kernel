import XCTest
@testable import GMCCDaemonKit

/// The two-phase resolve: deferred placement, two edge producers feeding one
/// router call, and the registry-driven obstacle policy.
///
/// The property that matters most here is NOT that connectors draw — it is
/// that adding them changed nothing about FK edges. A refactor of the
/// resolver that silently moved existing geometry would be invisible in a
/// screenshot review and catastrophic in a diff.
final class DiagramConnectorTests: XCTestCase {

    // MARK: - Fixtures (mirrors DiagramResolverTests so geometry is comparable)

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

    private func tree(_ elements: [DiagramElementNode]) -> DiagramTree {
        DiagramTree(identity: identity("d-1"), tier: "SESSION", projectUuid: "proj-1",
                    instanceUuid: "inst-1", sessionUuid: "sess-1", promptUuid: nil,
                    code: "main", name: "Main", description: "", gmccDiagramPath: nil,
                    revision: 0, elements: elements)
    }

    private func dopeTree() -> DopeScopeTree {
        func property(_ code: String, dataType: String = "text",
                      relatedRef: String? = nil) -> DopePropertyNode {
            DopePropertyNode(identity: identity("p-\(code)"),
                             body: DopePropertyBody(
                                code: code, name: code, description: "", sortOrder: 0,
                                dataType: dataType, nullable: true, isUnique: false,
                                autoIncrement: nil, textCharLimit: nil, enumRef: nil,
                                relationshipTargetRef: relatedRef, baseOriginRef: nil))
        }
        let user = DopeEntityNode(
            identity: identity("e-user"),
            body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [property("id", dataType: "uuid"),
                         property("profile", dataType: "relationship",
                                  relatedRef: "core.profile.id")])
        let profile = DopeEntityNode(
            identity: identity("e-profile"),
            body: DopeEntityBody(code: "profile", name: "Profile", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [property("id", dataType: "uuid")])
        let core = DopePersistenceNode(
            identity: identity("dom-core"),
            body: DopePersistenceBody(code: "core", name: "Core",
                                      description: "", sortOrder: 0),
            entities: [user, profile], enums: [])
        return DopeScopeTree(identity: identity("scope-1"),
                             body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                             sessionUuid: "sess-1", promptUuid: nil,
                             scopeType: "SESSION_BASE", revision: 7, domains: [core])
    }

    private func context() -> DiagramDopeContext {
        DiagramDopeContext(entries: [
            "gmcc": DiagramDopeContext.Entry(tree: dopeTree(), resolvedVia: "session_base"),
        ])
    }

    /// scope > [user card, profile card], with an optional connector parented
    /// under the user card pointing at the profile card — a PEER of its own
    /// parent, which is the containment rule.
    private func scene(connectorTarget: String?, includeConnector: Bool = true)
        -> DiagramTree {
        var userChildren: [DiagramElementNode] = []
        if includeConnector {
            userChildren.append(element(
                "e-conn", code: "connector_0001",
                payload: .connector(ConnectorPayload(
                    targetElementUuid: connectorTarget, strokeColor: "#ff0000",
                    strokeWidth: 3, lineStyle: .dashed, headKind: .arrow,
                    label: "points at"))))
        }
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0,
                               children: userChildren)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, profileCard])
        return tree([scope])
    }

    // MARK: - The regression that gates the whole refactor

    /// FK edge geometry must be BYTE-IDENTICAL with and without connectors
    /// on the canvas.
    ///
    /// Connectors join the same router call as FK edges — deliberately, so
    /// both steer around the same obstacles — and the risk that buys is that
    /// adding one silently reroutes the other. A connector is not an
    /// obstacle (`participatesInRouting == false`), so it must contribute
    /// nothing to the FK solution.
    func testFkEdgeGeometryIsUnchangedByAddingAConnector() {
        let without = DiagramResolver.resolve(
            scene(connectorTarget: nil, includeConnector: false), dope: context())
        let with = DiagramResolver.resolve(
            scene(connectorTarget: "e-profile"), dope: context())

        let fkWithout = without.edges.filter { $0.origin == .dopeForeignKey }
        let fkWith = with.edges.filter { $0.origin == .dopeForeignKey }
        XCTAssertEqual(fkWithout.count, 1)
        XCTAssertEqual(fkWith.count, fkWithout.count)
        for (a, b) in zip(fkWithout, fkWith) {
            XCTAssertEqual(a.propertyRef, b.propertyRef)
            XCTAssertEqual(a.routed, b.routed)
            XCTAssertEqual(a.points, b.points,
                           "adding a connector must not move an FK edge by a single point")
        }
    }

    /// Determinism survives the refactor: resolving twice is identical.
    func testResolvingTwiceProducesIdenticalEdgeGeometry() {
        let first = DiagramResolver.resolve(scene(connectorTarget: "e-profile"),
                                            dope: context())
        let second = DiagramResolver.resolve(scene(connectorTarget: "e-profile"),
                                             dope: context())
        XCTAssertEqual(first.edges.map(\.points), second.edges.map(\.points))
        XCTAssertEqual(first.edges.map(\.propertyRef), second.edges.map(\.propertyRef))
    }

    // MARK: - Deferred resolution

    func testConnectorResolvesAgainstTheCompletedFrameIndex() {
        let resolved = DiagramResolver.resolve(scene(connectorTarget: "e-profile"),
                                               dope: context())
        let connectorEdges = resolved.edges.filter {
            if case .connector = $0.origin { return true }
            return false
        }
        XCTAssertEqual(connectorEdges.count, 1, "the connector produced exactly one edge")
        let edge = connectorEdges[0]
        // Its endpoints are its PARENT and its TARGET — a connector is drawn
        // as a child of the element it connects FROM.
        XCTAssertEqual(edge.fromElementUuid, "e-user")
        XCTAssertEqual(edge.toElementUuid, "e-profile")
        guard case .connector(let elementUuid, let style) = edge.origin else {
            return XCTFail("expected a connector origin")
        }
        XCTAssertEqual(elementUuid, "e-conn")
        XCTAssertEqual(style.lineStyle, .dashed)
        XCTAssertEqual(style.label, "points at")
    }

    /// Both producers feed ONE router call, so both kinds of edge appear in
    /// one edge list having been solved against the same obstacle graph.
    func testConnectorAndFkEdgesShareOneEdgeList() {
        let resolved = DiagramResolver.resolve(scene(connectorTarget: "e-profile"),
                                               dope: context())
        XCTAssertEqual(resolved.edges.count, 2)
        XCTAssertEqual(resolved.edges.filter { $0.origin == .dopeForeignKey }.count, 1)
        XCTAssertEqual(resolved.edges.filter {
            if case .connector = $0.origin { return true }
            return false
        }.count, 1)
    }

    /// The element itself is patched with real geometry, not left at the
    /// phase-1 placeholder — hit-testing and content bounds depend on it.
    func testConnectorElementIsPatchedWithItsResolvedTarget() {
        let resolved = DiagramResolver.resolve(scene(connectorTarget: "e-profile"),
                                               dope: context())
        let userCard = resolved.topLevel[0].children.first { $0.uuid == "e-user" }
        let connector = userCard?.children.first { $0.uuid == "e-conn" }
        guard case .connector(let style)? = connector?.kind else {
            return XCTFail("expected a connector element")
        }
        guard case .resolved(let targetFrame) = style.target else {
            return XCTFail("connector target should have resolved in phase 2")
        }
        XCTAssertFalse(targetFrame.isEmpty)
        // Its frame spans both endpoints, so contentBounds cannot clip it.
        XCTAssertGreaterThan(connector?.frame.width ?? 0, 0)
    }

    // MARK: - Ghosts

    /// A connector with no target — deleted (ON DELETE SET NULL) or never
    /// set — is a LEGAL ghost. It emits no edge and renders nothing, exactly
    /// like a dangling dope binding.
    func testConnectorWithNoTargetIsAGhostNotAnError() {
        let resolved = DiagramResolver.resolve(scene(connectorTarget: nil),
                                               dope: context())
        XCTAssertEqual(resolved.edges.filter {
            if case .connector = $0.origin { return true }
            return false
        }.count, 0, "a targetless connector must emit no edge")
        // The FK edge is unaffected — one ghost does not break the diagram.
        XCTAssertEqual(resolved.edges.filter { $0.origin == .dopeForeignKey }.count, 1)
    }

    func testConnectorPointingAtAVanishedElementIsAGhost() {
        let resolved = DiagramResolver.resolve(
            scene(connectorTarget: "e-does-not-exist"), dope: context())
        XCTAssertEqual(resolved.edges.filter {
            if case .connector = $0.origin { return true }
            return false
        }.count, 0)
        let userCard = resolved.topLevel[0].children.first { $0.uuid == "e-user" }
        let connector = userCard?.children.first { $0.uuid == "e-conn" }
        guard case .connector(let style)? = connector?.kind else {
            return XCTFail("expected a connector element")
        }
        XCTAssertEqual(style.target, .absent)
    }

    // MARK: - Obstacle policy (decision 10, encoded as registry data)

    func testRoutingParticipationMatchesTheDecidedPolicy() {
        // Structural content blocks routing.
        XCTAssertTrue(DiagramElementTypeSpec.spec(for: .dopeEntity).participatesInRouting)
        XCTAssertTrue(DiagramElementTypeSpec.spec(for: .drawingShape).participatesInRouting)
        XCTAssertTrue(DiagramElementTypeSpec.spec(for: .drawingText).participatesInRouting)
        // Ink does NOT — you draw over and around a canvas freely, and a
        // dense stroke corpus would swamp the router.
        XCTAssertFalse(DiagramElementTypeSpec.spec(for: .drawingStroke).participatesInRouting)
        XCTAssertFalse(DiagramElementTypeSpec.spec(for: .drawingLayer).participatesInRouting)
        // A connector is a route, not an obstacle to other routes.
        XCTAssertFalse(DiagramElementTypeSpec.spec(for: .connector).participatesInRouting)
    }

    /// A text box between two cards is an obstacle, so the FK edge between
    /// them must route differently than it does on an empty canvas.
    func testTextBoxBetweenCardsChangesTheFkRoute() {
        func sceneWithText(_ include: Bool) -> DiagramTree {
            var layerChildren: [DiagramElementNode] = []
            if include {
                layerChildren.append(element(
                    "e-text", code: "t",
                    payload: .drawingText(DrawingTextPayload(
                        markdown: "in the way", width: 200, height: 200)),
                    centerX: 250, centerY: 0))
            }
            let layer = element("e-layer", code: "l",
                                payload: .drawingLayer(DrawingLayerPayload()),
                                children: layerChildren)
            let userCard = element("e-user", code: "u", payload: .dopeEntity(
                DopeEntityPayload(entityCode: "core.user")), centerX: 0)
            let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
                DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
            let scope = element("e-scope", code: "sc",
                                payload: .dopeScopePersistenceLayer(
                                    DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                                children: [userCard, profileCard])
            return tree([scope, layer])
        }
        let clear = DiagramResolver.resolve(sceneWithText(false), dope: context())
        let blocked = DiagramResolver.resolve(sceneWithText(true), dope: context())
        XCTAssertEqual(clear.edges.count, 1)
        XCTAssertEqual(blocked.edges.count, 1)
        XCTAssertNotEqual(clear.edges[0].points, blocked.edges[0].points,
                          "a text box in the corridor must push the FK edge around it")
    }

    /// The counterpart: ink in the same place must NOT move the edge.
    func testFreehandStrokeInTheCorridorDoesNotChangeTheFkRoute() {
        func sceneWithStroke(_ include: Bool) -> DiagramTree {
            var layerChildren: [DiagramElementNode] = []
            if include {
                layerChildren.append(element(
                    "e-ink", code: "s",
                    payload: .drawingStroke(DrawingStrokePayload(
                        strokeWidth: 4,
                        vertices: [DiagramVertex(x: -100, y: -100),
                                   DiagramVertex(x: 100, y: 100)])),
                    centerX: 250, centerY: 0))
            }
            let layer = element("e-layer", code: "l",
                                payload: .drawingLayer(DrawingLayerPayload()),
                                children: layerChildren)
            let userCard = element("e-user", code: "u", payload: .dopeEntity(
                DopeEntityPayload(entityCode: "core.user")), centerX: 0)
            let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
                DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
            let scope = element("e-scope", code: "sc",
                                payload: .dopeScopePersistenceLayer(
                                    DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                                children: [userCard, profileCard])
            return tree([scope, layer])
        }
        let clear = DiagramResolver.resolve(sceneWithStroke(false), dope: context())
        let inked = DiagramResolver.resolve(sceneWithStroke(true), dope: context())
        XCTAssertEqual(clear.edges[0].points, inked.edges[0].points,
                       "edges cross ink by design — decision 10")
    }
}
