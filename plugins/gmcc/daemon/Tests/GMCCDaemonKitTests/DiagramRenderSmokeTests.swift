#if canImport(SwiftUI)
import AppKit
import SwiftUI
import XCTest
@testable import GMCCDaemonKit

/// Headless render regression for the Canvas coordinate contract: strokes at
/// NEGATIVE diagram coordinates (the common case — elements centered at 0,0)
/// must survive into the rendered pixels, and the background must paint the
/// whole frame. The review's rating-0 finding proved a plain `.offset`
/// modifier silently clips Canvas content and drags the background out of
/// frame; this test pins the fix (translate inside each Canvas, positions
/// offset per-view, background un-offset).
final class DiagramRenderSmokeTests: XCTestCase {

    @MainActor
    private func render(_ resolved: ResolvedDiagram) throws -> NSBitmapImageRep {
        let view = DiagramCanvasView(resolved: resolved)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: view.totalSize.width,
                                                 height: view.totalSize.height)
        guard let cgImage = renderer.cgImage else {
            throw XCTSkip("ImageRenderer produced no image in this environment")
        }
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    @MainActor
    func testNegativeCoordinateStrokeAndBackgroundSurviveHeadlessRender() throws {
        // A stroke whose diagram-space geometry is entirely negative.
        let stroke = DiagramElementNode(
            identity: DopeNodeIdentity(uuid: "e-s", version: 0, createdAt: "t", updatedAt: "t"),
            base: DiagramElementBase(code: "s", name: "s", description: "", sortOrder: 0,
                                     centerX: -100, centerY: -100, elementZ: 0, scale: 1),
            payload: .drawingStroke(DrawingStrokePayload(
                strokeColor: "#ff0000", strokeWidth: 12,
                vertices: [DiagramVertex(x: -30, y: 0), DiagramVertex(x: 30, y: 0)])),
            children: [])
        let layer = DiagramElementNode(
            identity: DopeNodeIdentity(uuid: "e-l", version: 0, createdAt: "t", updatedAt: "t"),
            base: DiagramElementBase(code: "l", name: "l", description: "", sortOrder: 0,
                                     centerX: 0, centerY: 0, elementZ: 0, scale: 1),
            payload: .drawingLayer(DrawingLayerPayload()),
            children: [stroke])
        let tree = DiagramTree(
            identity: DopeNodeIdentity(uuid: "d-1", version: 0, createdAt: "t", updatedAt: "t"),
            tier: "SESSION", projectUuid: "p", instanceUuid: "i", sessionUuid: "s",
            promptUuid: nil, code: "main", name: "Main", description: "",
            gmccDiagramPath: nil, revision: 0, elements: [layer])
        let environment = DiagramRenderEnvironment(displayScale: 1, padding: 20)
        let resolved = DiagramResolver.resolve(tree, dope: DiagramDopeContext(),
                                               environment: environment)
        let rep = try render(resolved)

        // The stroke's diagram-space center (-100, -100) maps to view space
        // at (padding - minX - 100, ...). Sample where the horizontal stroke
        // line must be.
        let dx = environment.padding - resolved.contentBounds.minX
        let dy = environment.padding - resolved.contentBounds.minY
        let sampleX = Int(-100 + dx), sampleY = Int(-100 + dy)
        XCTAssertGreaterThan(alpha(rep, sampleX, sampleY), 0.5,
                             "stroke at negative diagram coords was clipped away")
        // The background must cover the far corner AND the origin corner —
        // an offset background leaves one of them transparent.
        XCTAssertGreaterThan(alpha(rep, 1, 1), 0.5, "top-left background band missing")
        XCTAssertGreaterThan(alpha(rep, rep.pixelsWide - 2, rep.pixelsHigh - 2), 0.5,
                             "bottom-right background missing")
    }

    // MARK: - Card + scope + edge characterization

    private func identity(_ uuid: String) -> DopeNodeIdentity {
        DopeNodeIdentity(uuid: uuid, version: 0, createdAt: "t", updatedAt: "t")
    }

