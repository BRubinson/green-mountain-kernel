import XCTest
@testable import GMCCDaemonKit

/// Router semantics, pinned in plain XCTest against synthetic CGRects — no
/// resolver, no SwiftUI. The geometric no-crossing assertion (orthogonal
/// segment vs UNinflated card rect) is the real gate; determinism is
/// byte-equality across runs; the corridor-arithmetic fixture mirrors the
/// FROZEN layout generator so a future layout change breaks loudly here.
final class DiagramEdgeRouterTests: XCTestCase {

    // MARK: - Fixtures

    /// Generator constants mirrored from diagram_from_dope.py (FROZEN this
    /// prompt): CARD_W 260, X_PITCH 310, Y_GAP 48, header 40, row 22.
    private let cardW: CGFloat = 260
    private let xPitch: CGFloat = 310
    private let yGap: CGFloat = 48
    private let padding: CGFloat = 12

    private func card(_ x: CGFloat, _ y: CGFloat, rows: Int = 3) -> CGRect {
        CGRect(x: x, y: y, width: cardW, height: 40 + CGFloat(rows) * 22 + 8)
    }

    private func obstacles(_ frames: [CGRect]) -> [DiagramEdgeRouter.Obstacle] {
        frames.map { DiagramEdgeRouter.Obstacle(frame: $0, scale: 1) }
    }

    private func request(from: CGRect, to: CGRect, rowY: CGFloat,
                         ref: String = "core.a.fk",
                         uuid: String = "e-1") -> DiagramEdgeRouter.EdgeRequest {
        DiagramEdgeRouter.EdgeRequest(fromFrame: from, toFrame: to, sourceRowY: rowY,
                                      propertyRef: ref, fromElementUuid: uuid)
    }

