import XCTest
@testable import GMCCDaemonKit

/// Resolver semantics, pinned in plain XCTest with zero SwiftUI: composed
/// transforms, sibling-only z with the (elementZ, code) tie-break,
/// deterministic FNV-1a colors, ghost injection, the composed-base property
/// union, and the FK edge pass.
final class DiagramResolverTests: XCTestCase {

    // MARK: - Fixtures

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

    private func tree(_ elements: [DiagramElementNode],
                      sessionUuid: String? = "sess-1") -> DiagramTree {
        DiagramTree(identity: identity("d-1"), tier: "SESSION", projectUuid: "proj-1",
                    instanceUuid: "inst-1", sessionUuid: sessionUuid, promptUuid: nil,
                    code: "main", name: "Main", description: "", gmccDiagramPath: nil,
                    revision: 0, elements: elements)
    }

    /// A dope tree: core.user (relationship → core.profile.id), core.profile,
    /// base.timestamps (BASE_COMPOSABLE) composed by core.user.
    private func dopeTree() -> DopeScopeTree {
        func property(_ code: String, dataType: String = "text", nullable: Bool = true,
                      isUnique: Bool = false, relatedRef: String? = nil,
                      baseOrigin: String? = nil) -> DopePropertyNode {
            DopePropertyNode(identity: identity("p-\(code)"),
                             body: DopePropertyBody(
                                code: code, name: code, description: "", sortOrder: 0,
                                dataType: dataType, nullable: nullable, isUnique: isUnique,
                                autoIncrement: nil, textCharLimit: nil, enumRef: nil,
                                relationshipTargetRef: relatedRef, baseOriginRef: baseOrigin))
        }
        let user = DopeEntityNode(
            identity: identity("e-user"),
            body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil,
                                 baseComposableRef: "base.timestamps"),
            properties: [
                property("id", dataType: "uuid", nullable: false, isUnique: true),
                property("profile", dataType: "relationship",
                         relatedRef: "core.profile.id"),
            ])
        let profile = DopeEntityNode(
            identity: identity("e-profile"),
            body: DopeEntityBody(code: "profile", name: "Profile", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [property("id", dataType: "uuid", nullable: false)])
        let timestamps = DopeEntityNode(
            identity: identity("e-ts"),
            body: DopeEntityBody(code: "timestamps", name: "Timestamps",
                                 entityType: "BASE_COMPOSABLE", description: "",
                                 sortOrder: 0, repoRepresentativeFile: nil,
                                 baseComposableRef: nil),
            properties: [property("created_at", dataType: "datetime", nullable: false)])
        let core = DopePersistenceNode(
            identity: identity("dom-core"),
            body: DopePersistenceBody(code: "core", name: "Core", description: "", sortOrder: 0),
            entities: [user, profile], enums: [])
        let base = DopePersistenceNode(
            identity: identity("dom-base"),
            body: DopePersistenceBody(code: "base", name: "Base", description: "", sortOrder: 0),
            entities: [timestamps], enums: [])
        return DopeScopeTree(identity: identity("scope-1"),
                             body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                             sessionUuid: "sess-1", promptUuid: nil,
                             scopeType: "SESSION_BASE", revision: 7,
                             domains: [core, base])
    }

    private func context() -> DiagramDopeContext {
        DiagramDopeContext(entries: [
            "gmcc": DiagramDopeContext.Entry(tree: dopeTree(), resolvedVia: "session_base"),
        ])
    }

    // MARK: - Transforms

    func testTransformsComposeParentSpaceCentersAndMultiplicativeScale() {
        let stroke = element("e-s", code: "s", payload: .drawingStroke(
            DrawingStrokePayload(strokeWidth: 2,
                                 vertices: [DiagramVertex(x: 0, y: 0),
                                            DiagramVertex(x: 10, y: 0)])),
                             centerX: 20, centerY: 0, scale: 2)
        let layer = element("e-l", code: "l", payload: .drawingLayer(DrawingLayerPayload()),
                            centerX: 100, centerY: 50, scale: 2, children: [stroke])
        let resolved = DiagramResolver.resolve(tree([layer]), dope: DiagramDopeContext())

        guard case .stroke(let resolvedStroke) = resolved.topLevel[0].children[0].kind else {
            return XCTFail("expected stroke kind")
        }
        // Stroke center = layer center + child offset * layer scale
        //              = (100 + 20*2, 50 + 0) = (140, 50).
        // Vertex 1 = center + v * effScale(4) = (140 + 40, 50).
        XCTAssertEqual(resolvedStroke.points[0], CGPoint(x: 140, y: 50))
        XCTAssertEqual(resolvedStroke.points[1], CGPoint(x: 180, y: 50))
        // Stroke width scales with the ACCUMULATED transform (2 * 4 = 8).
        XCTAssertEqual(resolvedStroke.lineWidth, 8)
    }

