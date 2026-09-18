import AppKit

/// The menu bar glyph: a single snow-capped summit, drawn as line work.
///
/// This IS a template image, and that is the whole design. The status bar
/// flattens a template to one tint and adapts it to light and dark bars, to
/// menu-bar tinting and to the highlighted state — which is what makes a glyph
/// sit in a row of system icons instead of next to them. The colour version
/// this replaced had to opt out of all of that to keep its green, and then had
/// to carry its own outline to survive a light bar. None of that is needed once
/// the icon is monochrome.
///
/// So: STROKES ONLY, no fill. Drawn in black — the tint is the system's to
/// choose, and a template's colour information is discarded anyway; only the
/// alpha survives. SF Symbols' proportions are the reference, which is why the
/// line weight is a fraction of the box rather than a fixed number: the glyph
/// has to sit at the same visual weight as the symbols on either side of it.
public enum KernelMenuBarIcon {
    /// 18pt is the status bar's usable height; AppKit scales for Retina from
    /// the point size, so the drawing handler stays resolution-independent.
    private static let side: CGFloat = 18

    /// Matched to an SF Symbol at `.regular` weight in the menu bar. Thinner
    /// reads as a hairline against the system icons; thicker closes up the
    /// snow line, whose zigzag has to stay wider than the pen that draws it —
    /// see `snowLine`.
    private static let stroke: CGFloat = 1.15

    public static let image: NSImage = {
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

    /// A filled corner disc carrying the environment letter, knocked out of the
    /// glyph. Drawn as a shape rather than a colour so the icon stays a template.
    private static func drawEnvironmentBadge(_ letter: String) {
        let diameter: CGFloat = 9
        let rect = NSRect(
            x: side - diameter, y: 0, width: diameter, height: diameter)
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
                y: rect.midY - textSize.height / 2),
            withAttributes: attributes)
    }

    private static func draw() {
        NSColor.black.setStroke()

        let body = path(silhouette, closed: true)
        style(body)
        body.stroke()

        let line = path(snowLine, closed: false)
        style(line)
        line.stroke()
    }

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
    // Points are in the 18×18 box, y up (the image is created unflipped), inset
    // far enough that the stroke — which straddles the path, half in and half
    // out — stays inside the box.
    //
    // Line work carries far less detail than a filled silhouette does: the
    // stroke eats the small notches from both sides at once, so the flanking
    // needles of the filled version are gone and ONE shoulder peak carries the
    // app icon's jaggedness. Everything below is the shape that survives being
    // drawn with a 1.25pt pen.

    private static let silhouette: [NSPoint] = [
        NSPoint(x: 2.2, y: 4.4),  // base left
        NSPoint(x: 6.6, y: 11.4),  // shoulder peak
        NSPoint(x: 8.2, y: 9.2),  // notch
        NSPoint(x: 10.8, y: 15.4),  // SUMMIT
        NSPoint(x: 15.8, y: 4.4),  // base right
    ]

    /// An open zigzag across the summit's two flanks, its ends sitting ON them
    /// (solved against each flank, not eyeballed) so the line meets the ridge
    /// instead of stopping short of it or crossing through.
    ///
    /// A snow CAP cannot be drawn in line work — an outlined cap is just a
    /// smaller triangle stacked on the peak, which reads as a second mountain.
    /// The snow line alone is the convention, and the zigzag is what separates
    /// it from a contour line.
    ///
    /// ONE dip, not a zigzag, and that is a size limit rather than a taste.
    /// Above the snow line this mountain is about 4pt wide, so every tooth of a
    /// zigzag has to clear BOTH flanks by more than a stroke width or its
    /// stroke merges with the ridge. Two earlier attempts did merge: the teeth
    /// fused to the left flank and pinched the cap in two, leaving a small
    /// triangular hole by the summit that read as an eye. There is no tooth
    /// count that fits — the shallow V is what the width allows, and it still
    /// says "snow line" rather than "contour" because it dips where a gully
    /// would.
    private static let snowLine: [NSPoint] = [
        NSPoint(x: 8.95, y: 11.0),  // on the left flank
        NSPoint(x: 10.9, y: 9.9),  // the gully
        NSPoint(x: 12.80, y: 11.0),  // on the right flank
    ]

    private static func path(_ points: [NSPoint], closed: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        if closed { path.close() }
        return path
    }
}
