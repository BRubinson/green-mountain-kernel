import Foundation

/// Render-environment knobs shared by the resolver, the views, and the
/// headless screenshot renderer. SwiftUI-free on purpose: the resolver (and
/// its tests) must never need a UI framework.
public struct DiagramRenderEnvironment: Hashable, Sendable {
    public enum ColorScheme: String, Codable, Hashable, Sendable {
        case light
        case dark
    }

    public let colorScheme: ColorScheme
    /// Pixels per point in the exported PNG.
    public let displayScale: Double
    /// Padding around contentBounds.
    public let padding: Double
    /// Entity card layout constants (points, pre-scale).
    public let cardWidth: Double
    public let cardHeaderHeight: Double
    public let cardRowHeight: Double

    public init(
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

    /// Entity card height (points, pre-scale) for a row count. The single
    /// home of the formula — the resolver's frames and DopeCanvasLayout's
    /// generated geometry both call this, so they can never disagree.
    public func cardHeight(rowCount: Int) -> Double {
        cardHeaderHeight + Double(max(rowCount, 1)) * cardRowHeight + 8
    }
}

/// Deterministic domain colors. FNV-1a, NEVER Swift's `Hasher` — Hasher is
/// per-process seed-randomized, and a naive `hashValue` would give the same
/// screenshot different colors on every run. Determinism is a correctness
/// requirement (screenshots diff-able across runs), not a style choice.
public enum DiagramPalette {
    /// Stable hue in [0, 1) for a domain code.
    public static func domainHue(_ code: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in code.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Double(hash % 360) / 360.0
    }
}
