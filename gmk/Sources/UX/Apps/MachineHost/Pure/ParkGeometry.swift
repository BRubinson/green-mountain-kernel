import CoreGraphics
import Foundation

/// Where hidden windows go: nearly off a bottom corner of a display, with a 1pt sliver left inside its visible frame.
///
/// Only bottom corners are used: the window server keeps a title bar below the menu bar, so a window cannot
/// hang off a display's top edge. The corner is chosen per display to overhang its neighbours the least.
enum ParkGeometry {
    /// A bottom corner of a display's visible frame, in Cocoa orientation.
    enum Corner: CaseIterable, Sendable {
        /// Bottom right; the choice on a tie.
        case bottomRight
        /// Bottom left.
        case bottomLeft
    }

    /// The width or height, in points, under which a window's on-screen overlap counts as hidden.
    static let hiddenTolerance: CGFloat = 2

    /// The bottom corner of `display` whose parked window overlaps the other displays the least.
    ///
    /// Each corner is scored with a window as large as the display itself, which bounds any real window, by
    /// the area it would cover on every other display; ties go to `.bottomRight`.
    ///
    /// - Parameters:
    ///   - display: The display the window is parked on.
    ///   - displays: Every connected display, `display` included.
    /// - Returns: The least-overlapping corner.
    static func parkCorner(for display: DisplayGeom, among displays: [DisplayGeom]) -> Corner {
        let others = displays.filter { $0.key != display.key }
        let probeSize = display.frame.size
        let scored = Corner.allCases.map { corner in
            let rect = parkRect(windowSize: probeSize, display: display, corner: corner)
            return (corner, others.reduce(0) { $0 + overlapArea(rect, $1.frame) })
        }
        return scored.min { $0.1 < $1.1 }?.0 ?? .bottomRight
    }

    /// The frame that parks a window of `windowSize` at `corner` of `display`.
    ///
    /// The window hangs off the corner so exactly a 1pt × 1pt sliver stays inside the visible frame.
    ///
    /// - Parameters:
    ///   - windowSize: The window's size, kept unchanged.
    ///   - display: The display the window is parked on.
    ///   - corner: The corner to park at.
    /// - Returns: The parked frame in Cocoa coordinates.
    static func parkRect(windowSize: CGSize, display: DisplayGeom, corner: Corner) -> CGRect {
        let visible = display.visibleFrame
        let originX: CGFloat
        switch corner {
        case .bottomRight: originX = visible.maxX - 1
        case .bottomLeft: originX = visible.minX + 1 - windowSize.width
        }
        let originY = visible.minY + 1 - windowSize.height
        return CGRect(origin: CGPoint(x: originX, y: originY), size: windowSize)
    }

    /// True when `frame` shows no more than a sliver on any display, as a parked or lost window does.
    ///
    /// A window whose overlap with every visible frame is at most `hiddenTolerance` wide or tall is
    /// hidden, whether it sits at a park corner or entirely off screen.
    ///
    /// - Parameters:
    ///   - frame: The window's frame in Cocoa coordinates.
    ///   - displays: Every connected display.
    /// - Returns: Whether the window is effectively hidden.
    static func isParked(frame: CGRect, displays: [DisplayGeom]) -> Bool {
        guard !frame.isEmpty, !displays.isEmpty else { return false }
        return !displays.contains { display in
            let overlap = frame.intersection(display.visibleFrame)
            return !overlap.isNull && overlap.width > hiddenTolerance && overlap.height > hiddenTolerance
        }
    }

    /// The area `lhs` and `rhs` share, zero when they only touch.
    ///
    /// - Parameters:
    ///   - lhs: One rectangle.
    ///   - rhs: The other rectangle.
    /// - Returns: The overlap area in square points.
    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let overlap = lhs.intersection(rhs)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
