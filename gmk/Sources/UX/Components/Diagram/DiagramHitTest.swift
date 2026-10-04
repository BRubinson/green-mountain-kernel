import CoreGraphics
import Foundation

/// Pure, SwiftUI-free hit resolution over the resolved value — the ONLY
/// place a host gesture becomes a target.
///
/// Non-hit-testing SwiftUI layers; the host's DragGesture converts location
/// to diagram space. Deliberately outside `#if canImport(SwiftUI)` so tests
/// run in plain XCTest.
enum DiagramHit: Sendable {
    case element(ResolvedElement)
    case edge(ResolvedEdge)
}

extension ResolvedDiagram {
    /// Performs a hit test at the given point using three ordered passes.
    ///
    /// Cards in reverse paint order, then edges by tolerance, then outlines.
    /// Deviates from paint order: fallback edges don't steal cards, and
    /// scope outline frames are unions of children.
    ///
    /// - Parameters:
    ///   - point: The test point in diagram space.
    ///   - edgeTolerance: The tolerance band for edge detection; default 6.
    ///   - includeInk: Whether to include ink strokes; default false.
    /// - Returns: The hit element or edge, or nil if nothing is hit.
    func hitTest(
        at point: CGPoint,
        edgeTolerance: CGFloat = 6,
        includeInk: Bool = false
    ) -> DiagramHit? {
        for element in topLevel.reversed() {
            if let hit = Self.hitElement(
                element,
                at: point,
                cardsOnly: true,
                includeInk: false,
                inkTolerance: edgeTolerance
            ) {
                return .element(hit)
            }
        }
        for edge in edges.reversed() {
            let points =
                edge.routed && edge.points.count >= 2
                ? edge.points : [edge.from, edge.to]
            for index in 0..<(points.count - 1) {
                if Self.distance(point, segment: points[index], points[index + 1])
                    <= edgeTolerance
                {
                    return .edge(edge)
                }
            }
        }
        for element in topLevel.reversed() {
            if let hit = Self.hitElement(
                element,
                at: point,
                cardsOnly: false,
                includeInk: includeInk,
                inkTolerance: edgeTolerance
            ) {
                return .element(hit)
            }
        }
        return nil
    }

    /// Finds an element by uuid using depth-first search in paint order.
    ///
    /// - Parameter uuid: The element uuid to find.
    /// - Returns: The matching element, or nil if not found.
    func element(uuid: String) -> ResolvedElement? {
        func find(_ element: ResolvedElement) -> ResolvedElement? {
            if element.uuid == uuid { return element }
            for child in element.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        for element in topLevel {
            if let found = find(element) { return found }
        }
        return nil
    }

    /// Recursively tests hit on an element and its children.
    ///
    /// - Parameters:
    ///   - element: The element to test.
    ///   - point: The test point in diagram space.
    ///   - cardsOnly: Whether to test cards only.
    ///   - includeInk: Whether to include ink strokes.
    ///   - inkTolerance: The ink tolerance distance.
    /// - Returns: The hit element, or nil if not hit.
    private static func hitElement(
        _ element: ResolvedElement,
        at point: CGPoint,
        cardsOnly: Bool,
        includeInk: Bool,
        inkTolerance: CGFloat
    ) -> ResolvedElement? {
        // Children first, reversed — the last-painted sibling wins, and an
        // entity card beats its containing scope outline.
        for child in element.children.reversed() {
            if let hit = hitElement(
                child,
                at: point,
                cardsOnly: cardsOnly,
                includeInk: includeInk,
                inkTolerance: inkTolerance
            ) {
                return hit
            }
        }
        switch element.kind {
        case .layer, .connector:
            return nil
        case .stroke(let stroke):
            // Opt-in only (the eraser): distance to the polyline, inflated
            // by half the drawn width so a fat marker is as grabbable as it
            // looks.
            guard includeInk, !cardsOnly, stroke.points.count >= 2 else { return nil }
            let tolerance = max(inkTolerance, stroke.lineWidth / 2 + 2)
            for index in 0..<(stroke.points.count - 1) {
                if distance(
                    point,
                    segment: stroke.points[index],
                    stroke.points[index + 1]
                ) <= tolerance {
                    return element
                }
            }
            return nil
        case .shape:
            guard includeInk, !cardsOnly else { return nil }
            return element.frame.insetBy(dx: -inkTolerance, dy: -inkTolerance)
                .contains(point) ? element : nil
        case .text:
            // A text box is a real bounded target — you click it to edit —
            // but it is drawing content, not a card, so it answers to the
            // same pass strokes and shapes would if they were hittable.
            guard !cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        case .umlNode:
            // A node is a card-grade target: selectable, draggable, and a
            // connector anchor — it answers in the same pass entity cards do.
            guard cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        case .entityCard, .absentEntity:
            guard cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        case .scopeCard, .absentScope:
            guard !cardsOnly else { return nil }
            return element.frame.contains(point) ? element : nil
        }
    }

    /// Returns the closest distance from a point to a line segment.
    ///
    /// Uses the Drawing/Geometry formula, kit-resident due to module boundary.
    ///
    /// - Parameters:
    ///   - p: The point to measure from.
    ///   - a: The segment start point.
    ///   - b: The segment end point.
    /// - Returns: The distance from p to the closest point on segment a-b.
    static func distance(_ p: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
        let nearest = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
        return hypot(p.x - nearest.x, p.y - nearest.y)
    }
}