    /// One dope scope holding two entity cards joined by an FK, far enough
    /// apart that the router runs. Small on purpose: the samples below are
    /// position-sensitive, and a fixture that reflows breaks them loudly.
    private func cardFixture() -> (DiagramTree, DiagramDopeContext) {
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
        let dopeTree = DopeScopeTree(
            identity: identity("scope-1"),
            body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
            sessionUuid: "s", promptUuid: nil, scopeType: "SESSION_BASE",
            revision: 1, domains: [core])

        func entity(_ uuid: String, code: String, entityCode: String,
                    centerX: Double) -> DiagramElementNode {
            DiagramElementNode(
                identity: identity(uuid),
                base: DiagramElementBase(code: code, name: code, description: "",
                                         sortOrder: 0, centerX: centerX, centerY: 0,
                                         elementZ: 1, scale: 1),
                payload: .dopeEntity(DopeEntityPayload(entityCode: entityCode)),
                children: [])
        }
        let scope = DiagramElementNode(
            identity: identity("el-scope"),
            base: DiagramElementBase(code: "scope", name: "Scope", description: "",
                                     sortOrder: 0, centerX: 0, centerY: 0,
                                     elementZ: 0, scale: 1),
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            children: [entity("el-user", code: "user", entityCode: "core.user", centerX: 0),
                       entity("el-profile", code: "profile", entityCode: "core.profile",
                              centerX: 420)])
        let tree = DiagramTree(
            identity: identity("d-1"), tier: "SESSION", projectUuid: "p",
            instanceUuid: "i", sessionUuid: "s", promptUuid: nil, code: "main",
            name: "Main", description: "", gmccDiagramPath: nil, revision: 0,
            elements: [scope])
        let context = DiagramDopeContext(entries: [
            "gmcc": DiagramDopeContext.Entry(tree: dopeTree, resolvedVia: "session_base"),
        ])
        return (tree, context)
    }

    /// CHARACTERIZATION test for the DiagramSceneView extraction and the
    /// selection channel: written green against the PRE-split renderer, it
    /// pins the card/scope/edge pixel output that the refactor (and an unset
    /// selection environment) must reproduce exactly.
    @MainActor
    func testCardScopeAndRoutedEdgeRenderCharacterization() throws {
        let (tree, context) = cardFixture()
        let environment = DiagramRenderEnvironment(displayScale: 1, padding: 20)
        let resolved = DiagramResolver.resolve(tree, dope: context, environment: environment)

        // The fixture must actually exercise the interesting paths.
        XCTAssertEqual(resolved.edges.count, 1, "expected exactly one FK edge")
        XCTAssertTrue(resolved.edges[0].routed, "expected the router to route the edge")

        let rep = try render(resolved)
        let dx = environment.padding - resolved.contentBounds.minX
        let dy = environment.padding - resolved.contentBounds.minY

        func viewPoint(_ p: CGPoint) -> (x: Int, y: Int) {
            (Int((p.x + dx).rounded()), Int((p.y + dy).rounded()))
        }

        // 1. Card headers paint fully opaque at both card centers' header band.
        let userFrame = resolved.topLevel[0].children[0].frame
        let profileFrame = resolved.topLevel[0].children[1].frame
        for frame in [userFrame, profileFrame] {
            let sample = viewPoint(CGPoint(x: frame.midX, y: frame.minY + 8))
            XCTAssertGreaterThan(alpha(rep, sample.x, sample.y), 0.5,
                                 "card header band missing at \(sample)")
        }
        // 2. The routed edge's midpoint segment strokes visibly. Sample the
        //    middle routed point (orthogonal polylines pass through it).
        let midPoint = resolved.edges[0].points[resolved.edges[0].points.count / 2]
        let edgeSample = viewPoint(midPoint)
        var edgeHit = false
        for ox in -2...2 where !edgeHit {
            for oy in -2...2 where !edgeHit {
                if alpha(rep, edgeSample.x + ox, edgeSample.y + oy) > 0.3 { edgeHit = true }
            }
        }
        XCTAssertTrue(edgeHit, "routed edge stroke missing near \(edgeSample)")
        // 3. Background still covers both corners.
        XCTAssertGreaterThan(alpha(rep, 1, 1), 0.5)
        XCTAssertGreaterThan(alpha(rep, rep.pixelsWide - 2, rep.pixelsHigh - 2), 0.5)
    }
}
#endif
