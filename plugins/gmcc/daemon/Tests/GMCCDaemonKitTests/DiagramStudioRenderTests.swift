#if canImport(SwiftUI)
import AppKit
import SwiftUI
import XCTest
@testable import GMCCDaemonKit

/// Phase A's render gate, in two layers:
///   1. PURE geometry — head paths, node chrome, stroke outlines — asserted
///     headlessly with no rasterization, so CI always runs them.
///   2. The everything-diagram raster matrix: one canvas holding every
///     element kind and connector variant, rendered once, with per-element
///     pixel evidence. XCTSkip fires ONLY when ImageRenderer genuinely
///     cannot produce an image, and says so loudly.
final class DiagramStudioRenderTests: XCTestCase {

    // MARK: - 1. Pure geometry

    func testEveryHeadKindBuildsDistinctGeometryOrNothing() {
        let tip = CGPoint(x: 100, y: 100)
        let direction = CGVector(dx: 1, dy: 0)
        var bounds: [DiagramConnectorHead: CGRect] = [:]
        for kind in DiagramConnectorHead.allCases {
            let rendering = DiagramConnectorHeadGeometry.headPath(
                kind: kind, tip: tip, direction: direction, lineWidth: 2)
            if kind == .none {
                XCTAssertNil(rendering, ".none must draw nothing")
                continue
            }
            let unwrapped = try? XCTUnwrap(rendering, "\(kind) built no path")
            guard let unwrapped else { continue }
            let box = unwrapped.path.boundingRect
            XCTAssertFalse(box.isEmpty, "\(kind) built an empty path")
            // Every decoration hugs the tip.
            XCTAssertLessThan(abs(box.midX - tip.x), 20, "\(kind) strayed from the tip")
            bounds[kind] = box
        }
        // arrow fills, openArrow strokes — the v1 bug rendered both as dots.
        XCTAssertEqual(DiagramConnectorHeadGeometry.headPath(
            kind: .arrow, tip: tip, direction: direction, lineWidth: 2)?.fill, true)
        XCTAssertEqual(DiagramConnectorHeadGeometry.headPath(
            kind: .openArrow, tip: tip, direction: direction, lineWidth: 2)?.fill, false)
        // The arrow triangle is NOT the dot ellipse: it must extend behind
        // the tip along -x, where the dot stays centered on it.
        let arrow = bounds[.arrow]!
        let dot = bounds[.dot]!
        XCTAssertLessThan(arrow.minX, dot.minX - 1,
                          "arrow must sweep back along the segment, unlike dot")
    }

