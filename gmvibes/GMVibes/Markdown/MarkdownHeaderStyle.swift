import SwiftUI
import GMCCDaemonKit
import AppKit

// Single source of truth for the in-editor markdown header look — the purplish hue and
// the per-level font sizes. Mirrors the size *relationship* of
// MarkdownBlocksView.headingFont(level) but expressed as explicit monospaced point
// sizes so the editor keeps its code-editor feel and the line-number gutter can size
// each row to match the editor's per-line height.
enum MarkdownHeaderStyle {
    /// The body monospaced point size (matches the editor's default text size).
    static let bodyPointSize: CGFloat = 13

    /// A pleasing "purplish" hue for headers; reads well on light and dark backgrounds.
    static let color = Color(red: 0.58, green: 0.36, blue: 0.92)

    /// Body (non-heading) text color. Must be an explicit adaptive color: an absent
    /// (`nil`) foreground in a TextEditor-bound AttributedString renders as black in the
    /// TextKit layer rather than the dynamic label color, so body text turns invisible
    /// on the dark field background. `.primary` resolves to the adaptive label color.
    static let bodyColor: Color = .primary

    /// The editor's body font; the gutter uses the same so rows line up.
    static let bodyFont: Font = .system(size: bodyPointSize, design: .monospaced)

    /// Vertical inset shared by the editor's scroll content and the gutter's top, kept
    /// in one place so the two columns can't drift apart.
    static let verticalPadding: CGFloat = 8
    /// Horizontal inset inside the editor's scroll content.
    static let horizontalPadding: CGFloat = 6
    /// Multiplier from point size to approximate rendered line height. Tuned to the
    /// system monospaced font so gutter rows track the editor's per-line layout.
    static let lineHeightFactor: CGFloat = 1.3

    /// The ATX heading level (1...6) for a line, or nil if it isn't a
    /// heading — the kit's parser rule, so the editor can never highlight a
    /// line the reader won't render as a heading.
    static func headingLevel(of line: String) -> Int? {
        MarkdownDocument.headingLevel(of: line)
    }

    /// Heading font for level 1...6 — largest at h1, easing down to ~body at h6.
    static func font(level: Int) -> Font {
        .system(size: pointSize(level: level), weight: .bold, design: .monospaced)
    }

    /// Point size for a heading level (1...6).
    static func pointSize(level: Int) -> CGFloat {
        switch level {
        case 1:  return bodyPointSize + 9   // ~22
        case 2:  return bodyPointSize + 6   // ~19
        case 3:  return bodyPointSize + 4   // ~17
        case 4:  return bodyPointSize + 2   // ~15
        case 5:  return bodyPointSize + 1   // ~14
        default: return bodyPointSize       // ~13 (h6 / clamps)
        }
    }

    /// Point size for an optional level — body size when nil (a non-heading line).
    static func size(forLevel level: Int?) -> CGFloat {
        level.map(pointSize(level:)) ?? bodyPointSize
    }

    /// Approximate rendered line height for a line at the given (optional) level.
    /// Used to size gutter rows to match the editor's per-line heights.
    static func lineHeight(forLevel level: Int?) -> CGFloat {
        size(forLevel: level) * lineHeightFactor
    }

    /// Approximate monospaced advance width per character at the given level.
    /// Used to estimate the no-wrap content width for horizontal scrolling.
    static func charWidth(forLevel level: Int?) -> CGFloat {
        size(forLevel: level) * 0.62
    }

    /// The SwiftUI font for a whole line at the given (optional) heading level —
    /// the level's bold heading font, or the body font for a non-heading line.
    static func lineFont(forLevel level: Int?) -> Font {
        level.map(font(level:)) ?? bodyFont
    }

    /// Insets that approximate SwiftUI `TextEditor`'s internal text-container
    /// padding on macOS. The per-line editor mirrors these on its hidden sizing
    /// `Text` so the measured (wrapped) height matches the editor's own layout.
    /// Tune here if per-line rows clip or leave slack.
    static let editorInsetH: CGFloat = 5
    static let editorInsetV: CGFloat = 3

    // MARK: - AppKit equivalents

    // The NSTextView-backed editor styles its NSTextStorage with AppKit fonts/colors;
    // these mirror the SwiftUI values above so both render the same look.

    /// Purplish header color as an NSColor (matches `color`).
    static var nsHeaderColor: NSColor { NSColor(srgbRed: 0.58, green: 0.36, blue: 0.92, alpha: 1) }

    /// Adaptive body text color (matches `bodyColor` == .primary).
    static var nsBodyColor: NSColor { .labelColor }

    /// Monospaced font for a whole line at the given (optional) heading level — bold
    /// heading font, or the regular body font for a non-heading line.
    static func nsFont(forLevel level: Int?) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size(forLevel: level),
                                    weight: level != nil ? .bold : .regular)
    }
}
