import Foundation

/// Render-environment knobs shared by the resolver, the views, and the headless
/// screenshot renderer.
///
/// SwiftUI-free on purpose: the resolver (and its tests) must never need a UI
/// framework.
struct DiagramRenderEnvironment: Hashable, Sendable {
    enum ColorScheme: String, Codable, Hashable, Sendable {
        case light
        case dark
    }

    let colorScheme: ColorScheme
    /// Pixels per point in the exported PNG.
    let displayScale: Double
    /// Padding around contentBounds.
    let padding: Double
    /// Entity card layout constants (points, pre-scale).
    let cardWidth: Double
    let cardHeaderHeight: Double
    let cardRowHeight: Double

    /// Creates a diagram render environment with layout parameters.
    ///
    /// - Parameters:
    ///   - colorScheme: The color scheme for rendering.
    ///   - displayScale: Pixels per point in the exported PNG.
    ///   - padding: Padding around content bounds.
    ///   - cardWidth: Entity card width in points.
    ///   - cardHeaderHeight: Card header height in points.
    ///   - cardRowHeight: Card row height in points.
    init(
        colorScheme: ColorScheme = .light,
        displayScale: Double = 2,
        padding: Double = 48,
        cardWidth: Double = 260,
        cardHeaderHeight: Double = 40,
        cardRowHeight: Double = 22
    ) {
        self.colorScheme = colorScheme
        self.displayScale = displayScale
        self.padding = padding
        self.cardWidth = cardWidth
        self.cardHeaderHeight = cardHeaderHeight
        self.cardRowHeight = cardRowHeight
    }

    /// Calculates entity card height for a given row count.
    ///
    /// The single home of the formula — the resolver's frames and
    /// DopeCanvasLayout's generated geometry both call this, so they can never
    /// disagree.
    ///
    /// - Parameter rowCount: The number of rows in the card.
    /// - Returns: The card height in points, pre-scale.
    func cardHeight(rowCount: Int) -> Double {
        cardHeaderHeight + Double(max(rowCount, 1)) * cardRowHeight + 8
    }
}

/// Deterministic domain colors.
///
/// FNV-1a, NEVER Swift's `Hasher` — Hasher is per-process seed-randomized, and a
/// naive `hashValue` would give the same screenshot different colors on every
/// run. Determinism is a correctness requirement (screenshots diff-able across
/// runs), not a style choice.
enum DiagramPalette {
    /// Returns a stable hue for a domain code.
    ///
    /// - Parameter code: The domain code.
    /// - Returns: A hue in the range [0, 1).
    static func domainHue(_ code: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in code.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Double(hash % 360) / 360.0
    }
}