    /// Strict-interior crossing test for an orthogonal segment against an
    /// UNinflated rect — routed paths must clear every card by construction.
    private func segmentCrosses(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> Bool {
        if a.y == b.y {
            let (lo, hi) = (min(a.x, b.x), max(a.x, b.x))
            return rect.minY < a.y && a.y < rect.maxY
                && lo < rect.maxX && hi > rect.minX
        }
        if a.x == b.x {
            let (lo, hi) = (min(a.y, b.y), max(a.y, b.y))
            return rect.minX < a.x && a.x < rect.maxX
                && lo < rect.maxY && hi > rect.minY
        }
        return true // a non-orthogonal segment is itself a failure
    }

    private func assertClears(_ polyline: DiagramEdgeRouter.RoutedPolyline,
                              frames: [CGRect], file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertTrue(polyline.routed, "expected a routed polyline", file: file, line: line)
        XCTAssertGreaterThanOrEqual(polyline.points.count, 2, file: file, line: line)
        for index in 0..<(polyline.points.count - 1) {
            let a = polyline.points[index], b = polyline.points[index + 1]
            XCTAssertTrue(a.x == b.x || a.y == b.y,
                          "segment \(index) is not orthogonal: \(a) → \(b)",
                          file: file, line: line)
            for frame in frames {
                XCTAssertFalse(segmentCrosses(a, b, frame),
                               "segment \(index) \(a) → \(b) crosses card \(frame)",
                               file: file, line: line)
            }
        }
    }

    // MARK: - Detour

    func testEdgeRoutesAroundBlockingCard() {
        let source = card(0, 0)
        let blocker = card(xPitch, -30, rows: 8) // tall card straddling the lane
        let target = card(xPitch * 2, 0)
        let frames = [source, blocker, target]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: source, to: target, rowY: source.midY)],
            obstacles: obstacles(frames), padding: padding)

        XCTAssertEqual(routes.count, 1)
        assertClears(routes[0], frames: frames)
        // The detour is real: a straight line from source to target would
        // cross the blocker.
        XCTAssertTrue(segmentCrosses(CGPoint(x: source.maxX, y: source.midY),
                                     CGPoint(x: target.minX, y: source.midY), blocker))
        // Endpoints are real card-border anchors.
        XCTAssertEqual(routes[0].points.first?.x, source.maxX)
        XCTAssertEqual(routes[0].points.last?.x, target.minX)
    }

    // MARK: - Determinism

    func testTwoRunsProduceIdenticalPointLists() {
        let frames = [card(0, 0), card(xPitch, -30, rows: 8), card(xPitch * 2, 0),
                      card(0, 300), card(xPitch, 400)]
        let edges = [
            request(from: frames[0], to: frames[2], rowY: frames[0].minY + 51,
                    ref: "core.a.fk1", uuid: "e-1"),
            request(from: frames[3], to: frames[4], rowY: frames[3].minY + 73,
                    ref: "core.b.fk2", uuid: "e-2"),
            request(from: frames[0], to: frames[4], rowY: frames[0].minY + 73,
                    ref: "core.a.fk3", uuid: "e-1"),
        ]
        let first = DiagramEdgeRouter.route(edges: edges, obstacles: obstacles(frames),
                                            padding: padding)
        let second = DiagramEdgeRouter.route(edges: edges, obstacles: obstacles(frames),
                                             padding: padding)
        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.routed, b.routed)
            XCTAssertEqual(a.points, b.points,
                           "identical runs must produce byte-identical polylines")
        }
    }

    // MARK: - Nudging

    func testParallelEdgesSharingACorridorAreSeparated() {
        // Two edges crossing between two columns through the SAME vertical
        // gutter: A1(top-left) → B2(bottom-right) and A2(bottom-left) →
        // B1(top-right). Their corridor runs overlap mid-route.
        let a1 = card(0, 0), a2 = card(0, 600)
        let b1 = card(xPitch, 300), b2 = card(xPitch, 900)
        let frames = [a1, a2, b1, b2]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: a1, to: b2, rowY: a1.midY, ref: "core.a1.fk", uuid: "e-a1"),
                    request(from: a2, to: b1, rowY: a2.midY, ref: "core.a2.fk", uuid: "e-a2")],
            obstacles: obstacles(frames), padding: padding)

        assertClears(routes[0], frames: frames)
        assertClears(routes[1], frames: frames)

        // No collinear overlap between the two polylines: for every pair of
        // parallel segments from different edges, sharing a line means their
        // spans must not overlap (the allocator separated them).
        for i in 0..<(routes[0].points.count - 1) {
            for j in 0..<(routes[1].points.count - 1) {
                let (p1, p2) = (routes[0].points[i], routes[0].points[i + 1])
                let (q1, q2) = (routes[1].points[j], routes[1].points[j + 1])
                if p1.x == p2.x && q1.x == q2.x && p1.x == q1.x {
                    let overlap = min(max(p1.y, p2.y), max(q1.y, q2.y))
                        - max(min(p1.y, p2.y), min(q1.y, q2.y))
                    XCTAssertLessThanOrEqual(overlap, 0,
                        "vertical runs at x=\(p1.x) overprint for \(overlap)pt")
                }
                if p1.y == p2.y && q1.y == q2.y && p1.y == q1.y {
                    let overlap = min(max(p1.x, p2.x), max(q1.x, q2.x))
                        - max(min(p1.x, p2.x), min(q1.x, q2.x))
                    XCTAssertLessThanOrEqual(overlap, 0,
                        "horizontal runs at y=\(p1.y) overprint for \(overlap)pt")
                }
            }
        }
    }

    // MARK: - Fallback

    func testEnclosedTerminusFallsBackUnrouted() {
        // The source card is sandwiched: both left and right neighbors sit
        // closer than 2×padding, so both escape-stub termini land strictly
        // inside a neighbor's inflated ring — the prescribed routed:false
        // fallback, detected before any search.
        let source = card(0, 0)
        let left = card(-cardW - 10, 0)
        let right = card(cardW + 10, 0)
        let target = card(xPitch * 3, 0)
        let frames = [source, left, right, target]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: source, to: target, rowY: source.midY)],
            obstacles: obstacles(frames), padding: padding)

        XCTAssertEqual(routes.count, 1)
        XCTAssertFalse(routes[0].routed)
        XCTAssertTrue(routes[0].points.isEmpty,
                      "unrouted result carries no points — the caller keeps its legacy pair")
    }

    // MARK: - Degenerate layouts

    func testOverlappingObstaclesRouteAroundTheUnion() {
        // Hand-layouts can overlap cards; the blocked intervals simply OR
        // together and the route clears the union.
        let source = card(0, 0)
        let blockerA = card(xPitch, -60, rows: 6)
        let blockerB = CGRect(x: xPitch + 80, y: 40, width: cardW, height: 180)
        let target = card(xPitch * 2 + 100, 0)
        let frames = [source, blockerA, blockerB, target]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: source, to: target, rowY: source.midY)],
            obstacles: obstacles(frames), padding: padding)
        assertClears(routes[0], frames: frames)
    }

    // MARK: - Corridor arithmetic (frozen generator)

    func testCorridorArithmeticMatchesFrozenGenerator() {
        // X_PITCH 310 − CARD_W 260 = 50pt column gutter → 26pt corridor at
        // padding 12; Y_GAP 48 → 24pt corridor. Pinned against the REAL
        // production padding (DiagramResolver.edgeRoutingPadding), not a
        // local mirror: if either the generator's geometry or the production
        // padding changes, this test fails first.
        let prodPadding = CGFloat(DiagramResolver.edgeRoutingPadding)
        XCTAssertEqual(prodPadding, padding,
                       "production routing padding is pinned to the frozen generator's"
                       + " corridors — change both deliberately, with the arithmetic below")
        let colLeft = card(0, 0)
        let colRight = card(xPitch, 0)
        let stackTop = card(0, 300)
        let stackBottom = CGRect(x: 0, y: 300 + stackTop.height + yGap,
                                 width: cardW, height: stackTop.height)

        let columnRects = [QRect(inflating: colLeft, by: prodPadding),
                           QRect(inflating: colRight, by: prodPadding)]
        let columnCorridor = columnRects[1].minX - columnRects[0].maxX
        XCTAssertEqual(columnCorridor, Quant.q(26), "column corridor must be 26pt")

        let stackRects = [QRect(inflating: stackTop, by: prodPadding),
                          QRect(inflating: CGRect(x: stackBottom.minX, y: stackBottom.minY,
                                                  width: stackBottom.width,
                                                  height: stackBottom.height), by: prodPadding)]
        let rowCorridor = stackRects[1].minY - stackRects[0].maxY
        XCTAssertEqual(rowCorridor, Quant.q(24), "row corridor must be 24pt")

        XCTAssertLessThan(prodPadding, yGap / 2,
                          "padding >= Y_GAP/2 closes every row-gap corridor")

        // And the corridor is actually usable: an edge through the column
        // gutter routes cleanly.
        let frames = [colLeft, colRight, stackTop, stackBottom]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: colLeft, to: stackBottom, rowY: colLeft.midY)],
            obstacles: obstacles(frames), padding: padding)
        assertClears(routes[0], frames: frames)
    }

    // MARK: - Hostile geometry (review fix, r40)

    func testHostileGeometryDegradesInsteadOfCrashing() {
        // NaN/inf/huge coordinates from unvalidated db doubles must degrade
        // (obstacle dropped, edge unrouted) — never trap at the Int64
        // boundary.
        let sane = card(0, 0)
        let target = card(xPitch, 0)
        let hostileObstacle = DiagramEdgeRouter.Obstacle(
            frame: CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 1e300, height: 40),
            scale: CGFloat.infinity)
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: sane, to: target, rowY: sane.midY),
                    request(from: CGRect(x: CGFloat.infinity, y: 0, width: 260, height: 150),
                            to: target, rowY: CGFloat.nan, ref: "core.bad.fk", uuid: "e-bad")],
            obstacles: obstacles([sane, target]) + [hostileObstacle],
            padding: padding)

        XCTAssertEqual(routes.count, 2)
        XCTAssertTrue(routes[0].routed, "sane edge still routes; hostile obstacle dropped")
        XCTAssertFalse(routes[1].routed, "hostile edge degrades to the legacy fallback")
        XCTAssertTrue(routes[1].points.isEmpty)
    }

    // MARK: - Stub blocking (review fix, r70)

    func testTinyCardInsideEscapeStubKillsThatCandidate() {
        // A tiny low-scale card sitting between the anchor and the stub
        // terminus is not caught by the terminus point check — the stub
        // SEGMENT test must kill that candidate so the edge exits the other
        // side instead of skewering the card.
        let source = card(0, 0)
        let target = card(-xPitch, 0) // reachable via the LEFT exit
        let tiny = CGRect(x: source.maxX + 3, y: source.midY - 1, width: 2, height: 2)
        let tinyObstacle = DiagramEdgeRouter.Obstacle(frame: tiny, scale: 0.1)
        let frames = [source, target]
        let routes = DiagramEdgeRouter.route(
            edges: [request(from: source, to: target, rowY: source.midY)],
            obstacles: obstacles(frames) + [tinyObstacle], padding: padding)

        XCTAssertEqual(routes.count, 1)
        assertClears(routes[0], frames: frames + [tiny])
        XCTAssertEqual(routes[0].points.first?.x, source.minX,
                       "blocked right stub forces the left exit")
    }

    // MARK: - Simplify

    func testSimplifyDropsZeroLengthAndMergesCollinear() {
        let raw = [QPoint(x: 0, y: 0), QPoint(x: 0, y: 0), QPoint(x: 256, y: 0),
                   QPoint(x: 512, y: 0), QPoint(x: 512, y: 256)]
        let merged = DiagramEdgeRouter.simplify(raw)
        XCTAssertEqual(merged, [QPoint(x: 0, y: 0), QPoint(x: 512, y: 0),
                                QPoint(x: 512, y: 256)])
    }
}
