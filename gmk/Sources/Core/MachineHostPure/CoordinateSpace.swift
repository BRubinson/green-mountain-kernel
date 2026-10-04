import CoreGraphics
import Foundation

/// Converts between accessibility coordinates (top-left origin) and Cocoa coordinates (bottom-left origin).
///
/// Both spaces are global and anchored on the primary display, so the flip is about its height. The model
/// holds Cocoa coordinates only; the accessibility shell converts at the boundary.
enum AxCoordinates {
    /// The Cocoa rectangle for an accessibility rectangle.
    ///
    /// - Parameters:
    ///   - rect: A rectangle in accessibility coordinates.
    ///   - primaryHeight: The height of the primary display's frame.
    /// - Returns: The same rectangle in Cocoa coordinates.
    static func axToCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    /// The accessibility rectangle for a Cocoa rectangle.
    ///
    /// - Parameters:
    ///   - rect: A rectangle in Cocoa coordinates.
    ///   - primaryHeight: The height of the primary display's frame.
    /// - Returns: The same rectangle in accessibility coordinates.
    static func cocoaToAx(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    /// The rectangle mirrored about the primary display's horizontal midline; the flip is its own inverse.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to flip.
    ///   - primaryHeight: The height of the primary display's frame.
    /// - Returns: The flipped rectangle.
    private static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}
