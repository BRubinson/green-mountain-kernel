#if canImport(SwiftUI)
import SwiftUI

/// Pure connector head/tail geometry — Path values built from a tip point
/// and an incoming direction, with no Canvas or rasterization involved, so
/// every kind is unit-testable headlessly.
///
/// The direction MUST come from the terminal ROUTED segment (head: the last
/// segment, tail: the first segment reversed), never from the from→to chord:
/// the chord orientation is wrong exactly when routing did its job.
public enum DiagramConnectorHeadGeometry {

    /// How the built path should be painted.
    public struct Rendering {
        public let path: Path
        /// Fill for solid decorations (arrow, dot, diamond), stroke for the
        /// open ones (open_arrow, circle outline, cross).
        public let fill: Bool

        public init(path: Path, fill: Bool) {
            self.path = path
            self.fill = fill
        }
    }

    /// Decoration length for a given line width — one formula for every
    /// kind so mixed-head diagrams read as one family.
    public static func headLength(lineWidth: Double) -> CGFloat {
        max(8, lineWidth * 3)
    }

    /// The head path at `tip`, arriving along `direction` (need not be
    /// normalized; a zero vector falls back to +x so a degenerate edge still
    /// draws something sane). Returns nil for `.none`.
    public static func headPath(
        kind: DiagramConnectorHead, tip: CGPoint,
        direction: CGVector, lineWidth: Double
    ) -> Rendering? {
        let length = headLength(lineWidth: lineWidth)
        let magnitude = hypot(direction.dx, direction.dy)
        let unit = magnitude > 0.0001
            ? CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
            : CGVector(dx: 1, dy: 0)
        let angle = atan2(unit.dy, unit.dx)

        func back(_ distance: CGFloat, spread: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - distance * cos(angle + spread),
                    y: tip.y - distance * sin(angle + spread))
        }

        switch kind {
        case .none:
            return nil
        case .arrow:
            // Closed, filled triangle — the fix for the v1 bug where .arrow
            // shared .dot's ellipse branch and every arrow rendered as a dot.
            var path = Path()
            path.move(to: tip)
            path.addLine(to: back(length, spread: 0.45))
            path.addLine(to: back(length, spread: -0.45))
            path.closeSubpath()
            return Rendering(path: path, fill: true)
        case .dot:
            let radius = max(3, lineWidth * 1.5)
            return Rendering(
                path: Path(ellipseIn: CGRect(x: tip.x - radius, y: tip.y - radius,
                                             width: radius * 2, height: radius * 2)),
                fill: true)
        case .openArrow:
            // The two-line chevron, stroked — UML's "uses" arrow.
            var path = Path()
            path.move(to: back(length, spread: 0.45))
            path.addLine(to: tip)
            path.addLine(to: back(length, spread: -0.45))
            return Rendering(path: path, fill: false)
        case .diamond:
            // UML aggregation: a filled rhombus whose long axis rides the
            // line, tip at the endpoint.
            var path = Path()
            let mid = back(length / 2, spread: 0.35)
            let midOpposite = back(length / 2, spread: -0.35)
            path.move(to: tip)
            path.addLine(to: mid)
            path.addLine(to: back(length, spread: 0))
            path.addLine(to: midOpposite)
            path.closeSubpath()
            return Rendering(path: path, fill: true)
        case .circle:
            // The OPEN ring (dot is the filled variant), centered one radius
            // back so it kisses the endpoint.
            let radius = max(3, lineWidth * 1.5)
            let center = back(radius, spread: 0)
            return Rendering(
                path: Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2)),
                fill: false)
        case .cross:
            // UML "no more" / blocked marker: an X across the line one
            // half-length back.
            var path = Path()
            let center = back(length / 2, spread: 0)
            let arm = length / 2
            let perpendicular = angle + .pi / 2
            let along = CGVector(dx: cos(angle) * arm / 2, dy: sin(angle) * arm / 2)
            let across = CGVector(dx: cos(perpendicular) * arm / 2,
                                  dy: sin(perpendicular) * arm / 2)
            path.move(to: CGPoint(x: center.x - along.dx - across.dx,
                                  y: center.y - along.dy - across.dy))
            path.addLine(to: CGPoint(x: center.x + along.dx + across.dx,
                                     y: center.y + along.dy + across.dy))
            path.move(to: CGPoint(x: center.x - along.dx + across.dx,
                                  y: center.y - along.dy + across.dy))
            path.addLine(to: CGPoint(x: center.x + along.dx - across.dx,
                                     y: center.y + along.dy - across.dy))
            return Rendering(path: path, fill: false)
        }
    }
}
#endif