    // MARK: - Sibling z + tie-break

    func testSiblingOrderIsElementZThenCode() {
        let a = element("e-a", code: "bbb", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 1)
        let b = element("e-b", code: "aaa", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 1)
        let c = element("e-c", code: "zzz", payload: .drawingLayer(DrawingLayerPayload()),
                        elementZ: 0)
        let resolved = DiagramResolver.resolve(tree([a, b, c]), dope: DiagramDopeContext())
        XCTAssertEqual(resolved.topLevel.map(\.uuid), ["e-c", "e-b", "e-a"],
                       "z first, code tie-break — deterministic paint order")
    }

    // MARK: - Deterministic color

    func testDomainHueIsStableAcrossCallsAndDistinctishAcrossCodes() {
        XCTAssertEqual(DiagramPalette.domainHue("core"), DiagramPalette.domainHue("core"))
        XCTAssertNotEqual(DiagramPalette.domainHue("core"), DiagramPalette.domainHue("base"))
        let hue = DiagramPalette.domainHue("core")
        XCTAssertGreaterThanOrEqual(hue, 0)
        XCTAssertLessThan(hue, 1)
    }

    // MARK: - Entity cards + base union + ghosts

    func testEntityCardUnionsComposedBaseProperties() throws {
        let model = try XCTUnwrap(DiagramResolver.entityCard("core.user", in: dopeTree()))
        XCTAssertEqual(model.entityName, "User")
        XCTAssertEqual(model.domainCode, "core")
        let names = model.rows.map(\.name)
        XCTAssertEqual(names, ["id", "profile", "created_at"],
                       "own properties first, composed-base union appended")
        // Badges: id is NN+UQ; profile is FK; created_at came from the base.
        XCTAssertEqual(model.rows[0].badges, ["NN", "UQ"])
        XCTAssertTrue(model.rows[1].badges.contains("FK"))
        XCTAssertTrue(model.rows[2].badges.contains("B"))
    }

    func testGhostInjection() {
        let entityKnown = element("e-known", code: "known", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let entityMissing = element("e-missing", code: "missing", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.no_such")), centerX: 400)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [entityKnown, entityMissing])
        let danglingScope = element("e-ghost", code: "gs", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "nope")), centerX: 900,
                                    children: [element("e-ghost-child", code: "gc",
                                                       payload: .dopeEntity(DopeEntityPayload(
                                                        entityCode: "core.user")))])
        let resolved = DiagramResolver.resolve(tree([scope, danglingScope]), dope: context())

        let scopeElement = resolved.topLevel.first { $0.uuid == "e-scope" }!
        guard case .scopeCard(let card) = scopeElement.kind else {
            return XCTFail("expected scope card")
        }
        XCTAssertEqual(card.resolvedVia, "session_base")
        guard case .entityCard = scopeElement.children.first(where: { $0.uuid == "e-known" })!.kind
        else { return XCTFail("expected entity card") }
        guard case .absentEntity(let missingCode) =
                scopeElement.children.first(where: { $0.uuid == "e-missing" })!.kind
        else { return XCTFail("expected absentEntity ghost") }
        XCTAssertEqual(missingCode, "core.no_such")

        let ghostScope = resolved.topLevel.first { $0.uuid == "e-ghost" }!
        guard case .absentScope(let ghostCode) = ghostScope.kind else {
            return XCTFail("expected absentScope ghost")
        }
        XCTAssertEqual(ghostCode, "nope")
        // Children of an unresolved scope ghost too — no tree to look into.
        guard case .absentEntity = ghostScope.children[0].kind else {
            return XCTFail("expected the child of a ghost scope to ghost as well")
        }
    }

    // MARK: - FK edge pass

    func testRelationshipPropertiesBecomeEdgesBetweenRenderedCards() {
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        XCTAssertEqual(edge.fromElementUuid, "e-user")
        XCTAssertEqual(edge.toElementUuid, "e-profile")
        XCTAssertEqual(edge.propertyRef, "core.user.profile")
        XCTAssertLessThan(edge.from.x, edge.to.x, "edge leaves the side facing the target")
    }

    func testEdgeToUnrenderedEntityIsSimplyOmitted() {
        // Only the user card is on the canvas — the relationship's target has
        // no card, so no edge (and no error).
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")))
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")), children: [userCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())
        XCTAssertTrue(resolved.edges.isEmpty)
    }

    // MARK: - Edge routing integration

