import AppKit
import SwiftUI

/// Which environment this bundle is looking at, and how it says so.
///
/// Derived from the RESOLVED ROOT, never a build flag: a `#if` would be a second source of
/// truth, and the disagreement that matters is a build wearing non-production chrome while
/// resolving `~/gmfs`. The baked Info.plist key is what makes the root unspoofable.
///
/// `Paths.isProductionRoot` compares `(st_dev, st_ino)` of `gm.db` rather than paths, because
/// `standardizedFileURL` does not resolve symlinks and a firmlink makes one root look like two.
enum EnvironmentKind: Sendable {
    case production
    case beta
    case test

    /// Resolve from the root this process actually opened.
    ///
    /// The declared `GMEnvironment` label is used only to tell BETA from TEST,
    /// never to decide whether we are on production — that answer comes from the
    /// filesystem. A label that could override the root would reintroduce the
    /// second source of truth this type exists to remove.
    static var current: EnvironmentKind {
        if Paths.isProductionRoot { return .production }
        switch Paths.declaredEnvironmentName?.lowercased() {
        case "beta": return .beta
        default: return .test
        }
    }

    var isProduction: Bool { self == .production }

    /// The single letter the menu bar and Dock carry.
    var badge: String {
        switch self {
        case .production: return ""
        case .beta: return "B"
        case .test: return "T"
        }
    }

    var displayName: String {
        switch self {
        case .production: return "Production"
        case .beta: return "Beta"
        case .test: return "Test"
        }
    }

    /// The banner colour.
    ///
    /// Red for test, amber for beta — distinct because mistaking beta for
    /// test is a different mistake from mistaking either for production, and
    /// a single "not prod" colour would hide that.
    var bannerColor: Color {
        switch self {
        case .production: return .clear
        case .beta: return Color(nsColor: .systemOrange)
        case .test: return Color(nsColor: .systemRed)
        }
    }

    /// The pane's BACKGROUND tint as a bare hex string, with no leading `#`. `nil` on
    /// production, and nil emits no escape at all.
    ///
    /// Not `bannerColor`: that is a 22pt fill over app chrome and is unreadable as the ground
    /// behind terminal text, so these are two quantities rather than two descriptions of one.
    /// Terminal contrast is not a linear function of a UI fill, so neither derives from the
    /// other. KEEP THE TINTS DARK AND LOW-SATURATION; never `systemOrange`.
    var paneBackgroundHex: String? {
        switch self {
        case .production: return nil
        case .beta: return "3a2410"  // dark amber
        case .test: return "3a1414"  // dark red
        }
    }
}

/// The always-visible bar a non-production window carries.
///
/// Correct AT FIRST PAINT, which is the whole requirement. `Paths.root` reads
/// the bundle key synchronously in-process, so this renders the truth on frame
/// zero — unlike the daemon's `PATHS_GET` answer, which arrives after the window
/// is already on screen and would flash production chrome first.
struct EnvironmentBanner: View {
    private let kind: EnvironmentKind

    /// Creates an environment banner for the given environment kind.
    ///
    /// - Parameter kind: The environment to display; defaults to the current environment.
    init(kind: EnvironmentKind = .current) {
        self.kind = kind
    }

    var body: some View {
        if kind.isProduction {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Text(kind.badge).font(.system(size: 10, weight: .heavy, design: .rounded))
                Text(kind.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                // The ROOT, spelled out. A banner saying "TEST" tells you the
                // build's intent; the path tells you what it will actually
                // write, and only the second one is checkable.
                Text(Paths.root.path)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(kind.bannerColor)
            .foregroundStyle(.white)
        }
    }
}

/// Dock-tile badging.
///
/// The tile is CONDITIONAL: `INFOPLIST_KEY_LSUIElement = YES` leaves the app menu-bar
/// resident with no Dock tile until a window opens, so a Dock badge cannot be the primary
/// signal. The always-visible signals are the menu-bar glyph and the banner above.
///
/// Call this after the activation policy changes. It is a no-op on production and when there
/// is no tile to draw on.
@MainActor
enum EnvironmentDockBadge {

    /// Updates the Dock icon with an environment badge.
    ///
    /// A no-op on production and when there is no Dock tile.
    ///
    /// - Parameter kind: The environment to badge; defaults to the current environment.
    static func apply(kind: EnvironmentKind = .current) {
        guard !kind.isProduction else {
            NSApp.applicationIconImage = nil  // back to the bundle icon
            return
        }
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.applicationIconImage = badged(kind: kind)
    }

    /// Composites the environment letter over the app icon.
    ///
    /// - Parameter kind: The environment kind to badge on the icon.
    /// - Returns: A new image with the badge, or nil if the icon cannot be rendered.
    private static func badged(kind: EnvironmentKind) -> NSImage? {
        let base = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        guard let base else { return nil }
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))

        let inset: CGFloat = 40
        let diameter: CGFloat = 300
        let circle = NSRect(
            x: size.width - diameter - inset,
            y: inset,
            width: diameter,
            height: diameter
        )
        NSColor(
            cgColor: kind == .beta
                ? NSColor.systemOrange.cgColor
                : NSColor.systemRed.cgColor
        )?
        .setFill()
        NSBezierPath(ovalIn: circle).fill()

        let letter = kind.badge as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 210, weight: .heavy),
            .foregroundColor: NSColor.white,
        ]
        let textSize = letter.size(withAttributes: attributes)
        letter.draw(
            at: NSPoint(
                x: circle.midX - textSize.width / 2,
                y: circle.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )

        image.unlockFocus()
        return image
    }
}
