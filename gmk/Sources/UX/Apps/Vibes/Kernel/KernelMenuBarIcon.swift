import AppKit

/// The menu bar glyph: a single snow-capped summit, drawn as line work.
///
/// A TEMPLATE image: the status bar flattens it to one tint and adapts it to light and dark
/// bars, to tinting and to the highlighted state, which is what makes a glyph sit in a row of
/// system icons rather than beside them. STROKES ONLY, no fill, drawn in black, since a
/// template discards colour and keeps only alpha. Line weight is a fraction of the box rather
/// than a fixed number, so the glyph carries the same visual weight as the SF Symbols beside it.
enum KernelMenuBarIcon {
    /// 18pt is the status bar's usable height; AppKit scales for Retina from
    /// the point size, so the drawing handler stays resolution-independent.
    private static let side: CGFloat = 18

    /// Matched to an SF Symbol at `.regular` weight in the menu bar.
    ///
    /// Thinner reads as a hairline against the system icons; thicker closes up the snow line, whose zigzag has to stay
    /// wider than the pen that draws it — see `snowLine`.
    private static let stroke: CGFloat = 1.15

    static let image: NSImage = {
        // The environment letter rides the glyph itself, so the menu bar says
        // which database this instance writes even when no window is open —
        // which, under LSUIElement, is most of the time.
        let kind = EnvironmentKind.current
        let image = NSImage(
            size: NSSize(width: side, height: side),
            flipped: false
        ) { _ in
            draw()
            if !kind.isProduction { drawEnvironmentBadge(kind.badge) }
            return true
        }
        // TEMPLATE STAYS TRUE, and the badge is drawn in black rather than red
        // for that reason: template rendering is what lets the status bar tint
        // the glyph with the rest of the row, in both appearances and while
        // highlighted. Opting out to get a red letter would make the icon wrong
        // in dark mode and while the menu is open — the two moments someone is
        // most likely to be looking at it. The COLOURED signal is the banner;
        // this one is a shape.
        image.isTemplate = true
        image.accessibilityDescription =
            kind.isProduction
            ? "GM Kernel"
            : "GM Kernel — \(kind.displayName)"
        return image
    }()

    /// Draw a filled corner disc carrying the environment letter.
    ///
    /// Knocked out of the glyph and drawn as a shape rather than a colour so
    /// the icon stays a template.
    ///
    /// - Parameter letter: The environment letter to draw.
    private static func drawEnvironmentBadge(_ letter: String) {
        let diameter: CGFloat = 9
        let rect = NSRect(
            x: side - diameter,
            y: 0,
            width: diameter,
            height: diameter
        )
        NSColor.black.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let text = letter as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
    }

    /// Draw the glyph silhouette and snow line.
    private static func draw() {
        NSColor.black.setStroke()

        let body = path(silhouette, closed: true)
        style(body)
        body.stroke()

        let line = path(snowLine, closed: false)
        style(line)
        line.stroke()
    }

    /// Apply menu bar styling to a path.
    ///
    /// - Parameter path: The path to style.
    private static func style(_ path: NSBezierPath) {
        path.lineWidth = stroke
        // Round, like the symbols beside it. Mitred joins spike at the summit,
        // and at 18 points that spike is a visible barb rather than a sharp
        // peak.
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
    }

    // MARK: - Geometry
    //
    // Points are in the 18x18 box, y up (the image is created unflipped), inset far enough
    // that the stroke, which straddles the path, stays inside the box.
    //
    // Line work carries less detail than a filled silhouette: the stroke eats small notches
    // from both sides at once, so ONE shoulder peak carries the jaggedness. What follows is
    // the shape that survives a 1.25pt pen.

    private static let silhouette: [NSPoint] = [
        NSPoint(x: 2.2, y: 4.4),  // base left
        NSPoint(x: 6.6, y: 11.4),  // shoulder peak
        NSPoint(x: 8.2, y: 9.2),  // notch
        NSPoint(x: 10.8, y: 15.4),  // SUMMIT
        NSPoint(x: 15.8, y: 4.4),  // base right
    ]

    /// An open dip across the summit's two flanks, its ends solved against each flank so the
    /// line meets the ridge instead of stopping short or crossing through.
    ///
    /// An outlined snow CAP would read as a second mountain, so the snow line alone is the convention.
    ///
    /// ONE dip is a size limit rather than a taste: above the snow line this mountain is about
    /// 4pt wide, so any tooth must clear BOTH flanks by more than a stroke width or its stroke
    /// merges with the ridge.
    private static let snowLine: [NSPoint] = [
        NSPoint(x: 8.95, y: 11.0),  // on the left flank
        NSPoint(x: 10.9, y: 9.9),  // the gully
        NSPoint(x: 12.80, y: 11.0),  // on the right flank
    ]

    /// Create a path from a series of points.
    ///
    /// - Parameters:
    ///   - points: The points to connect.
    ///   - closed: Whether to close the path.
    /// - Returns: The bezier path.
    private static func path(_ points: [NSPoint], closed: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        if closed { path.close() }
        return path
    }
}
