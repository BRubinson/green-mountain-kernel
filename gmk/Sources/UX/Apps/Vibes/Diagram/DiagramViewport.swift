import SwiftUI

/// SALVAGED VERBATIM from Drawing/DrawingModel.swift's `Viewport` (renamed only
/// because the original survives until the Drawing/ tear-out slice).
///
/// Stored as `{offset, zoom}`; USED as a `CGAffineTransform`, so anchored zoom is
/// transform composition instead of hand-rolled algebra. This is the ONLY place
/// screen↔diagram coordinate math lives — the scene renders at `offset/zoom`
/// through the kit's diagram-space offset parameter and scales via
/// `.scaleEffect(zoom)`, which composes to exactly `toScreen`.
struct DiagramViewport: Equatable {
    /// Screen-space translation of the diagram origin.
    var offset: CGSize = .zero
    var zoom: CGFloat = 1

    static let zoomRange: ClosedRange<CGFloat> = 0.05...20

    /// diagram → screen.
    ///
    /// Composition order is fixed here, once, forever.
    var toScreen: CGAffineTransform {
        CGAffineTransform(scaleX: zoom, y: zoom)
            .concatenating(CGAffineTransform(translationX: offset.width, y: offset.height))
    }
    var toCanvas: CGAffineTransform { toScreen.inverted() }

    /// Converts a screen-space point to canvas-space.
    /// - Parameter p: The screen-space point.
    /// - Returns: The canvas-space point.
    func canvasPoint(_ p: CGPoint) -> CGPoint { p.applying(toCanvas) }

    /// Converts a canvas-space point to screen-space.
    /// - Parameter p: The canvas-space point.
    /// - Returns: The screen-space point.
    func screenPoint(_ p: CGPoint) -> CGPoint { p.applying(toScreen) }

    /// Converts a canvas-space rectangle to screen-space.
    /// - Parameter r: The canvas-space rectangle.
    /// - Returns: The screen-space rectangle.
    func canvasRect(_ r: CGRect) -> CGRect { r.applying(toCanvas) }

    /// Zooms while keeping an anchor point fixed to the same diagram location.
    ///
    /// The `anchor` is a screen-space point (pinch centroid or cursor) that remains
    /// pinned to the same diagram-space location during the zoom.
    ///
    /// - Parameters:
    ///   - newZoom: The desired zoom level.
    ///   - anchor: The screen-space point to keep fixed.
    mutating func zoom(to newZoom: CGFloat, anchor: CGPoint) {
        let clamped = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard clamped != zoom else { return }
        let before = canvasPoint(anchor)
        zoom = clamped
        let after = canvasPoint(anchor)
        offset.width += (after.x - before.x) * zoom
        offset.height += (after.y - before.y) * zoom
    }

    /// Centers a diagram-space point within the viewport.
    /// - Parameters:
    ///   - point: The diagram-space point to center.
    ///   - size: The viewport size.
    mutating func center(on point: CGPoint, in size: CGSize) {
        offset = CGSize(
            width: size.width / 2 - point.x * zoom,
            height: size.height / 2 - point.y * zoom
        )
    }
}