    func testRoutedEdgeLeavesAtTheFKPropertyRow() {
        // core.user's FK sits at row index 1 (own rows: id, profile —
        // base-union rows only append after). Card height = 40 + 3*22 + 8.
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 500)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        XCTAssertTrue(edge.routed)
        let userFrame = resolved.topLevel[0].children
            .first { $0.uuid == "e-user" }!.frame
        let expectedRowY = userFrame.minY + 40 + 1.5 * 22
        XCTAssertEqual(edge.from.y, expectedRowY, accuracy: 0.01,
                       "the edge leaves at the FK row's y, not the card midY")
        XCTAssertEqual(edge.from, edge.points.first)
        XCTAssertEqual(edge.to, edge.points.last)
    }

    func testRoutedEdgeFKRowAnchorHonorsScale() {
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0, scale: 2)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 900)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        let userFrame = resolved.topLevel[0].children
            .first { $0.uuid == "e-user" }!.frame
        XCTAssertEqual(edge.from.y, userFrame.minY + (40 + 1.5 * 22) * 2,
                       accuracy: 0.01, "row geometry scales with the card")
    }

    func testGhostCardIsARoutingObstacle() {
        // A ghost (.absentEntity) card sits squarely on the straight line
        // between user and profile — the routed edge must clear its frame.
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let ghost = element("e-ghost", code: "g", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.no_such")), centerX: 320, centerY: 10)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 640)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, ghost, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        XCTAssertTrue(edge.routed)
        let ghostFrame = resolved.topLevel[0].children
            .first { $0.uuid == "e-ghost" }!.frame
        for index in 0..<(edge.points.count - 1) {
            let a = edge.points[index], b = edge.points[index + 1]
            let crosses: Bool
            if a.y == b.y {
                crosses = ghostFrame.minY < a.y && a.y < ghostFrame.maxY
                    && min(a.x, b.x) < ghostFrame.maxX && max(a.x, b.x) > ghostFrame.minX
            } else {
                crosses = ghostFrame.minX < a.x && a.x < ghostFrame.maxX
                    && min(a.y, b.y) < ghostFrame.maxY && max(a.y, b.y) > ghostFrame.minY
            }
            XCTAssertFalse(crosses, "segment \(a) → \(b) crosses the ghost card")
        }
    }

    func testContentBoundsCoverRoutedDetours() {
        // Same blocking fixture: every routed point must be inside
        // contentBounds or detours clip out of the screenshot viewport.
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let ghost = element("e-ghost", code: "g", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.no_such")), centerX: 320, centerY: 10)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 640)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, ghost, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        for edge in resolved.edges {
            for point in edge.points {
                XCTAssertTrue(resolved.contentBounds.insetBy(dx: -0.01, dy: -0.01)
                    .contains(point),
                    "routed point \(point) escapes contentBounds \(resolved.contentBounds)")
            }
        }
    }

    func testSandwichedCardFallsBackToLegacyAnchorPair() {
        // Both of the user card's escape stubs are swallowed by neighbors
        // closer than 2×padding — the edge keeps the legacy straight pair.
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let wallL = element("e-wl", code: "wl", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.ghost_l")), centerX: -266)
        let wallR = element("e-wr", code: "wr", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.ghost_r")), centerX: 266)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 1200)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, wallL, wallR, profileCard])
        let resolved = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(resolved.edges.count, 1)
        let edge = resolved.edges[0]
        XCTAssertFalse(edge.routed)
        XCTAssertEqual(edge.points, [edge.from, edge.to],
                       "unrouted edges keep the legacy anchor pair")
        XCTAssertEqual(edge.from.y, resolved.topLevel[0].children
            .first { $0.uuid == "e-user" }!.frame.midY,
                       "legacy fallback keeps side-midpoint anchors")
    }

    func testResolveTwiceProducesIdenticalEdgeGeometry() {
        let userCard = element("e-user", code: "u", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), centerX: 0)
        let ghost = element("e-ghost", code: "g", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.no_such")), centerX: 320, centerY: 10)
        let profileCard = element("e-profile", code: "p", payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.profile")), centerX: 640)
        let scope = element("e-scope", code: "sc", payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                            children: [userCard, ghost, profileCard])
        let first = DiagramResolver.resolve(tree([scope]), dope: context())
        let second = DiagramResolver.resolve(tree([scope]), dope: context())

        XCTAssertEqual(first.edges.count, second.edges.count)
        for (a, b) in zip(first.edges, second.edges) {
            XCTAssertEqual(a.points, b.points)
            XCTAssertEqual(a.routed, b.routed)
        }
    }

    // MARK: - Bounds

    func testContentBoundsCoverEveryFrameAndAnEmptyDiagramGetsAFallback() {
        let empty = DiagramResolver.resolve(tree([]), dope: DiagramDopeContext())
        XCTAssertFalse(empty.contentBounds.isNull)
        XCTAssertGreaterThan(empty.contentBounds.width, 0)

        let far = element("e-far", code: "far", payload: .drawingLayer(DrawingLayerPayload()),
                          centerX: 2000, centerY: -1500)
        let resolved = DiagramResolver.resolve(tree([far]), dope: DiagramDopeContext())
        XCTAssertTrue(resolved.contentBounds.contains(CGPoint(x: 2000, y: -1500)))
    }
}