    func testHeadOrientationFollowsTheTerminalSegmentNotTheChord() {
        // A routed edge arriving VERTICALLY at its target: the head must
        // orient on the last segment (downward), not the horizontal chord.
        let edge = ResolvedEdge(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100),
            fromElementUuid: "a", toElementUuid: "b", propertyRef: "edge",
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
                     CGPoint(x: 200, y: 100)],
            routed: true,
            origin: .connector(elementUuid: "c", style: ResolvedConnector(
                target: .resolved(.zero), strokeColor: "#000", lineWidth: 2,
                lineStyle: .solid, headKind: .arrow, label: "")))
        guard case .connector(_, let style) = edge.origin else { return XCTFail() }
        let geometry = DiagramEdgeCanvas.connectorGeometry(edge: edge, style: style)
        XCTAssertEqual(geometry.headDirection.dx, 0, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.headDirection.dy, 0,
                             "head must arrive along the final vertical segment")
        XCTAssertLessThan(geometry.tailDirection.dx, 0,
                          "tail must point back out along the first segment")
    }

    func testRoutingKindsSelectDistinctPaths() {
        let style = { (routing: DiagramConnectorRouting) in
            ResolvedConnector(target: .resolved(.zero), strokeColor: "#000",
                              lineWidth: 2, lineStyle: .solid, headKind: .arrow,
                              routingKind: routing, tailKind: .none, label: "")
        }
        let edge = ResolvedEdge(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100),
            fromElementUuid: "a", toElementUuid: "b", propertyRef: "edge",
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
                     CGPoint(x: 200, y: 100)],
            routed: true)
        let straight = DiagramEdgeCanvas.connectorGeometry(edge: edge, style: style(.straight))
        let curved = DiagramEdgeCanvas.connectorGeometry(edge: edge, style: style(.curved))
        let stepped = DiagramEdgeCanvas.connectorGeometry(edge: edge, style: style(.orthogonalStep))
        // The chord's box is the from→to rect; the routed polyline detours.
        XCTAssertNotEqual(straight.path.description, stepped.path.description)
        XCTAssertNotEqual(straight.path.description, curved.path.description)
        XCTAssertNotEqual(curved.path.description, stepped.path.description)
    }

    func testEveryNodeKindBuildsChromeFillingItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 90)
        for kind in DiagramNodeKind.allCases {
            let path = UmlNodeShape(kind: kind).path(in: rect)
            let box = path.boundingRect
            XCTAssertFalse(box.isEmpty, "\(kind) chrome is empty")
            XCTAssertGreaterThan(box.width, rect.width * 0.6,
                                 "\(kind) chrome does not span its rect")
            XCTAssertGreaterThan(box.height, rect.height * 0.6,
                                 "\(kind) chrome does not span its rect")
        }
    }

    func testStrokeOutlinerDerivesAPressureAwarePolygon() {
        let points = stride(from: 0.0, through: 100, by: 10).map {
            CGPoint(x: $0, y: sin($0 / 20) * 10)
        }
        let pressures: [Double?] = points.enumerated().map {
            Double($0.offset) / Double(points.count)
        }
        let outline = StrokeOutliner.outline(
            points: points, pressures: pressures,
            options: StrokeOutliner.Options(size: 8))
        XCTAssertGreaterThan(outline.count, points.count,
                             "an outline is a polygon around the centerline")
        // Degenerate input falls back cleanly.
        XCTAssertTrue(StrokeOutliner.outline(
            points: [CGPoint(x: 1, y: 1)], pressures: [nil],
            options: StrokeOutliner.Options(size: 8)).isEmpty)
    }

    // MARK: - 2. The everything-diagram raster matrix

    private func identity(_ uuid: String) -> DopeNodeIdentity {
        DopeNodeIdentity(uuid: uuid, version: 0, createdAt: "t", updatedAt: "t")
    }

    private func element(_ uuid: String, code: String, x: Double, y: Double,
                         payload: DiagramElementPayload,
                         children: [DiagramElementNode] = []) -> DiagramElementNode {
        DiagramElementNode(
            identity: identity(uuid),
            base: DiagramElementBase(code: code, name: code, description: "",
                                     sortOrder: 0, centerX: x, centerY: y,
                                     elementZ: 1, scale: 1),
            payload: payload, children: children)
    }

    /// Every element kind, every node kind, and a connector per routing
    /// kind with distinct head/tail decorations — one canvas.
    private func everythingFixture() -> DiagramTree {
        var children: [DiagramElementNode] = []
        // Strokes: pencil with pressure, highlighter band.
        children.append(element("s-pencil", code: "pencil", x: 0, y: 0,
            payload: .drawingStroke(DrawingStrokePayload(
                tool: .pencil, strokeColor: "#c02020", strokeWidth: 5,
                vertices: [DiagramVertex(x: -40, y: 0, pressure: 0.2),
                           DiagramVertex(x: 0, y: -14, pressure: 0.9),
                           DiagramVertex(x: 40, y: 0, pressure: 0.4)]))))
        children.append(element("s-high", code: "high", x: 0, y: 50,
            payload: .drawingStroke(DrawingStrokePayload(
                tool: .highlighter, strokeColor: "#f0c000", strokeWidth: 10,
                vertices: [DiagramVertex(x: -40, y: 0), DiagramVertex(x: 40, y: 0)]))))
        // Every shape kind.
        let shapeVertices: [DiagramShapeKind: [DiagramVertex]] = [
            .rectangle: [DiagramVertex(x: -30, y: -20), DiagramVertex(x: 30, y: 20)],
            .ellipse: [DiagramVertex(x: -30, y: -20), DiagramVertex(x: 30, y: 20)],
            .line: [DiagramVertex(x: -30, y: -20), DiagramVertex(x: 30, y: 20)],
            .arrow: [DiagramVertex(x: -30, y: 0), DiagramVertex(x: 30, y: 0)],
            .polygon: [DiagramVertex(x: -30, y: 20), DiagramVertex(x: 0, y: -20),
                       DiagramVertex(x: 30, y: 20)],
        ]
        for (index, kind) in DiagramShapeKind.allCases.enumerated() {
            children.append(element("sh-\(kind.rawValue)", code: "sh_\(kind.rawValue)",
                x: Double(index) * 90, y: 130,
                payload: .drawingShape(DrawingShapePayload(
                    shapeKind: kind, strokeColor: "#204080", strokeWidth: 3,
                    fillColor: kind == .rectangle ? "#a0c0ff" : nil,
                    cornerRadius: kind == .rectangle ? 6 : nil,
                    vertices: shapeVertices[kind] ?? []))))
        }
        // Block-markdown text box.
        children.append(element("t-box", code: "tbox", x: 0, y: 260,
            payload: .drawingText(DrawingTextPayload(
                markdown: "# Title\n- one\n- two", width: 200, height: 90,
                fontSize: 12, textColor: "#101010", backgroundColor: "#f0f0f0"))))
        // Every node kind, spaced widely; connectors between neighbors
        // exercising every routing kind and several head/tail pairs.
        let routings: [DiagramConnectorRouting] = [.orthogonalStep, .straight, .curved]
        let heads: [DiagramConnectorHead] = [.arrow, .openArrow, .diamond,
                                             .circle, .cross, .dot]
        var previousRef: String?
        for (index, kind) in DiagramNodeKind.allCases.enumerated() {
            let uuid = "n-\(kind.rawValue)"
            var nodeChildren: [DiagramElementNode] = []
            if let target = previousRef {
                let connectorUuid = "c-\(kind.rawValue)"
                nodeChildren.append(element(connectorUuid, code: "c_\(kind.rawValue)",
                    x: 0, y: 0,
                    payload: .connector(ConnectorPayload(
                        targetElementUuid: target,
                        strokeColor: "#106040", strokeWidth: 2,
                        lineStyle: index % 2 == 0 ? .dashed : .solid,
                        headKind: heads[index % heads.count],
                        routingKind: routings[index % routings.count],
                        tailKind: heads[(index + 3) % heads.count],
                        label: index == 2 ? "flows" : ""))))
            }
            children.append(element(uuid, code: "n_\(kind.rawValue)",
                x: Double(index % 3) * 260, y: 420 + Double(index / 3) * 200,
                payload: .umlNode(UmlNodePayload(
                    nodeKind: kind, width: 170, height: 100,
                    markdown: "**\(kind.rawValue)**\n- field",
                    strokeColor: "#333366", strokeWidth: 2,
                    fillColor: "#eef1ff")), children: nodeChildren))
            previousRef = uuid
        }
        let layer = DiagramElementNode(
            identity: identity("layer"),
            base: DiagramElementBase(code: "layer", name: "layer", description: "",
                                     sortOrder: 0, centerX: 0, centerY: 0,
                                     elementZ: 0, scale: 1),
            payload: .drawingLayer(DrawingLayerPayload()), children: children)
        // A ghost scope card — the legal dangling-binding state must render.
        let ghost = element("g-scope", code: "ghost", x: 700, y: 40,
            payload: .dopeScopePersistenceLayer(
                DopeScopePersistenceLayerPayload(dopeScopeCode: "nowhere")))
        return DiagramTree(
            identity: identity("d-all"), tier: "SESSION", projectUuid: "p",
            instanceUuid: "i", sessionUuid: "s", promptUuid: nil,
            code: "everything", name: "Everything", description: "",
            gmccDiagramPath: nil, revision: 1, elements: [layer, ghost])
    }

    @MainActor
    func testEverythingDiagramRendersEveryKindWithPixelEvidence() throws {
        let tree = everythingFixture()
        let environment = DiagramRenderEnvironment(displayScale: 1, padding: 24)
        let resolved = DiagramResolver.resolve(tree, dope: DiagramDopeContext(),
                                               environment: environment)

        // The fixture must produce a connector edge per node after the first.
        let connectorEdges = resolved.edges.filter {
            if case .connector = $0.origin { return true }
            return false
        }
        XCTAssertEqual(connectorEdges.count, DiagramNodeKind.allCases.count - 1)

        let view = DiagramCanvasView(resolved: resolved)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: view.totalSize.width,
                                                 height: view.totalSize.height)
        guard let cgImage = renderer.cgImage else {
            throw XCTSkip("LOUD: ImageRenderer produced no image in this "
                + "environment — the raster matrix did NOT run (the pure "
                + "geometry layer above still did)")
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let dx = environment.padding - resolved.contentBounds.minX
        let dy = environment.padding - resolved.contentBounds.minY

        // Per-element pixel evidence: somewhere in each element's frame a
        // pixel differs from the flat background.
        let background = rep.colorAt(x: 1, y: 1)
        func differsFromBackground(in frame: CGRect, label: String) {
            var found = false
            let xs = stride(from: frame.minX, through: frame.maxX, by: max(2, frame.width / 24))
            let ys = stride(from: frame.minY, through: frame.maxY, by: max(2, frame.height / 24))
            for x in xs where !found {
                for y in ys where !found {
                    let px = Int((x + dx).rounded()), py = Int((y + dy).rounded())
                    guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
                          let color = rep.colorAt(x: px, y: py) else { continue }
                    if let background, !colorsMatch(color, background) { found = true }
                }
            }
            XCTAssertTrue(found, "\(label): no pixel evidence inside \(frame)")
        }
        // A scope outline's only body is its 1.5px dashed border — a coarse
        // grid over the frame slips between dashes, so walk the border line
        // itself pixel by pixel.
        func borderEvidence(in frame: CGRect, label: String) {
            var found = false
            var x = frame.minX
            while x <= frame.maxX, !found {
                for oy in -2...2 where !found {
                    let px = Int((x + dx).rounded())
                    let py = Int((frame.minY + dy).rounded()) + oy
                    guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
                          let color = rep.colorAt(x: px, y: py) else { continue }
                    if let background, !colorsMatch(color, background) { found = true }
                }
                x += 1
            }
            XCTAssertTrue(found, "\(label): no border evidence along \(frame)")
        }
        func walk(_ element: ResolvedElement) {
            switch element.kind {
            case .layer:
                break // transparent by design
            case .connector:
                break // drawn by the edge canvas; asserted via edges below
            case .scopeCard, .absentScope:
                borderEvidence(in: element.frame, label: element.code)
            default:
                differsFromBackground(in: element.frame.insetBy(dx: -2, dy: -2),
                                      label: element.code)
            }
            for child in element.children { walk(child) }
        }
        for element in resolved.topLevel { walk(element) }

        // Every connector edge leaves pixel evidence at its midpoint band.
        for edge in connectorEdges {
            let mid = edge.points[edge.points.count / 2]
            var found = false
            for ox in -6...6 where !found {
                for oy in -6...6 where !found {
                    let px = Int((mid.x + dx).rounded()) + ox
                    let py = Int((mid.y + dy).rounded()) + oy
                    guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
                          let color = rep.colorAt(x: px, y: py) else { continue }
                    if let background, !colorsMatch(color, background) { found = true }
                }
            }
            XCTAssertTrue(found, "edge \(edge.propertyRef): no stroke evidence near \(mid)")
        }
    }

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ca = a.usingColorSpace(.deviceRGB),
              let cb = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(ca.redComponent - cb.redComponent) < 0.02
            && abs(ca.greenComponent - cb.greenComponent) < 0.02
            && abs(ca.blueComponent - cb.blueComponent) < 0.02
    }
}
#endif
